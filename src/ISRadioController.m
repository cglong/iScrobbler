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

     // SEARCH: window: itunes sidebar (my tags, friends, neighbours search),
    // main panel: play this station, play only music you tagged as "loved" (sub only), go to tag page
    // play user radio, play user neighborhood, play user loved tracks (sub only), go to profile

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
                NSLocalizedString(@"Search for a Station", ""), 0x2026 /*...*/]
                action:@selector(openStationSearch:) keyEquivalent:@""];
            [item setTarget:self];
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
    stationBeingTuned = [[NSDictionary alloc] initWithObjectsAndKeys:url, @"url", name ? name : url, @"name", nil];
    
    [[ASWebServices sharedInstance] tuneStation:url];
}

- (void)skip
{
    [[ASWebServices sharedInstance] exec:@"skip"];
}

- (void)ban
{
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
            [m insertItem:item atIndex:0];
            [item release];
            
            [m insertItem:[NSMenuItem separatorItem] atIndex:1];
        } else
            [item setTitle:title];
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
        
        NSMutableArray *history = [[[NSUserDefaults standardUserDefaults] objectForKey:@"RadioStationHistory"] mutableCopy];
        if ([history count] >= [[NSUserDefaults standardUserDefaults] integerForKey:@"Number of Songs to Save"])
            [history removeLastObject];
        
        // see if we already exist
        int count = [history count];
        int i = 0;
        NSString *match = [station objectForKey:@"url"];
        for (; i < count; ++i) {
            if (NSOrderedSame == [[[history objectAtIndex:i] objectForKey:@"url"] caseInsensitiveCompare:match])
                break;
        }
        if (i < count)
            [history removeObjectAtIndex:i];
        
        // add to front
        [history insertObject:station atIndex:0];
        
        [[NSUserDefaults standardUserDefaults] setObject:history forKey:@"RadioStationHistory"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
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
    
    #ifndef __LP64__
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
        default:
            msg = NSLocalizedString(@"Unknown error.", "");
        break;
    }
    [GrowlApplicationBridge
            notifyWithTitle:NSLocalizedString(@"Failed to tune station", "")
            description:msg
            notificationName:IS_GROWL_NOTIFICATION_ALERTS
            iconData:nil
            priority:0.0
            isSticky:YES
            clickContext:nil];
    #endif
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
    // TOODO: [[rootMenu itemWithTag:MSTATION_SEARCH] setEnabled:YES];
    
    if ([[ASWebServices sharedInstance] subscriber]) {
        [[m itemWithTag:MSTATION_MYRADIO] setEnabled:YES];
        [[m itemWithTag:MSTATION_MYLOVED] setEnabled:YES];
        [[m itemWithTag:MACTION_DISCOVERY] setEnabled:YES];
        [self setDiscoveryMode:nil];
    }
    
    [self setRecordToProfile:nil];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTuneLastRadioStation"]) {
        NSArray *history = [[NSUserDefaults standardUserDefaults] objectForKey:@"RadioStationHistory"];
        if (history && [history count] > 0) {
            NSDictionary *d = [history objectAtIndex:0];
            [self tuneStationWithName:[d objectForKey:@"name"] url:[d objectForKey:@"url"]];
        }
    }
}

- (void)wsFailedHandShake:(NSNotification*)note
{
    [rootMenu setToolTip:NSLocalizedString(@"Radio not connected (failed)", "")];
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
        [np objectForKey:@"track"], @"Name",
        [np objectForKey:@"album"], @"Album",
        [np objectForKey:@"artist"], @"Artist",
        [[[ASWebServices sharedInstance] streamURL] path], @"Location",
        [NSNumber numberWithInt:0], @"Rating",
        [NSNumber numberWithLongLong:(long  long)duration * 1000LL], @"Total Time", // iTunes gives this in milliseconds
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

