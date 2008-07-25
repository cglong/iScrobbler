//
//  ISRadioController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/16/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
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
- (void)radioPlayDidStop;
- (void)setDiscoveryMode:(id)sender;
- (NSDictionary*)lastTunedStation;
@end

#define LAST_STATION_TITLE NSLocalizedString(@"Last Station", "")

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
            ASWebServices *ws = asws;
            
            // Build and insert the Radio menu
            NSMenu *m = [[NSMenu alloc] init];
            [m setAutoenablesItems:NO];
            NSMenuItem *item;
            
            if ([ws needHandshake]) {
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
            
            [m addItem:[NSMenuItem separatorItem]];
            
            NSDictionary *d = [self lastTunedStation];
            NSString *title;
            if (d) {
                title = [NSString stringWithFormat:@"%@: %@", LAST_STATION_TITLE, [d objectForKey:@"name"]];
            } else
                title = LAST_STATION_TITLE;
            item = [[NSMenuItem alloc] initWithTitle:title
                action:@selector(playStation:) keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:MSTATION_LASTTUNED];
            [item setEnabled:NO];
            [item setRepresentedObject:[d objectForKey:@"radioURL"]];
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
            
            title = [NSString stringWithFormat:@"%C ", 0x25FC];
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
            [m release];
            
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTuneLastRadioStation"])
                [ws handshake];
        }
    }
}

- (NSString*)radioPlaylistName
{
    NSString *name;
    return ((name = [[NSUserDefaults standardUserDefaults] stringForKey:@"RadioPlaylist"]) ? name : @"iScrobbler Radio");
}

- (void)handlePlayerError:(NSDictionary*)scriptResponse
{
    OSStatus err = 0;
    NSString *errMsg;
    if ([scriptResponse objectForKey:NSAppleScriptErrorNumber]) {
        err = [[scriptResponse objectForKey:NSAppleScriptErrorNumber] intValue];
    }
    switch (err) {
        case qtsConnectionFailedErr:
        case qtsTimeoutErr:
            errMsg = NSLocalizedString(@"The radio server cannot be contacted.", "");
        break;
        case qtsAddressBusyErr:
            errMsg = NSLocalizedString(@"The radio server is refusing connections.", "");
        break;
        default:
            errMsg = [NSString stringWithFormat:@"%@: %d", NSLocalizedString(@"Unknown error", ""), err];
        break;
    }
    
    errMsg = [NSLocalizedString(@"iTunes received an error attempting to play the station", "")
        stringByAppendingFormat:@": \"%@\"", errMsg];
    [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Failed to play station", "") message:errMsg];
}

- (BOOL)playRadioPlaylist:(BOOL)nextTrack
{
    NSNumber *playing = [NSNumber numberWithBool:NO];
    @try {
        playing = [radioScript executeHandler:!nextTrack ? @"PlayRadioPlaylist" : @"PlayNextRadioTrack"
            withParameters:[self radioPlaylistName], nil];
    } @catch (NSException *ex) {
        ScrobLog(SCROB_LOG_ERR, @"Radio: can't play playlist -- script error: %@.", ex);
        [self handlePlayerError:[ex userInfo]];
    }
    if ([playing boolValue]) {
        NSMenuItem *item = [[rootMenu submenu] itemWithTag:MACTION_STOP];
        [item setEnabled:YES];
    } else
        [self radioPlayDidStop];
    return ([playing boolValue]);
}

- (void)tuneStationWithName:(NSString*)name url:(NSString*)url
{
    [stationBeingTuned release];
    stationBeingTuned = [[NSDictionary alloc] initWithObjectsAndKeys:url, @"radioURL", name ? name : url, @"name", nil];
    
    ASWebServices *ws = asws;
    if ([ws needHandshake]) {
        [ws handshake];
        return;
    }
    
    [self setValue:[NSNumber numberWithBool:YES] forKey:@"isBusy"];
    
    [self stop];
    [ws tuneStation:url];
}

- (void)skip
{
    if ([asws playlistSkipsLeft] > 0)
        [asws decrementPlaylistSkipsLeft];
    else {
        [[NSApp delegate] displayWarningWithTitle:NSLocalizedString(@"Station Skip Limit Exceeded", "")
            message:NSLocalizedString(@"You cannot skip any more tracks in this station due to a limit imposed by last.fm.", "")];
        return;
    }
    SongData *s = [[NSApp delegate] nowPlaying];
    ISASSERT([s isLastFmRadio], "not a radio track!");
    ISASSERT([[s playerUUID] isEqualTo:currentTrackID], "tracks don't match!");
    [s setSkipped:YES];
    #ifdef obsolete
    [asws exec:@"skip"]; // this is not necessary as the skip is handled by the submission of the track
    #endif
    [self playRadioPlaylist:YES];
}

- (void)ban
{
    SongData *s = [[NSApp delegate] nowPlaying];
    ISASSERT([s isLastFmRadio], "not a radio track!");
    ISASSERT([[s playerUUID] isEqualTo:currentTrackID], "tracks don't match!");
    [s setBanned:YES];
    [self playRadioPlaylist:YES];
    [[NSApp delegate] banTrack:s];
}

- (void)radioPlayDidStop
{
    @try {
        (void)[radioScript executeHandler:@"EmptyRadioPlaylst" withParameters:[self radioPlaylistName], nil];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Radio: can't empty playlist -- script error: %@.", exception);
    }
    
    [currentTrackID release];
    currentTrackID = nil;
    [activeRadioTracks removeAllObjects];
    [asws stop];
    [stationBeingTuned release];
    stationBeingTuned = nil;
    [self performSelector:@selector(setNowPlayingStation:) withObject:nil];
    [[[rootMenu submenu] itemWithTag:MACTION_STOP] setEnabled:NO];
}

- (void)stop
{
    [asws stop];
    [[NSApp delegate] playerStop];
    [self radioPlayDidStop];
}

- (void)playStation:(id)sender
{
    if ([sender respondsToSelector:@selector(representedObject)]) {
        
        id o = [sender representedObject];
        #ifdef notyet
        if (!o) {
            // get the last played station
        }
        #endif
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
    [asws setDiscovery:enabled];
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

- (NSDictionary*)lastTunedStation
{
    NSArray *history = [[NSUserDefaults standardUserDefaults] objectForKey:@"RadioStationHistory"];
    if (history && [history count] > 0) {
        return ([history objectAtIndex:0]);
    }
    return (nil);
}

- (void)setNowPlayingStation:(NSDictionary*)station
{
    #define MACTION_NPRADIO MACTION_CONNECTRADIO
    NSMenu *m = [rootMenu submenu];
    NSMenuItem *item = [m itemWithTag:MACTION_NPRADIO];
    if (station) {
        NSString *title = [NSString stringWithFormat:@"%@: %@", IS_RADIO_TUNEDTO_STR, [station objectForKey:@"name"]];
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
        NSInteger i = [m indexOfItem:item] + 1;
        if (i < [m numberOfItems] && [[m itemAtIndex:i] isSeparatorItem])
            [m removeItemAtIndex:i];
        [m removeItem:item];
    }
        
}

- (void)addStationToHistory:(NSDictionary*)station
{
    if (station) {
        // Intialize last station item
        NSMenuItem *item = [[rootMenu submenu] itemWithTag:MSTATION_LASTTUNED];
        [item setTitle:LAST_STATION_TITLE];
        [item setRepresentedObject:nil];
        [item setEnabled:NO];
        
        @try {
        
        NSMutableArray *history = [[[[NSUserDefaults standardUserDefaults] objectForKey:@"RadioStationHistory"] mutableCopy] autorelease];
        NSInteger count;
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
        
        if ([history count] >= count) {
            NSRange del;
            del.length = [history count] - count;
            if (0 == del.length)
                [history removeLastObject];
            else {
                del.location = count;
                [history removeObjectsInRange:del];
            }
        }
        
        // see if we already exist
        count = [history count];
        NSInteger i = 0;
        NSString *match = [station objectForKey:@"radioURL"];
        for (; i < count; ++i) {
            if (NSOrderedSame == [[[history objectAtIndex:i] objectForKey:@"radioURL"] caseInsensitiveCompare:match])
                break;
        }
        if (i < count)
            [history removeObjectAtIndex:i];
        
        // add to front
        [history insertObject:station atIndex:0];
        
        // finally, update the last station item
        [item setTitle:[NSString stringWithFormat:@"%@: %@", LAST_STATION_TITLE, [station objectForKey:@"name"]]];
        [item setRepresentedObject:[station objectForKey:@"radioURL"]];
        [item setEnabled:YES];
        
exitHistory:
        [[NSUserDefaults standardUserDefaults] setObject:history forKey:@"RadioStationHistory"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:ISRadioHistoryDidUpdateNotification object:self];
        
        } @catch (id e) {
            ScrobLog(SCROB_LOG_ERR, @"Radio: exception adding station to history: %@", e);
        }
    }
}

- (void)addPlaylistTracksToiTunes:(NSArray*)tracks
{
    NSEnumerator *en = [tracks objectEnumerator];
    NSDictionary *track;
    NSString *m3u, *uuid;
    while ((track = [en nextObject])) {
        @try {
            m3u = [NSString stringWithFormat:@"#EXTM3U\n\n#EXTINF:%li,%@\n%@\n",
                [[track objectForKey:ISR_TRACK_DURATION] longValue] / 1000L,
                [track objectForKey:ISR_TRACK_TITLE], [track objectForKey:ISR_TRACK_URL]];
            
            NSString *path = [@"/tmp" stringByAppendingPathComponent:
                [[[[track objectForKey:ISR_TRACK_URL] lastPathComponent]
                    stringByDeletingPathExtension] stringByAppendingPathExtension:@"m3u"]];
            if ([m3u writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]) {
                uuid = [radioScript executeHandler:@"AddRadioTrack" withParameters:[self radioPlaylistName], 
                    [track objectForKey:ISR_TRACK_TITLE], [track objectForKey:ISR_TRACK_ARTIST],
                    [track objectForKey:ISR_TRACK_ALBUM], [track objectForKey:ISR_TRACK_URL], path, nil];
                if (uuid && [uuid length] > 0) {
                    ISASSERT(nil == [activeRadioTracks objectForKey:uuid], "track is already active!");
                    [activeRadioTracks setObject:track forKey:uuid];
                } else
                    ScrobLog(SCROB_LOG_ERR, @"Radio: failed to add track to iTunes: %@ (peristent id missing).", track);
                #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
                (void)[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                #else
                (void)[[NSFileManager defaultManager] removeFileAtPath:path handler:nil];
                #endif
            } else
                ScrobLog(SCROB_LOG_ERR, @"Radio: failed to add track to iTunes: %@ (m3u creation failed).", track);
        } @catch (NSException *exception) {
            ScrobLog(SCROB_LOG_ERR, @"Radio: exception adding track to iTunes: %@ (%@).", track, exception);
        }
    }
    
    if ([activeRadioTracks count] > 0) {
        SongData *s = [[NSApp delegate] nowPlaying];
        if (!s || ![s isLastFmRadio])
            [self playRadioPlaylist:NO];
    }
}

- (void)wsStationTuned:(NSNotification*)note
{
    // use the station info from last.fm if possible
    NSDictionary *d = [note userInfo];
    NSString *sname = [d objectForKey:@"stationname"];
    NSString *surl = [[d objectForKey:@"url"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
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
    
    // don't clear the busy state as the playlist needs to update
    [asws updatePlaylist];
}

- (NSString*)wsErrorMessageFromNotification:(NSNotification*)note
{
    int err = [note userInfo] ? [[[note userInfo] objectForKey:@"error"] intValue] : 0;
    NSString *msg = @"";
    switch (err) {
        case 0:
            msg = NSLocalizedString(@"A network error occurred.", "");
        break;
        case 1:
            msg = NSLocalizedString(@"There is not enough content to play the station. Due to restrictions imposed by the music labels, a radio station must have more than 15 tracks; each by different artists.", "");
        break;
        case 2:
            msg = NSLocalizedString(@"The group does not have enough members to have a radio station.", "");
        break;
        case 3:
            msg = NSLocalizedString(@"The artist does not have enough fans to have a radio station.", "");
        break;
        case 4:
            msg = NSLocalizedString(@"The station is not available for streaming.", "");
        break;
        case 5:
            msg = NSLocalizedString(@"The station is available to subscribers only.", "");
        break;
        case 6:
            msg = NSLocalizedString(@"The user does not have enough neighbors to have a radio station.", "");
        break;
        case 7:
        case 8:
            msg = NSLocalizedString(@"The stream has stopped. Please try again later, or try another station.", "");
        break;
        case -1: // empty response from server
            msg = NSLocalizedString(@"The station may not exist or may not be properly setup.", "");
        break;
        default:
            msg = NSLocalizedString(@"An unknown error occurred.", "");
        break;
    }
    return (msg);
}

- (void)wsStationTuneFailure:(NSNotification*)note
{
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"isBusy"];
    
    [self setNowPlayingStation:nil];
    [stationBeingTuned release];
    stationBeingTuned = nil;
    
    [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Failed to Tune Station", "")
        message:[self wsErrorMessageFromNotification:note]];
}

- (void)wsWillHandShake:(NSNotification*)note
{
    [self setValue:[NSNumber numberWithBool:YES] forKey:@"isBusy"];
    
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
    [[m itemWithTag:MSTATION_LASTTUNED] setEnabled:NO];
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
    
    item = [m itemWithTag:MSTATION_LASTTUNED];
    if ([item representedObject])
        [item setEnabled:YES];
    
    if ([asws subscriber]) {
        [[m itemWithTag:MSTATION_MYRADIO] setEnabled:YES];
        [[m itemWithTag:MSTATION_MYLOVED] setEnabled:YES];
        [[m itemWithTag:MACTION_DISCOVERY] setEnabled:YES];
        [self setDiscoveryMode:nil];
    }
    
    [self setRecordToProfile:nil];
    
    [[NSApp delegate] displayProtocolEvent:NSLocalizedString(@"Connected to Last.fm Radio", "")];
    
    if (!stationBeingTuned && [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTuneLastRadioStation"]) {
        NSDictionary *d = [self lastTunedStation];
        if (d) {
            [self tuneStationWithName:[d objectForKey:@"name"] url:[d objectForKey:@"radioURL"]];
        }
    } else if (stationBeingTuned) {
        // station waiting for handshaked, tune it
        [asws tuneStation:[stationBeingTuned objectForKey:@"radioURL"]];
        // leave 'stationBeingTuned' in tact for NP/history updates
    }
    
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"isBusy"];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:OPEN_FINDSTATIONS_WINDOW_AT_LAUNCH]) {
        [[ISRadioSearchController sharedController] showWindow:nil];
    }
}

- (void)wsFailedHandShake:(NSNotification*)note
{
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"isBusy"];
    
    [rootMenu setToolTip:NSLocalizedString(@"Radio not connected (failed)", "")];
    [[NSApp delegate] displayProtocolEvent:NSLocalizedString(@"Failed to connect to Last.fm Radio", "")];
}

- (void)wsNowPlayingUpdate:(NSNotification*)note
{
    NSArray *playlist = [[note userInfo] objectForKey:ISR_PLAYLIST];
    [self performSelector:@selector(addPlaylistTracksToiTunes:) withObject:playlist afterDelay:0.0];
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"isBusy"];
}

- (void)wsNowPlayingFailed:(NSNotification*)note
{
    ScrobLog(SCROB_LOG_ERR, @"Radio: Failed to get playlist data");
    if (0 == [activeRadioTracks count])
        [self wsStationTuneFailure:note];
    else {
        [self setValue:[NSNumber numberWithBool:NO] forKey:@"isBusy"];
        [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Failed to Retrieve Additional Station Content", "")
            message:[self wsErrorMessageFromNotification:note]];
    }
}

- (void)wsExecComplete:(NSNotification*)note
{
}

#ifdef ISDEBUG
- (BOOL)isActiveRadioSong:(SongData*)s
{
    NSDictionary *d = [activeRadioTracks objectForKey:[s playerUUID]];
    return (d && NSOrderedSame == [[d objectForKey:ISR_TRACK_TITLE] caseInsensitiveCompare:[s title]]
        && NSOrderedSame == [[d objectForKey:ISR_TRACK_ARTIST] caseInsensitiveCompare:[s artist]]);
}
#endif

- (void)nowPlaying:(NSNotification*)note
{
    BOOL radioPlaying = ![asws stopped];
    SongData *s = [note object];
    if (radioPlaying && [[[note userInfo] objectForKey:@"isStopped"] boolValue]) {
        [self radioPlayDidStop];
        return;
    }
    
    if (s && ![s isLastFmRadio]) {
        if (radioPlaying)
            [self radioPlayDidStop];
        return;
    } else if (currentTrackID && (!s || ![currentTrackID isEqualTo:[s playerUUID]])) {
        // current track stopped or paused (pause is not allowed by last.fm, so it's effectively a stop)
        [activeRadioTracks removeObjectForKey:currentTrackID];
        
        @try {
            (void)[radioScript executeHandler:@"RemoveRadioTrack" withParameters:[self radioPlaylistName], currentTrackID, nil];
        } @catch (NSException *exception) {
            ScrobLog(SCROB_LOG_ERR, @"Radio: can't remove radio track '%@' -- script error: %@.", [s brief], exception);
        }
        
        [currentTrackID release];
        currentTrackID = [[s playerUUID] retain];
        #ifdef ISDEBUG
        if (currentTrackID)
            ISASSERT([self isActiveRadioSong:s], "current track is not in the active radio list!");
        #endif
    } else if (!currentTrackID && s && [s isLastFmRadio]) {
        currentTrackID = [[s playerUUID] retain];
        ISASSERT(currentTrackID && [self isActiveRadioSong:s], "current track is not in the active radio list!");
    }
    
    if (radioPlaying && [activeRadioTracks count] <= 1) {
        [self setValue:[NSNumber numberWithBool:YES] forKey:@"isBusy"];
        [asws updatePlaylist];
    }
}

- (void)iTunesPlayerDialogHandler:(NSNotification*)note
{
    id showing = [[note userInfo] objectForKey:@"Showing Dialog"];
    if (showing && 0 == [showing intValue] && currentTrackID) {
        NSString *trackID = [[currentTrackID copy] autorelease];
        @try {
            NSNumber *pos = [radioScript executeHandler:@"GetPositionOfTrack" withParameters:trackID, nil];
            SongData *s = [[NSApp delegate] nowPlaying];
            if (s && currentTrackID && [trackID isEqualTo:currentTrackID] && [trackID isEqualTo:[s playerUUID]]) {
                if ([pos longValue] >= 0) {
                    NSNumber *elapsed = [s elapsedTime];
                    NSInteger paused = [elapsed longValue] - [pos longValue] + [[s pausedTime] longValue];
                    if (paused > 0) {
                        [s setPausedTime:[NSNumber numberWithLong:paused]];
                        ISASSERT([[s elapsedTime] isLessThanOrEqualTo:pos], "invalid elapsed time!");
                    }
                    ScrobLog(SCROB_LOG_TRACE, @"Radio: adjusted current track elapsed time from %@s to %@s",
                        elapsed, [s elapsedTime]);
                } else
                    ScrobLog(SCROB_LOG_WARN, @"Radio: lost current track while updating elapsed time (script).");
            } else
                ScrobLog(SCROB_LOG_WARN, @"Radio: lost current track while updating elapsed time.");
        } @catch (NSException *exception) {
            ScrobLog(SCROB_LOG_ERR, @"Radio: can't get elapsed time of current track -- script error: %@.", exception);
        }
        
    }
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
    if (context)
        [[NSNotificationCenter defaultCenter] removeObserver:self name:context object:nil];
    
    [NSApp activateIgnoringOtherApps:YES];
    
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
                priority:0
                isSticky:YES
                clickContext:context];
        } else {
            [self performSelector:@selector(registerAsDefaultLastFMRadioPlayer:) withObject:nil afterDelay:0.3];
        }
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
    
    // for Leopard compat we must use NSPropertySpecifier and not NSUniqueIDSpecifier
    spec = [[NSPropertySpecifier alloc]
        initWithContainerClassDescription:(NSScriptClassDescription *)[NSApp classDescription]
        containerSpecifier:nil key:@"radioController"];
    return (spec);
}

- (NSString*)uniqueID
{
    return (AS_RADIO_UUID);
}

- (NSString*)name
{
    return (@"lastfm radio controller");
}

- (BOOL)connected
{
    return (![asws needHandshake]);
}

- (void)setConnected:(BOOL)connect
{
    if (connect)
        [asws handshake];
}

- (BOOL)subscribed
{
    return ([asws subscriber]);
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
        [self tuneStationWithName:nil url:s];
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

- (BOOL)isBusy
{
    return (isBusy > 0);
}

- (void)setIsBusy:(BOOL)busy
{
    if (busy) {
        if (0 == isBusy)
            [rootMenu setEnabled:NO];
        ++isBusy;
    } else {
        --isBusy;
        if (0 == isBusy)
            [rootMenu setEnabled:YES];
    }
    ISASSERT(isBusy >= 0, "isBusy went south");
    if (isBusy < 0)
        isBusy = 0;
}

- (void)applicationWillTerminate:(NSNotification*)note
{
    if ([self currentStation])
        [self stop];
}

- (id)init
{
    NSURL *file = [NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                stringByAppendingPathComponent:@"Scripts/iTunesLastfmRadio.scpt"]];
    radioScript = [[NSAppleScript alloc] initWithContentsOfURL:file error:nil];
    if (!radioScript || ![radioScript compileAndReturnError:nil]) {
        ScrobLog(SCROB_LOG_CRIT, @"Could not create iTunes radio script!");
        [[NSApp delegate] showApplicationIsDamagedDialog];
        [self autorelease];
        return (nil);
    }
    
    activeRadioTracks = [[NSMutableDictionary alloc] init];
    
    asws = [ASWebServices sharedInstance];

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
    
    [nc addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
    
    // If a stream has to be rebuffered, its eleapsed play time will be longer than the actual time elapsed.
    // We use the dialog notification to check the elasped play time with iTunes.
    // This is iTunes specific (which we try to avoid), but it doesn't actually break anything if we don't
    // get the elapsed play time correct. At worse, a spurious entry will be submitted to last.fm and created in the local charts.
    // XXX
    // However, note that this is kind of hackish in that iTunes may not show a "rebuffering" dialog in future version (7.5+)
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
        selector:@selector(iTunesPlayerDialogHandler:) name:@"com.apple.iTunes.dialogInfo" object:nil];
    
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

- (NSUInteger)retainCount
{
    return (NSUIntegerMax);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end

@interface ISRadioController (SongDataSupport)
- (NSString*)playerUUIDOfCurrentTrack;
- (NSString*)albumImageURLForTrackUUID:(NSString*)uuid;
- (NSNumber*)durationForTrackUUID:(NSString*)uuid;
- (NSString*)authCodeForTrackUUID:(NSString*)uuid;
@end

@implementation ISRadioController (SongDataSupport)

- (NSString*)playerUUIDOfCurrentTrack
{
    NSString *uuid = @"";
    @try {
        uuid = [radioScript executeHandler:@"GetPersistentIDOfCurrentTrack" withParameters:nil];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Radio: failed to get current track uuid -- script error: %@.", exception);
    }
    return (uuid);
}

- (NSString*)albumImageURLForTrackUUID:(NSString*)uuid
{
    return ([[activeRadioTracks objectForKey:uuid] objectForKey:ISR_TRACK_IMGURL]);
}

- (NSNumber*)durationForTrackUUID:(NSString*)uuid
{
    return ([[activeRadioTracks objectForKey:uuid] objectForKey:ISR_TRACK_DURATION]);
}

- (NSString*)authCodeForTrackUUID:(NSString*)uuid
{
    return ([[activeRadioTracks objectForKey:uuid] objectForKey:ISR_TRACK_LFMAUTH]);
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
