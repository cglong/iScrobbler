//
//  ISCrashReporter.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 11/17/07.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "ISCrashReporter.h"

@implementation ISCrashReporter

- (void)windowWillClose:(NSNotificationCenter*)note
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self autorelease];
}

- (BOOL)textView:(NSTextView*)textView clickedOnLink:(id)url atIndex:(unsigned)charIndex
{
    BOOL handled = NO;
    @try {
        handled = [[NSWorkspace sharedWorkspace] openURL:url];
    } @catch (NSException *e) {}
    return (handled);
}

- (void)reportCrashWithArgs:(NSArray*)args
{
    if ([args count] < 2) {
        (void)[self autorelease];
        return;
    }
    
    //NSDate *entryDate = [args objectAtIndex:0];
    NSString *data = [args objectAtIndex:1];
    NSRange r;
    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    // On Tiger, we have to search the data for a marker, if it doesn't exist
    // then read the whole file in the assumption we are dealing with separte log files on Leopard
    r = [data rangeOfString:@"*********" options:NSBackwardsSearch];
    if (NSNotFound != r.location) {
        data = [data substringFromIndex:r.location];
    }
    #endif
    
    NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    
    NSRect frame = [[NSScreen mainScreen] visibleFrame];
    frame.size.width *= .50;
    frame.size.height -= 100.0;
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
        styleMask:NSTitledWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask|NSResizableWindowMask
        backing:NSBackingStoreBuffered defer:NO];
    [w setReleasedWhenClosed:YES];
    [w setLevel:NSModalPanelWindowLevel];
    [w setTitle:[bundleName stringByAppendingFormat:@" %@", NSLocalizedString(@"Crash Report", "")]];
    
    frame = [[w contentView] frame];
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame:frame] autorelease];
    [sv setHasHorizontalScroller:YES];
    [sv setHasVerticalScroller:YES];
    [sv setAutohidesScrollers:YES];
    [sv setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:frame] autorelease];
    [tv setEditable:NO];
    [tv setSelectable:YES];
    [tv setRichText:YES];
    [tv setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    
    LEOPARD_BEGIN
    [tv setGrammarCheckingEnabled:NO];
    [w setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
    LEOPARD_END
    
    NSString *preamble = [@"\n" stringByAppendingFormat:@"%@ %@", bundleName,
        // XXX: iScrobbler specific
        NSLocalizedString(@"appears to have crashed the last time you used it. Check that you are using the very latest version, and if so please copy the following text and report this in the iScrobbler support forum at http://www.last.fm/group/iScrobbler/forum. If possible, please also describe what you were doing when the crash occurred.\n\n", "")];
    NSAttributedString *s = [[[NSMutableAttributedString alloc] initWithString:preamble] autorelease];
    r = [preamble rangeOfString:@"http://www.last.fm/group/iScrobbler/forum"];
    [(NSMutableAttributedString*)s setAttributes:
        [NSDictionary dictionaryWithObjectsAndKeys:
            [NSURL URLWithString:@"http://www.last.fm/group/iScrobbler/forum"], NSLinkAttributeName,
            [NSNumber numberWithInt:1], NSUnderlineStyleAttributeName,
            [NSColor blueColor], NSForegroundColorAttributeName,
            [NSCursor pointingHandCursor], NSCursorAttributeName, nil]
        range:r];
    
    [[tv textStorage] setAttributedString:s];
    
    r.location = [[tv textStorage] length];
    s = [[[NSAttributedString alloc] initWithString:data] autorelease];
    [[tv textStorage] appendAttributedString:s];
    r.length = [s length];
    [tv setSelectedRanges:[NSArray arrayWithObject:[NSValue valueWithRange:r]]];
    
    [sv setDocumentView:tv];
    r.location = r.length = 0;
    [tv scrollRangeToVisible:r];
    [tv setDelegate:self];
    [[w contentView] addSubview:sv];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:)
        name:NSWindowWillCloseNotification object:w];
    [NSApp activateIgnoringOtherApps:YES];
    [w makeKeyAndOrderFront:nil];
    [w center];
}

- (id)initWithReportPath:(NSString*)path
{
    NSDate *lastCheck = [[NSUserDefaults standardUserDefaults] objectForKey:@"CRLastCheck"];
    
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"CRLastCheck"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    if (lastCheck) {
        NSDictionary *attrs;
        #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
        attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        #else
        attrs = [[NSFileManager defaultManager] fileAttributesAtPath:path traverseLink:YES];
        #endif
        
        NSError *error;
        NSDate *modDate = [attrs objectForKey:NSFileModificationDate];
        if (modDate && [modDate isGreaterThanOrEqualTo:lastCheck]) {
            [self performSelector:@selector(reportCrashWithArgs:)
            withObject:[NSArray arrayWithObjects:
                lastCheck, [NSString stringWithContentsOfFile:path encoding:NSMacOSRomanStringEncoding error:&error], nil]
            afterDelay:0.0];
            return (self);
        }
    }
    
    (void)[self autorelease];
    return (nil);
}

+ (BOOL)crashReporter
{
    NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
#ifdef notyet
    if (!bundleName)
        bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"];
#endif        
    if (!bundleName)
        return (NO);
    
    NSString *path;
    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber10_4) {
        path = [[@"~/Library/Logs/CrashReporter/" stringByExpandingTildeInPath]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.crash.log", bundleName]];
    } else {
    #endif
    
    // Leopard logs separate files with the date and host name appended to the bundle name.
    // A "." plist file contains the index of all the crash logs.
    // However, that name also includes the host name (modified to remove to certain characters).
    // It's easier and less brittle to just do a manual search for the most recent log.
    NSString *rootPath = [@"~/Library/Logs/CrashReporter/" stringByExpandingTildeInPath];
    NSDate *logDate = [NSDate distantPast];
    NSDictionary *attrs;
    NSString *logFile;
    NSDirectoryEnumerator *den = [[NSFileManager defaultManager] enumeratorAtPath:rootPath];
    path = nil;
    while ((logFile = [den nextObject])) {
        [den skipDescendents];
        attrs = [den fileAttributes];
        if ([logFile hasPrefix:bundleName] && [[logFile pathExtension] isEqualToString:@"crash"]
        && [[attrs objectForKey:NSFileModificationDate] isGreaterThan:logDate]) {
            logDate = [attrs objectForKey:NSFileModificationDate];
            path = [rootPath stringByAppendingPathComponent:logFile];
        }
    }
    if (!path) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"CRLastCheck"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return (NO);
    }
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    }
    #endif
    
    return ([[ISCrashReporter alloc] initWithReportPath:path] != nil);
}

@end
