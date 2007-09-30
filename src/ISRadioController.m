//
//  ISRadioController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/16/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISRadioController.h"
#import "iScrobblerController.h"
#import "SongData.h"
#import "ASWebServices.h"
#import "ISRadioSearchController.h"
#import "KFAppleScriptHandlerAdditionsCore.h"
#import "KFASHandlerAdditions-TypeTranslation.h"

@interface ISRadioController (RadioPrivate)
- (void)playStation:(id)sender;
- (void)setDiscoveryMode:(id)sender;
@end

@implementation ISRadioController

+ (ISRadioController*)sharedInstance
{
    static ISRadioController *shared = nil;
    return (shared ? shared : (shared = [[ISRadioController alloc] init]));
}

- (void)setRootMenu:(NSMenuItem*)menu
{
    if (menu != rootMenu) {
        [stationBeingTuned release];
        stationBeingTuned = nil;
        
        (void)[menu retain];
        [rootMenu release];
        if ((rootMenu = menu)) {
            ASWebServices *ws = [ASWebServices sharedInstance];
            
            // Build and insert the Radio menu
            NSMenu *m = [[NSMenu alloc] init];
            [m setAutoenablesItems:NO];
            NSMenuItem *item;
            
            if (![ws streamURL]) {
                if (![[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTuneLastRadioStation"]) {
                    item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Connect", "")
                        action:@selector(handshake) keyEquivalent:@""];
                    [item setTarget:ws];
                    [item setTag:MACTION_CONNECTRADIO];
                    [item setEnabled:YES];
                    [m addItem:item];
                    [item release];
                }
                
                [rootMenu setToolTip:NSLocalizedString(@"Radio not connected", "")];
            }
            
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"My Radio", "") // sub only
                action:@selector(playStation:) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MSTATION_MYRADIO];
            [item setEnabled:NO];
            [item setRepresentedObject:[ws stationForCurrentUser:@"personal"]];
            [m addItem:item];
            [item release];
            
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"My Loved Tracks", "") // sub only
                action:@selector(playStation:) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MSTATION_MYLOVED];
            [item setEnabled:NO];
            [item setRepresentedObject:[ws stationForCurrentUser:@"loved"]];
            [m addItem:item];
            [item release];
            
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"My Playlist", "")
                action:@selector(playStation:) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MSTATION_MYPLAYLIST];
            [item setEnabled:NO];
            [item setRepresentedObject:[ws stationForCurrentUser:@"playlist"]];
            [m addItem:item];
            [item release];
            
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"My Recommendations", "")
                action:@selector(playStation:) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MSTATION_RECOMMENDED];
            [item setEnabled:NO];
            [item setRepresentedObject:[ws stationForCurrentUser:@"recommended"]];
            [m addItem:item];
            [item release];
            
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"My Neighborhood", "")
                action:@selector(playStation:) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MSTATION_MYNEIGHBORHOOD];
            [item setEnabled:NO];
            [item setRepresentedObject:[ws stationForCurrentUser:@"neighbours"]];
            [m addItem:item];
            [item release];
            
            item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@%C",
                NSLocalizedString(@"Find a Station", ""), 0x2026 /*...*/]
                action:@selector(showWindow:) keyEquivalent:@""];
            [item setTarget:[ISRadioSearchController sharedController]];
            [item setTag:MSTATION_SEARCH];
            [item setEnabled:NO];
            [m addItem:item];
            [item release];
            
            [m addItem:[NSMenuItem separatorItem]];
            
            NSString *title = [NSString stringWithFormat:@"%C ", 0x25FC];
            item = [[NSMenuItem alloc] initWithTitle:[title stringByAppendingString:NSLocalizedString(@"Stop", "")]
                action:@selector(stop) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MACTION_STOP];
            [item setEnabled:NO];
            [m addItem:item];
            [item release];
            
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Scrobble Radio Plays", "")
                action:@selector(setRecordToProfile:) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MACTION_SCROBRADIO];
            [item setEnabled:NO];
            [m addItem:item];
            [item release];
            
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Discovery Mode", "") // sub only
                action:@selector(setDiscoveryMode:) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MACTION_DISCOVERY];
            [item setEnabled:NO];
            [m addItem:item];
            [item release];
            
            [rootMenu setSubmenu:m];
            
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTuneLastRadioStation"])
                [ws handshake];
        }
    }
}

- (void)tuneStationWithName:(NSString*)name url:(NSString*)url
{
    [stationBeingTuned release];
    stationBeingTuned = [[NSDictionary alloc] initWithObjectsAndKeys:url, @"radioURL", name ? name : url, @"name", nil];
    
    ASWebServices *ws = [ASWebServices sharedInstance];
    if (![ws streamURL]) {
        [ws handshake];
        return;
    }
    
    [ws tuneStation:url];
}

- (void)skip
{
    SongData *s = [[NSApp delegate] nowPlaying];
    ISASSERT([s isLastFmRadio], "not a radio track!");
    [s setSkipped:YES];
    [[ASWebServices sharedInstance] exec:@"skip"];
}

- (void)ban
{
    SongData *s = [[NSApp delegate] nowPlaying];
    ISASSERT([s isLastFmRadio], "not a radio track!");
    [s setBanned:YES];
    [[ASWebServices sharedInstance] exec:@"ban"];
}

- (void)stop
{
    static NSAppleScript *stopScript = nil;
    if (!stopScript) {
        NSURL *file = [NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                    stringByAppendingPathComponent:@"Scripts/iTunesStop.scpt"]];
        stopScript = [[NSAppleScript alloc] initWithContentsOfURL:file error:nil];
        if (!stopScript || ![stopScript compileAndReturnError:nil]) {
            ScrobLog(SCROB_LOG_CRIT, @"Could not create iTunes stop script!");
            [[NSApp delegate] showApplicationIsDamagedDialog];
            return;
        }
    }
    
    @try {
        (void)[stopScript executeAndReturnError:nil];
        [stationBeingTuned release];
        stationBeingTuned = nil;
        [self performSelector:@selector(setNowPlayingStation:) withObject:nil];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Can't stop iTunes -- script error: %@.", exception);
    }
}

- (void)playStation:(id)sender
{
    if ([sender respondsToSelector:@selector(representedObject)]) {
        
        id o = [sender representedObject];
        if (o && [o isKindOfClass:[NSString class]])
            [self tuneStationWithName:[sender title] url:o];
    }
}

- (void)setRecordToProfile:(id)sender
{
    BOOL enabled;
    if (sender) {
        ISASSERT(sender == [[rootMenu submenu] itemWithTag:MACTION_SCROBRADIO], "! radio scrobble menu item");
        if (NSOffState == [sender state]) {
            enabled = YES;
        } else
            enabled = NO;
        
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"RadioPlaysScrobbled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        sender = [[rootMenu submenu] itemWithTag:MACTION_SCROBRADIO];
        enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"RadioPlaysScrobbled"];
        
        if ([sender state] == (enabled ? NSOnState : NSOffState))
            return;
    }
    
    [sender setState:enabled ? NSOnState : NSOffState];
    [[ASWebServices sharedInstance] exec: enabled ? @"rtp" : @"nortp"];
}

- (void)setDiscoveryMode:(id)sender
{
    BOOL enabled;
    if (sender) {
        ISASSERT(sender == [[rootMenu submenu] itemWithTag:MACTION_DISCOVERY], "! discovery menu item");
        if (NSOffState == [sender state]) {
            enabled = YES;
        } else
            enabled = NO;
        
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"RadioDiscoveryMode"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        sender = [[rootMenu submenu] itemWithTag:MACTION_DISCOVERY];
        enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"RadioDiscoveryMode"];
        
        if ([sender state] == (enabled ? NSOnState : NSOffState))
            return;
    }
    
    [sender setState:enabled ? NSOnState : NSOffState];
    [sender setToolTip:enabled ? NSLocalizedString(@"Play all music.", "") : NSLocalizedString(@"Play only music not in your profile.", "")];
    [[ASWebServices sharedInstance] setDiscovery:enabled];
}

- (BOOL)scrobbleRadioPlays
{
    return ([[NSUserDefaults standardUserDefaults] boolForKey:@"RadioPlaysScrobbled"]);
}

- (NSArray*)history
{
    return ([[NSUserDefaults standardUserDefaults] objectForKey:@"RadioStationHistory"]);
}

// private once more

- (void)setNowPlayingStation:(NSDictionary*)station
{
    #define MACTION_NPRADIO MACTION_CONNECTRADIO
    NSMenu *m = [rootMenu submenu];
    NSMenuItem *item = [m itemWithTag:MACTION_NPRADIO];
    if (station) {
        NSString *title = [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Now Playing", ""), [station objectForKey:@"name"]];
        if (!item) {
            item = [[NSMenuItem alloc] initWithTitle:title
                action:nil keyEquivalent:@""];
            [item setTag:MACTION_NPRADIO];
            [item setEnabled:NO];
            [item setRepresentedObject:station];
            [m insertItem:item atIndex:0];
            [item release];
            
            [m insertItem:[NSMenuItem separatorItem] atIndex:1];
        } else {
            [item setTitle:title];
            [item setRepresentedObject:station];
        }
    } else if (item) {
        int i = [m indexOfItem:item] + 1;
        if (i < [m numberOfItems] && [[m itemAtIndex:i] isSeparatorItem])
            [m removeItemAtIndex:i];
        [m removeItem:item];
    }
        
}

- (void)addStationToHistory:(NSDictionary*)station
{
    if (station) {
        @try {
        
        NSMutableArray *history = [[[[NSUserDefaults standardUserDefaults] objectForKey:@"RadioStationHistory"] mutableCopy] autorelease];
        unsigned count;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"Radio Station History Limit"])
            count = [[NSUserDefaults standardUserDefaults] integerForKey:@"Radio Station History Limit"];
        else
            count = [[NSUserDefaults standardUserDefaults] integerForKey:@"Number of Songs to Save"];
        
        if (!count) {
            if (0 == [history count])
                return;
            
            [history removeAllObjects];
            goto exitHistory;
        }
        
        if ([history count] >= count)
            [history removeLastObject];
        
        // see if we already exist
        count = [history count];
        int i = 0;
        NSString *match = [station objectForKey:@"radioURL"];
        for (; i < count; ++i) {
            if (NSOrderedSame == [[[history objectAtIndex:i] objectForKey:@"radioURL"] caseInsensitiveCompare:match])
                break;
        }
        if (i < count)
            [history removeObjectAtIndex:i];
        
        // add to front
        [history insertObject:station atIndex:0];
        
exitHistory:
        [[NSUserDefaults standardUserDefaults] setObject:history forKey:@"RadioStationHistory"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:ISRadioHistoryDidUpdateNotification object:self];
        
        } @catch (id e) {
            ScrobLog(SCROB_LOG_ERR, @"exception adding radio station to history: %@", e);
        }
    }
}

- (void)pingNowPlaying:(NSTimer*)timer
{
    [[ASWebServices sharedInstance] updateNowPlaying];
}

- (void)wsStationTuned:(NSNotification*)note
{
    static NSAppleScript *playURLScript = nil;
    if (!playURLScript) {
        NSURL *file = [NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                    stringByAppendingPathComponent:@"Scripts/iTunesPlayURL.scpt"]];
        playURLScript = [[NSAppleScript alloc] initWithContentsOfURL:file error:nil];
        if (!playURLScript) {
            ScrobLog(SCROB_LOG_CRIT, @"Could not load iTunesPlayURL.scpt!\n");
            [[NSApp delegate] showApplicationIsDamagedDialog];
            return;
        }
    }
    
    @try {
        (void)[playURLScript executeHandler:@"PlayURL" withParameters:
            [[ASWebServices sharedInstance] streamURL], nil];
        [self pingNowPlaying:nil];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Can't play last.fm radio -- script error: %@.", exception);
        NSNotification *n = [NSNotification notificationWithName:ASWSStationTuneFailed
            object:self userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:999999] forKey:@"error"]];
        [self performSelector:@selector(wsStationTuneFailure:) withObject:n afterDelay:0.0];
        return;
    }
    
    // use the station info from last.fm if possible
    NSDictionary *d = [note userInfo];
    NSString *sname = [d objectForKey:@"stationname"];
    NSString *surl = [d objectForKey:@"url"];
    if (sname && surl) {
        [stationBeingTuned release];
        stationBeingTuned = [[NSDictionary alloc] initWithObjectsAndKeys:surl, @"radioURL", sname, @"name", nil];
    }
    if (stationBeingTuned) {
        [self setNowPlayingStation:stationBeingTuned];
        [self addStationToHistory:stationBeingTuned];
        
        [stationBeingTuned release];
        stationBeingTuned = nil;
    }
}

- (void)wsStationTuneFailure:(NSNotification*)note
{
    [self setNowPlayingStation:nil];
    [stationBeingTuned release];
    stationBeingTuned = nil;
    
    int err = [note userInfo] ? [[[note userInfo] objectForKey:@"error"] intValue] : 0;
    NSString *msg = @"";
    switch (err) {
        case 0:
            msg = NSLocalizedString(@"Network error.", "");
            break;
        case 1:
            msg = NSLocalizedString(@"Not enough content.", "");
        break;
        case 2:
            msg = NSLocalizedString(@"Not enough group members.", "");
        break;
        case 3:
            msg = NSLocalizedString(@"Not enough artist fans.", "");
        break;
        case 4:
            msg = NSLocalizedString(@"Not available for streaming.", "");
        break;
        case 5:
            msg = NSLocalizedString(@"You are not a subscriber.", "");
        break;
        case 6:
            msg = NSLocalizedString(@"Not enough neighbors.", "");
        break;
        case 7:
            msg = NSLocalizedString(@"Stopped stream. Please try another station.", "");
        break;
        case 999999:
            msg = NSLocalizedString(@"iTunes received an error attempting to play the station. Please try another station.", "");
        break;
        default:
            msg = NSLocalizedString(@"Unknown error.", "");
        break;
    }
    [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Failed to tune station", "") message:msg];
}

- (void)wsWillHandShake:(NSNotification*)note
{
    [rootMenu setToolTip:[NSString stringWithFormat:@"%@%C",
        NSLocalizedString(@"Radio connecting", ""), 0x2026 /*...*/]];
    
    NSMenu *m = [rootMenu submenu];
    [[m itemWithTag:MACTION_CONNECTRADIO] setEnabled:NO];
    [[m itemWithTag:MSTATION_MYRADIO] setEnabled:NO];
    [[m itemWithTag:MSTATION_MYLOVED] setEnabled:NO];
    [[m itemWithTag:MSTATION_MYPLAYLIST] setEnabled:NO];
    [[m itemWithTag:MSTATION_RECOMMENDED] setEnabled:NO];
    [[m itemWithTag:MSTATION_MYNEIGHBORHOOD] setEnabled:NO];
    [[m itemWithTag:MSTATION_SEARCH] setEnabled:NO];
    [[m itemWithTag:MACTION_SCROBRADIO] setEnabled:NO];
    [[m itemWithTag:MACTION_DISCOVERY] setEnabled:NO];
}

- (void)wsDidHandShake:(NSNotification*)note
{
    [rootMenu setToolTip:NSLocalizedString(@"Radio connected", "")];
    
    NSMenu *m = [rootMenu submenu];
    
    NSMenuItem *item = [m itemWithTag:MACTION_CONNECTRADIO];
    if (item)
        [m removeItem:item];
    
    [[m itemWithTag:MSTATION_RECOMMENDED] setEnabled:YES];
    [[m itemWithTag:MSTATION_MYNEIGHBORHOOD] setEnabled:YES];
    [[m itemWithTag:MSTATION_MYPLAYLIST] setEnabled:YES];
    [[m itemWithTag:MACTION_SCROBRADIO] setEnabled:YES];
    [[m itemWithTag:MSTATION_SEARCH] setEnabled:YES];
    
    if ([[ASWebServices sharedInstance] subscriber]) {
        [[m itemWithTag:MSTATION_MYRADIO] setEnabled:YES];
        [[m itemWithTag:MSTATION_MYLOVED] setEnabled:YES];
        [[m itemWithTag:MACTION_DISCOVERY] setEnabled:YES];
        [self setDiscoveryMode:nil];
    }
    
    [self setRecordToProfile:nil];
    
    [[NSApp delegate] displayProtocolEvent:NSLocalizedString(@"Connected to Last.fm Radio", "")];
    
    if (!stationBeingTuned && [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTuneLastRadioStation"]) {
        NSArray *history = [[NSUserDefaults standardUserDefaults] objectForKey:@"RadioStationHistory"];
        if (history && [history count] > 0) {
            NSDictionary *d = [history objectAtIndex:0];
            [self tuneStationWithName:[d objectForKey:@"name"] url:[d objectForKey:@"radioURL"]];
        }
    } else if (stationBeingTuned) {
        // station waiting for handshaked, tune it
        [[ASWebServices sharedInstance] tuneStation:[stationBeingTuned objectForKey:@"radioURL"]];
        // leave 'stationBeingTuned' in tact for NP/history updates
    }
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:OPEN_FINDSTATIONS_WINDOW_AT_LAUNCH]) {
        [[ISRadioSearchController sharedController] showWindow:nil];
    }
}

- (void)wsFailedHandShake:(NSNotification*)note
{
    [rootMenu setToolTip:NSLocalizedString(@"Radio not connected (failed)", "")];
    [[NSApp delegate] displayProtocolEvent:NSLocalizedString(@"Failed to connect to Last.fm Radio", "")];
}

- (void)wsNowPlayingUpdate:(NSNotification*)note
{
    static NSTimer *ping = nil;
    
    [ping invalidate];
    [ping release];
    ping = nil;
    
    // emulate an iTunes Play event
    NSDictionary *np = [note userInfo];
    NSString *state = np && (NSOrderedSame == [[np objectForKey:@"streaming"] caseInsensitiveCompare:@"true"]) ? @"Playing" : @"Stopped";
    
    if ([state isEqualToString:@"Stopped"]) {
        [[[rootMenu submenu] itemWithTag:MACTION_STOP] setEnabled:NO];
        SongData *s = [[NSApp delegate] nowPlaying];
        if (!s || ![s isLastFmRadio])
            return;
    } else
        [[[rootMenu submenu] itemWithTag:MACTION_STOP] setEnabled:YES];
    
    int duration = np ? [[np objectForKey:@"trackduration"] intValue] : 0;
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
    // last.fm specific keys
        [NSNumber numberWithBool:YES], @"last.fm",
        // albumcover_small
        // album_url
    // iTunes keys
        state, @"Player State",
        [np objectForKey:@"track"], @"Name", // Required
        [np objectForKey:@"artist"], @"Artist", // ditto
        [NSNumber numberWithLongLong:(long  long)duration * 1000LL], @"Total Time", // ditto, iTunes gives this in milliseconds
        [[[ASWebServices sharedInstance] streamURL] path], @"Location",
        [NSNumber numberWithInt:0], @"Rating",
        [np objectForKey:@"album"], @"Album", // may be missing and thus nil
        @"", @"Genre",
        //@"Track Number",
        nil];
    
    if (duration > 0) {
        int progress = [[np objectForKey:@"trackprogress"] intValue];
        duration -= progress;
        ping = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)duration
            target:self selector:@selector(pingNowPlaying:) userInfo:nil repeats:NO];
        (void)[ping retain];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"org.bergstrand.iscrobbler.lasfm.playerInfo" 
        object:self userInfo:d];
}

- (void)wsNowPlayingFailed:(NSNotification*)note
{
    [self wsNowPlayingUpdate:note];
}

- (void)wsExecComplete:(NSNotification*)note
{
    if ([[ASWebServices sharedInstance] nowPlayingInfo])
        [[ASWebServices sharedInstance] updateNowPlaying];
}

- (void)nowPlaying:(NSNotification*)note
{
    if ((![note object] && ![[[note userInfo] objectForKey:@"isPlaying"] boolValue])
        || ![[note object] isLastFmRadio]) {
        [[ASWebServices sharedInstance] stop];
    } else if (![note object])
        [[ASWebServices sharedInstance] updateNowPlaying];
}

- (BOOL)isDefaultLastFMRadioPlayer
{
    NSString* defaultID = (NSString*)LSCopyDefaultHandlerForURLScheme(CFSTR("lastfm"));
    if (defaultID) {
        NSString *myID = [[NSBundle mainBundle] bundleIdentifier];
        [defaultID autorelease];
        return (NSOrderedSame == [myID caseInsensitiveCompare:defaultID]);
    }
    
    return (NO);
}

- (void)setDefaultLastFMRadioPlayer:(BOOL)handler
{
    if (handler)
        (void)LSSetDefaultHandlerForURLScheme(CFSTR("lastfm"), (CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
}

- (void)registerAsDefaultLastFMRadioPlayer:(id)context
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:context object:nil];
    
    NSAlert *a = [NSAlert alertWithMessageText:NSLocalizedString(@"Default Last.fm Radio Player", "")
        defaultButton:NSLocalizedString(@"Make Default", "")
        alternateButton:NSLocalizedString(@"Cancel and Don't Check Again","")
        otherButton:NSLocalizedString(@"Cancel","")
        informativeTextWithFormat:
        NSLocalizedString(@"iScrobbler is not currently your default Last.fm Radio Player. Would you like to make it the default?", ""), nil];
    switch ([a runModal]) {
        case NSAlertDefaultReturn:
            [self setDefaultLastFMRadioPlayer:YES];
        break;
        case NSAlertAlternateReturn:
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CheckDefaultRadioPlayer"];
        break;
        case NSAlertOtherReturn:
        default:
        break;
    }
}

- (void)defaultRadioPlayerCheck
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CheckDefaultRadioPlayer"]
        && ![self isDefaultLastFMRadioPlayer]) {
#ifndef __LP64__ 
        if ([GrowlApplicationBridge isGrowlRunning]) {
            id context = [NSStringFromClass([self class]) stringByAppendingString:
                NSStringFromSelector(@selector(registerAsDefaultLastFMRadioPlayer:))];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(registerAsDefaultLastFMRadioPlayer:)
                name:context object:nil];
            
            [GrowlApplicationBridge
                notifyWithTitle:NSLocalizedString(@"Default Last.fm Radio Player", "")
                description:NSLocalizedString(@"iScrobbler is not currently your default Last.fm Radio Player. Click here for further options.", "")
                notificationName:IS_GROWL_NOTIFICATION_ALERTS
                iconData:nil
                priority:0.0
                isSticky:YES
                clickContext:context];
        }
#endif
    }
}

// AppleScript
#ifdef ISDEBUG
- (id)valueForUndefinedKey:(NSString*)key
{
    ScrobDebug(@"%@", key);
    return (nil);
}
#endif

#define AS_RADIO_UUID @"5482A787-CF01-46D3-875C-706488F9058E"
- (NSScriptObjectSpecifier *)objectSpecifier
{
    static NSScriptObjectSpecifier *spec = nil;
    
    if (spec)
        return (spec);
    
    //spec = [[NSPropertySpecifier alloc]
    spec = [[NSUniqueIDSpecifier alloc]
        initWithContainerClassDescription:(NSScriptClassDescription *)[NSApp classDescription]
        containerSpecifier:nil key:@"radioController"
        uniqueID:AS_RADIO_UUID];
    return (spec);
}

- (NSString*)uniqueID
{
    return (AS_RADIO_UUID);
}

- (NSString*)name
{
    return (AS_RADIO_UUID);
}

- (BOOL)connected
{
    return (nil != [[ASWebServices sharedInstance] streamURL]);
}

- (void)setConnected:(BOOL)connect
{
    if (connect)
        [[ASWebServices sharedInstance] handshake];
}

- (BOOL)subscribed
{
    return ([[ASWebServices sharedInstance] subscriber]);
}

- (BOOL)scriptDiscoveryMode
{
    return ([[NSUserDefaults standardUserDefaults] boolForKey:@"RadioDiscoveryMode"]);
}

- (void)setScriptDiscoveryMode:(BOOL)discover
{
    if ([self subscribed]) {
        [[NSUserDefaults standardUserDefaults] setBool:discover forKey:@"RadioDiscoveryMode"];
        [self setDiscoveryMode:nil];
    }
}

- (BOOL)scriptScrobblePlays
{
    return ([[NSUserDefaults standardUserDefaults] boolForKey:@"RadioPlaysScrobbled"]);
}

- (void)setScriptScrobblePlays:(BOOL)scrob
{
    if ([self subscribed]) {
        [[NSUserDefaults standardUserDefaults] setBool:scrob forKey:@"RadioPlaysScrobbled"];
        [self setDiscoveryMode:nil];
    }
}

- (NSString*)currentStation
{
    NSMenuItem *item = [[rootMenu submenu] itemWithTag:MACTION_NPRADIO];
    return ([[item representedObject] objectForKey:@"name"]);
}

// Commands

- (id)tuneStationScript:(NSScriptCommand*)cmd
{
    NSString *s = [cmd directParameter];
    ScrobDebug(@"%@", s);
    @try {
        [self tuneStationWithName:nil url:[NSURL URLWithString:s]];
    } @catch (id e) {}
    return (nil);
}

- (id)stopPlayingScript:(NSScriptCommand*)cmd
{
    ScrobDebug(@"");
    NSMenuItem *item = [[rootMenu submenu] itemWithTag:MACTION_STOP];
    if (item && [item isEnabled])
        [self performSelector:@selector(stop) withObject:nil afterDelay:0.0];
    return (nil);
}

// End AppleScript

- (id)init
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(wsWillHandShake:) name:ASWSWillHandshake object:nil];
    [nc addObserver:self selector:@selector(wsDidHandShake:) name:ASWSDidHandshake object:nil];
    [nc addObserver:self selector:@selector(wsFailedHandShake:) name:ASWSFailedHandshake object:nil]; 
    [nc addObserver:self selector:@selector(wsStationTuned:) name:ASWSStationDidTune object:nil];
    [nc addObserver:self selector:@selector(wsStationTuneFailure:) name:ASWSStationTuneFailed object:nil];
    [nc addObserver:self selector:@selector(wsNowPlayingUpdate:) name:ASWSNowPlayingDidUpdate object:nil];
    [nc addObserver:self selector:@selector(wsNowPlayingFailed:) name:ASWSNowPlayingFailed object:nil];
    [nc addObserver:self selector:@selector(wsExecComplete:) name:ASWSExecDidComplete object:nil];
    
    [nc addObserver:self selector:@selector(nowPlaying:) name:@"Now Playing" object:nil];
    
    [self defaultRadioPlayerCheck];
    
    return (self);
}

// Singleton support
- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (unsigned)retainCount
{
    return (UINT_MAX);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end

@interface ISScriptCommand : NSScriptCommand {
}
@end

@implementation ISScriptCommand

- (id)performDefaultImplementation
{
    // XXX - this is a hackish way to handle commands to a direct object
    // since our radio controller is a singleton, we just assume the following events go to it
    // http://cocoadev.com/index.pl?DirectParametersAsValues
    switch ([[self commandDescription] appleEventCode]) {
        case 'Tstn': // tune station
            [[ISRadioController sharedInstance] tuneStationScript:self];
        break;
        case 'STop': // stop playing
            [[ISRadioController sharedInstance] stopPlayingScript:self];
        break;
        default:
            ScrobLog(SCROB_LOG_TRACE, @"ISScriptCommand: unknown aevt code: %c", [[self commandDescription] appleEventCode]);
        break;
    }
    return (nil);
}

@end
