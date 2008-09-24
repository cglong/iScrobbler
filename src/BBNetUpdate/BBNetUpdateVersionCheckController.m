/*
* Copyright 2002,2006-2008 Brian Bergstrand.
*
* Redistribution and use in source and binary forms, with or without modification, 
* are permitted provided that the following conditions are met:
*
* 1.	Redistributions of source code must retain the above copyright notice, this list of
*     conditions and the following disclaimer.
* 2.	Redistributions in binary form must reproduce the above copyright notice, this list of
*     conditions and the following disclaimer in the documentation and/or other materials provided
*     with the distribution.
* 3.	The name of the author may not be used to endorse or promote products derived from this
*     software without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
* WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
* AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE
* FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
* OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
* CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
* THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
* $Id$
*/

#import "BBNetUpdateVersionCheckController.h"
#import "BBNetUpdateAskController.h"
#import "BBNetUpdateDownloadController.h"

static UInt32 BBCFVersionNumberFromString(CFStringRef);

static BBNetUpdateVersionCheckController *gVCInstance = nil;

__private_extern__ NSString *BBNetUpdateDidFinishUpdateCheck = @"BBNetUpdateDidFinishUpdateCheck";
#define HTTP_DATE_FMT_RAW @"%a, %d %b %Y %H:%M:%S %Z"

@implementation BBNetUpdateVersionCheckController

+ (void)checkForNewVersion:(NSString*)appName interact:(BOOL)interact
{
   BOOL dontCheck = [[NSUserDefaults standardUserDefaults] boolForKey:@"BBNetUpdateDontAutoCheckVersion"];
   
   if (dontCheck && !interact)
      return;
   
   if (!gVCInstance) {
      gVCInstance =
         [[BBNetUpdateVersionCheckController alloc] initWithWindowNibName:@"BBNetUpdateVersionCheck"];
      if (!gVCInstance) {
         NSBeep();
         return;
      }
      
      [gVCInstance setWindowFrameAutosaveName:@"BBNetUpdateVersionCheck"];
   }
   
   if (![gVCInstance isWindowLoaded]) {
      // Load it
      (void)[gVCInstance window];
   }
   
   if ([(gVCInstance->progressBar) respondsToSelector:@selector(setDisplayedWhenStopped:)])
      [(gVCInstance->progressBar) setDisplayedWhenStopped:NO];
   
   if (!gVCInstance->bundleName) {
       if (!appName)
          gVCInstance->bundleName = [[[NSBundle mainBundle] localizedInfoDictionary] objectForKey:@"CFBundleName"];
       else
          gVCInstance->bundleName = appName;
       (void)[gVCInstance->bundleName retain];
   }
   
   gVCInstance->_interact = interact;
   gVCInstance->_didDownload = NO;
   gVCInstance->checkingVersion = YES;
   
   if (![[NSUserDefaults standardUserDefaults] boolForKey:@"BBNetUpdateDontAskConnect"] && !interact) {
      gVCInstance->_interact = YES;
      [BBNetUpdateAskController askUser:appName delagate:gVCInstance];
   }
   else
      [gVCInstance connect:nil];
}

+ (BOOL)isCheckInProgress
{
   return (gVCInstance && gVCInstance->checkingVersion);
}

+ (NSDate*)lastCheck
{
   id date = [[NSUserDefaults standardUserDefaults] objectForKey:@"BBNetUpdateLastCheck"];
   if ([date isKindOfClass:[NSDate class]])
      return (date);
   
   return (nil);
}

+ (NSString*)userAgent
{
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"BBNetUpdateVersion"];
    if (!ver) {
        if (!(ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]))
            ver = @"";
    }
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (!build)
        build = ver;
    
    NSString *arch =
        #ifdef __ppc__
        @"PPC"
        #elif defined(__i386__)
        @"Intel"
        #elif defined(__x86_64__)
        @"Intel 64-bit"
        #elif defined(__ppc64__)
        @"PPC 64-bit"
        #else
        @"Unknown"
        #endif
        ;
    
    SInt32 majorVer = 0, minorVer = 0, bugFixVer = 0; 
    // These selectors will fail in 10.3.x
    Gestalt(gestaltSystemVersionMajor, &majorVer);
    Gestalt(gestaltSystemVersionMinor, &minorVer);
    Gestalt(gestaltSystemVersionBugFix, &bugFixVer);
    
    NSMutableString *name = [[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] mutableCopy] autorelease];
    [name replaceOccurrencesOfString:@" " withString:@"_" options:0 range:NSMakeRange(0, [name length])];
    
    NSString *agent = [NSString stringWithFormat:@"Mozilla/5.0 (Macintosh; U; %@ Mac OS X %d_%d_%d;) %@/%@(r%@)",
        arch,
        majorVer, minorVer, bugFixVer,
        name,
        ver, build];
        
    return (agent);
}

- (void)connect:(id)sender
{
    if ([BBNetUpdateDownloadController finalizingInstallation]) {
        [fieldTitle setStringValue:NSLocalizedString(@"Installation in Progress", @"")];
        [fieldText setStringValue:NSLocalizedString(@"A new version has been installed and is waiting for the current version to quit.", @"")];
        [buttonDownload setEnabled:NO];
        [[super window] makeKeyAndOrderFront:nil];
        return;
    }

   [fieldTitle setStringValue:NSLocalizedString(@"Requesting Version Data", @"")];
   [fieldText setStringValue:@"The latest version data is being retrieved."];
   
   NSURL *url = [NSURL URLWithString:[[NSDictionary dictionaryWithContentsOfFile:
         [[NSBundle mainBundle] pathForResource:@"BBNetUpdateConfig" ofType:@"plist"]]
         objectForKey:@"BBNetUpdateDownloadInfoURL"]];
   
   if (!url) {
      checkingVersion = NO;
      NSBeep();
      return;
   }
   
   if (_interact)
      [[super window] makeKeyAndOrderFront:nil];
   
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:
        NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    [request setValue:[BBNetUpdateVersionCheckController userAgent] forHTTPHeaderField:@"User-Agent"];
    NSDate *last = [BBNetUpdateVersionCheckController lastCheck];
    if (last && [last isGreaterThan:[NSDate date]]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BBNetUpdateLastCheck"];
        last = nil;
    }
    if (!_interact && last) {
        NSString *since = [last descriptionWithCalendarFormat:HTTP_DATE_FMT_RAW
            timeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"] locale:nil];
        [request setValue:since forHTTPHeaderField:@"If-Modified-Since"]; // conditonal load
    }

    [connection cancel];
    [connection release];
    connection = nil;
    connection = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
    if (!connection) {
      checkingVersion = NO;
      NSBeep();
      return;
    }
    
    checkingVersion = YES;
}

- (IBAction)download:(id)sender
{
   NSSavePanel *op;
   
   if (!verInfo)  {
      [self close];
      return;
   }

    if (installSelf) {
        [BBNetUpdateDownloadController downloadTo:nil from:[verInfo objectForKey:@"File"]
            withHashInfo:[verInfo objectForKey:@"Hash"]];
        [self close];
        return;
    }
   
   // Prompt the user for the save dir.
   op = [NSSavePanel savePanel];
   
   [op beginSheetForDirectory:
      [[NSUserDefaults standardUserDefaults] stringForKey:@"BBNetUpdateLastSavePanelLocation"]
      file:[[verInfo objectForKey:@"File"] lastPathComponent]
      modalForWindow:[super window] modalDelegate:self
      didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

// NSWindowController
- (void)windowWillClose:(NSNotification*)note
{
    if (verInfo) {
        // user chose to cancel a new version, delete the lastCheck key so they are still notified that a new version exists later
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BBNetUpdateLastCheck"];
    }
    
    [connection cancel];
    [connection autorelease];
    connection = nil;
    [verData release];
    verData = nil;
    
   [verInfo release];
   verInfo = nil;
   
   checkingVersion = NO;
   
   if (!_didDownload) {
      // There wasn't a new version, or the user didn't download a new version
      // Either way, send the done notification
      
      [[NSNotificationCenter defaultCenter] postNotificationName:BBNetUpdateDidFinishUpdateCheck
         object:nil];
   }
}

// NSURLConnection delegate methods
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (!verData) {
        verData = [[NSMutableData alloc] init];
        
        [progressBar startAnimation:nil];
        [progressBar displayIfNeeded];
    }
    [verData appendData:data];
}

- (void)connection:(NSURLConnection *)conn didReceiveResponse:(NSURLResponse *)response
{
    if ([response respondsToSelector:@selector(statusCode)]
        && 304 == [(NSHTTPURLResponse*)response statusCode]) {
        // not modified since last check
        [connection cancel];
        [connection autorelease];
        connection = nil;
        [verInfo release]; verInfo = nil;
        
        [progressBar stopAnimation:nil];
        [progressBar displayIfNeeded];
        if (_interact) {
            [fieldTitle setStringValue:NSLocalizedString(@"You Have the Latest Version", @"")];
            [fieldText setStringValue:NSLocalizedString(@"You are using the latest version.", @"")];
            [buttonDownload setTitle:@"OK"];
            [buttonDownload setEnabled:YES];
            [[super window] makeKeyAndOrderFront:nil];
        } else
            [self close];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)conn
{
    NSMutableData *data = [verData autorelease];
    verData = nil;
    
   if (data && [data length] > 0) {
      CFStringRef errstr = NULL;
      BOOL display = NO;
      
      verInfo = (NSDictionary*)CFPropertyListCreateFromXMLData(NULL, (CFDataRef)data, 
         kCFPropertyListImmutable, &errstr);
      if (errstr)
         CFRelease(errstr);
      
      double requiredVer = 0.0;
      if (verInfo) {
         NSString *title, *moreInfo, *newVer, *netVer, *curVer;
         
         @try {
         NSNumber *rver = [verInfo objectForKey:@"MinFoundationVer"];
         if (rver) {
            requiredVer = [rver doubleValue];
         }
         } @catch (id e) {}
         
         if (!(curVer = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"BBNetUpdateVersion"]))
            curVer = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
         netVer = [verInfo objectForKey:@"Version"];
         
         if (netVer)
            [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"BBNetUpdateLastCheck"];
         
         if (NSFoundationVersionNumber < requiredVer) {
            display = _interact; // only display the dialog if the user initiated the check
            [buttonDownload setTitle:@"OK"];
            title = NSLocalizedString(@"Mac OS X Update Needed", "");
            curVer = [verInfo objectForKey:@"MinSysVer"];
            if (netVer && curVer) {
                newVer = [NSString stringWithFormat:
                    NSLocalizedString(@"A new version is available (%@), but it requires Mac OS X %@ or later to install.", ""),
                    netVer,
                    curVer];
            } else
                newVer = NSLocalizedString(@"A new version is available, but it requires a later version of Mac OS X to install.", "");

            [verInfo release]; verInfo = nil;
         } else if (curVer && netVer &&
            (BBCFVersionNumberFromString((CFStringRef)curVer) <
               BBCFVersionNumberFromString((CFStringRef)netVer))) {
            
            NSString *fmt;
            if (installSelf)
                fmt = NSLocalizedString(@"You are using version %@ of %@. Version %@ is now available. Would you like to install the new version?", @"");
            else
                fmt = NSLocalizedString(@"You are using version %@ of %@. Version %@ is now available. Would you like to download the new version?", @"");
            newVer = [NSString stringWithFormat:fmt, curVer, bundleName, netVer];
            
            moreInfo = [[verInfo objectForKey:@"Notes"] objectForKey:@"English"];
            if (moreInfo) {
               [fieldMoreInfo setString:moreInfo];
            }
         
            title = NSLocalizedString(@"A New Version is Available", @"");
            
            // Make sure the user knows there is a new version
            display = YES;
            if (installSelf)
                [buttonDownload setTitle:NSLocalizedString(@"Install", @"")];
            else
                [buttonDownload setTitle:NSLocalizedString(@"Download", @"")];
         } else {
            title = NSLocalizedString(@"You Have the Latest Version", @"");
            newVer = NSLocalizedString(@"You are using the latest version.", @"");
            
            [buttonDownload setTitle:@"OK"];
            [verInfo release]; verInfo = nil;
         }
         
         [buttonDownload setEnabled:YES];
         
         [fieldTitle setStringValue:title];
         [fieldText setStringValue:newVer];
         
         if (display && ![[super window] isVisible])
            [[super window] makeKeyAndOrderFront:nil];
      } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BBNetUpdateLastCheck"];
        // corrupt XML
        [fieldTitle setStringValue:NSLocalizedString(@"Version Data Error", @"")];
        [fieldText setStringValue:NSLocalizedString(@"The version data file appears corrupt.", @"")];
        if (![[super window] isVisible])
            [[super window] makeKeyAndOrderFront:nil];
      }
   } else {
      [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BBNetUpdateLastCheck"];
      // No version data
      [fieldTitle setStringValue:NSLocalizedString(@"Version Data Error", @"")];
      [fieldText setStringValue:NSLocalizedString(@"The server returned empty version data.", @"")];
      if (![[super window] isVisible])
        [[super window] makeKeyAndOrderFront:nil];
   }
   
   [progressBar stopAnimation:nil];
   [progressBar displayIfNeeded];
   
   if (![[super window] isVisible])
      [self close];
}

-(void)connection:(NSURLConnection *)conn didFailWithError:(NSError *)reason
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BBNetUpdateLastCheck"];
    
    if (![[super window] isVisible])
        [[super window] makeKeyAndOrderFront:nil];

    // Alert the user
    NSBeginAlertSheet(NSLocalizedString(@"Update Error", @""),
      @"OK", nil, nil, [super window], self, nil, nil, nil,
    NSLocalizedString(@"An update error has occured, the update has been cancelled. Reason: '%@'", @""), [reason localizedDescription]);

    [fieldTitle setStringValue:NSLocalizedString(@"Could not obtain version data", @"")];

    [buttonDownload setEnabled:NO];

    [progressBar stopAnimation:nil];
    [progressBar displayIfNeeded];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return (nil);
}

- (void)windowDidLoad
{
    [(NSPanel*)[self window] setLevel:NSModalPanelWindowLevel + 1];
    [[self window] setTitle:[NSString stringWithFormat:@"%@ %@",
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"],
        NSLocalizedString(@"Software Update", @"")]];
    [buttonDownload setTitle:@"OK"];
    [buttonDownload setEnabled:NO];
    
    installSelf = [[[NSDictionary dictionaryWithContentsOfFile:
        [[NSBundle mainBundle] pathForResource:@"BBNetUpdateConfig" ofType:@"plist"]]
        objectForKey:@"BBNetUpdateInstallSelf"] boolValue];
    if (installSelf) {
        // If we can't write, then don't allow self install
        NSString *pathToParent = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
        if (NO == [[NSFileManager defaultManager] isWritableFileAtPath:pathToParent])
            installSelf = NO;
    }
}

// Sheet handlers
- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(NSInteger)returnCode contextInfo:(void  *)contextInfo
{
   NSString *file = [sheet filename];
   
   if(NSOKButton == returnCode && file) {
      [[NSUserDefaults standardUserDefaults] setObject:[sheet directory]
         forKey:@"BBNetUpdateLastSavePanelLocation"];
      
      [NSTimer scheduledTimerWithTimeInterval:0.02 target:self
            selector:@selector(close) userInfo:nil repeats:NO];
      
      _didDownload = YES;
      
      [BBNetUpdateDownloadController downloadTo:file from:[verInfo objectForKey:@"File"]
        withHashInfo:[verInfo objectForKey:@"Hash"]];
   }
}

@end

// Pulled the following from Apple's Core Foundation

#define DEVELOPMENT_STAGE 0x20
#define ALPHA_STAGE 0x40
#define BETA_STAGE 0x60
#define RELEASE_STAGE 0x80

#define MAX_VERS_LEN 10

static inline Boolean _isDigit(UniChar aChar) {
    return (((aChar >= (UniChar)'0') && (aChar <= (UniChar)'9')) ? true : false);
}

UInt32 BBCFVersionNumberFromString(CFStringRef versStr) {
    // Parse version number from string.
    // String can begin with "." for major version number 0.  String can end at any point, 
    // but elements within the string cannot be skipped.
    UInt32 major1 = 0, major2 = 0, minor1 = 0, minor2 = 0, stage = RELEASE_STAGE, build = 0;
    UniChar versChars[MAX_VERS_LEN];
    UniChar *chars = NULL;
    CFIndex len;
    UInt32 theVers;
    Boolean digitsDone = false;

    if (!versStr) {
        return 0;
    }

    len = CFStringGetLength(versStr);

    if ((len == 0) || (len > MAX_VERS_LEN)) {
        return 0;
    }

    CFStringGetCharacters(versStr, CFRangeMake(0, len), versChars);
    chars = versChars;
    
    // Get major version number.
    major1 = major2 = 0;
    if (_isDigit(*chars)) {
        major2 = *chars - (UniChar)'0';
        chars++;
        len--;
        if (len > 0) {
            if (_isDigit(*chars)) {
                major1 = major2;
                major2 = *chars - (UniChar)'0';
                chars++;
                len--;
                if (len > 0) {
                    if (*chars == (UniChar)'.') {
                        chars++;
                        len--;
                    } else {
                        digitsDone = true;
                    }
                }
            } else if (*chars == (UniChar)'.') {
                chars++;
                len--;
            } else {
                digitsDone = true;
            }
        }
    } else if (*chars == (UniChar)'.') {
        chars++;
        len--;
    } else {
        digitsDone = true;
    }

    // Now major1 and major2 contain first and second digit of the major version number as ints.
    // Now either len is 0 or chars points at the first char beyond the first decimal point.

    // Get the first minor version number.  
    if (len > 0 && !digitsDone) {
        if (_isDigit(*chars)) {
            minor1 = *chars - (UniChar)'0';
            chars++;
            len--;
            if (len > 0) {
                if (*chars == (UniChar)'.') {
                    chars++;
                    len--;
                } else {
                    digitsDone = true;
                }
            }
        } else {
            digitsDone = true;
        }
    }

    // Now minor1 contains the first minor version number as an int.
    // Now either len is 0 or chars points at the first char beyond the second decimal point.

    // Get the second minor version number. 
    if (len > 0 && !digitsDone) {
        if (_isDigit(*chars)) {
            minor2 = *chars - (UniChar)'0';
            chars++;
            len--;
        } else {
            digitsDone = true;
        }
    }

    // Now minor2 contains the second minor version number as an int.
    // Now either len is 0 or chars points at the build stage letter.

    // Get the build stage letter.  We must find 'd', 'a', or 'b' next, if there is anything next.
    if (len > 0) {
        if (*chars == (UniChar)'d') {
            stage = DEVELOPMENT_STAGE;
        } else if (*chars == (UniChar)'a') {
            stage = ALPHA_STAGE;
        } else if (*chars == (UniChar)'b') {
            stage = BETA_STAGE;
        } else {
            return 0;
        }
        chars++;
        len--;
    }

    // Now stage contains the release stage.
    // Now either len is 0 or chars points at the build number.

    // Get the first digit of the build number.
    if (len > 0) {
        if (_isDigit(*chars)) {
            build = *chars - (UniChar)'0';
            chars++;
            len--;
        } else {
            return 0;
        }
    }
    // Get the second digit of the build number.
    if (len > 0) {
        if (_isDigit(*chars)) {
            build *= 10;
            build += *chars - (UniChar)'0';
            chars++;
            len--;
        } else {
            return 0;
        }
    }
    // Get the third digit of the build number.
    if (len > 0) {
        if (_isDigit(*chars)) {
            build *= 10;
            build += *chars - (UniChar)'0';
            chars++;
            len--;
        } else {
            return 0;
        }
    }

    // Range check the build number and make sure we exhausted the string.
    if ((build > 0xFF) || (len > 0)) {
        return 0;
    }

    // Build the number
    theVers = major1 << 28;
    theVers += major2 << 24;
    theVers += minor1 << 20;
    theVers += minor2 << 16;
    theVers += stage << 8;
    theVers += build;

    return theVers;
}
