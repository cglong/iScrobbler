//
//  iScrobblerController.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Completely re-written by Brian Bergstrand sometime in Feb 2005.
//  Copyright 2005-2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt

#import <openssl/md5.h>

#import <IOKit/IOMessage.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <Carbon/Carbon.h>

#import "iScrobblerController.h"
#import "PreferenceController.h"
#import "SongData.h"
#import "keychain.h"
#import "QueueManager.h"
#import "ProtocolManager.h"
#import "ScrobLog.h"
#import "StatisticsController.h"
#import "TopListsController.h"
#import "KFAppleScriptHandlerAdditionsCore.h"
#import "KFASHandlerAdditions-TypeTranslation.h"
#import "BBNetUpdate/BBNetUpdateVersionCheckController.h"
#import "ASXMLFile.h"
#import "ASXMLRPC.h"
#import "ASWebServices.h"
#import "ISRecommendController.h"
#import "ISTagController.h"
#import "ISLoveBanListController.h"
#import "ISRadioController.h"
#import "ISStatusItem.h"
#import "ISPluginController.h"
#import "Persistence.h"
#import "ISiTunesLibrary.h"

#import "NSWorkspace+ISAdditions.m"

#define IS_GROWL_NOTIFICATION_TRACK_CHANGE @"Track Change"
#define IS_GROWL_NOTIFICATION_IPOD_WILL_SYNC @"iPod Sync Begin"
#define IS_GROWL_NOTIFICATION_IPOD_DID_SYNC @"iPod Sync Finished"
#define IS_GROWL_NOTIFICATION_PROTOCOL @"Last.fm Communications"

static io_connect_t powerPort = (io_connect_t)0;
static void iokpm_callback (void *, io_service_t, natural_t, void*);

#if 0
@interface NSScriptCommand (ISExtensions)

- (id)evaluatedDirectParameters;

@end
#endif

@interface iScrobblerController (iScrobblerControllerPrivate)

- (IBAction)syncIPod:(id)sender;
- (void) restoreITunesLastPlayedTime;
- (void) setITunesLastPlayedTime:(NSDate*)date;

- (void) volumeDidMount:(NSNotification*)notification;
- (void) volumeDidUnmount:(NSNotification*)notification;

- (void)iTunesPlaylistUpdate:(NSTimer*)timer;

- (NSImage*)aeImageConversionHandler:(NSAppleEventDescriptor*)aeDesc;

@end

@interface iScrobblerController (Private)
- (void)retryInfoHandler:(NSTimer*)timer;
- (void)presentError:(NSError*)error withDidEndHandler:(SEL)selector;
@end

// See iTunesPlayerInfoHandler: for why this is needed
@interface ProtocolManager (NoCompilerWarnings)
    - (float)minTimePlayed;
@end

#define SUBMIT_IPOD_MENUITEM_TAG    4
#define RADIO_MENUITEM_TAG 5

@interface SongData (iScrobblerControllerAdditions)
    - (SongData*)initWithiTunesPlayerInfo:(NSDictionary*)dict;
    - (void)updateUsingSong:(SongData*)song;
    - (NSString*)growlDescription;
    - (NSString*)growlTitle;
@end

#define isTopListsActive (NO == [[NSUserDefaults standardUserDefaults] boolForKey:@"Disable Local Lists"] \
&& YES == [[NSUserDefaults standardUserDefaults] boolForKey:@"Display Control Menu"])

@implementation iScrobblerController

- (void)displayProtocolEvent:(NSString *)msg
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"GrowlLastFMCommunications"]) {
        #ifndef __LP64__
        [GrowlApplicationBridge
            notifyWithTitle:msg
            description:@""
            notificationName:IS_GROWL_NOTIFICATION_PROTOCOL
            iconData:nil
            priority:0.0
            isSticky:NO
            clickContext:nil];
        #endif
    }
}

- (void)displayNowPlayingWithMsg:(NSString*)msg
{
#ifndef __LP64__    
    SongData *s;
    NSData *artwork = nil;
    NSString *npInfo = nil, *title = nil;

    if ((s = [self nowPlaying]) && [GrowlApplicationBridge isGrowlRunning]) {
        @try {
        artwork = [[s artwork] TIFFRepresentation];
        } @catch (NSException* e) {}
        
        title = [currentSong growlTitle];
        npInfo = [currentSong growlDescription];
    } else if (msg)
        title = NSLocalizedString(@"Status", "");
    
    if (!title)
        return;
    
    if (npInfo)
        msg = msg ? [npInfo stringByAppendingFormat:@"\n%@", msg] : npInfo;
    
    [GrowlApplicationBridge
        notifyWithTitle:title
        description:msg
        notificationName:IS_GROWL_NOTIFICATION_TRACK_CHANGE
        iconData:artwork
        priority:0.0
        isSticky:NO
        clickContext:nil
        identifier:@"iscrobbler.play"];
#endif
}

- (void)displayNowPlaying
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"GrowlPlays"]) {
         NSString *msg = [[ISRadioController sharedInstance] performSelector:@selector(currentStation)];
        [self displayNowPlayingWithMsg:msg ? [NSString stringWithFormat:@"%@: %@", IS_RADIO_TUNEDTO_STR, msg] : nil];
    }
}

- (void)displayErrorWithTitle:(NSString*)title message:(NSString*)msg
{
#ifndef __LP64__
    [GrowlApplicationBridge
            notifyWithTitle:title
            description:msg
            notificationName:IS_GROWL_NOTIFICATION_ALERTS
            iconData:nil
            priority:0.0
            isSticky:YES
            clickContext:nil];
#endif            
}

- (void)displayWarningWithTitle:(NSString*)title message:(NSString*)msg
{
#ifndef __LP64__
    [GrowlApplicationBridge
            notifyWithTitle:title
            description:msg
            notificationName:IS_GROWL_NOTIFICATION_ALERTS
            iconData:nil
            priority:0.0
            isSticky:NO
            clickContext:nil];
#endif    
}

// PM notifications

- (void)handshakeCompleteHandler:(NSNotification*)note
{
    ProtocolManager *pm = [note object];
    
    BOOL status = NO;
    NSString *msg = nil;
    if ([[pm lastHandshakeResult] isEqualToString:HS_RESULT_OK]) {
        status = YES;
        [self displayProtocolEvent:NSLocalizedString(@"Handshake successful", "")];
    } else {
        [self displayProtocolEvent:NSLocalizedString(@"Handshake failed", "")];
        msg = [[pm lastHandshakeMessage] stringByAppendingFormat:@" (%@: %u)",
            NSLocalizedString(@"Tracks Queued", ""),
            [[QueueManager sharedInstance] count]];
    }
    [statusItem updateStatus:status withOperation:NO withMsg:msg];
}

- (void)badAuthHandler:(NSNotification*)note
{
    [self performSelector:@selector(showBadCredentialsDialog) withObject:nil afterDelay:0.0];
}

- (void)handshakeStartHandler:(NSNotification*)note
{
    [statusItem updateStatus:YES withOperation:YES withMsg:nil];
}

- (void)submitCompleteHandler:(NSNotification*)note
{
    BOOL status = NO;
    ProtocolManager *pm = [note object];
    NSString *msg = nil;
    if ([[pm lastSubmissionResult] isEqualToString:HS_RESULT_OK]) {
        [self displayProtocolEvent:NSLocalizedString(@"Submission successful", "")];
        status = YES;
    } else {
        [self displayProtocolEvent:NSLocalizedString(@"Submission failed", "")];
        msg = [[pm lastSubmissionMessage] stringByAppendingFormat:@" (%@: %u)",
            NSLocalizedString(@"Tracks Queued", ""),
            [[QueueManager sharedInstance] count]];;
    }
    [statusItem updateStatus:status withOperation:NO withMsg:msg];
}

- (void)submitStartHandler:(NSNotification*)note
{
    [statusItem updateStatus:YES withOperation:YES withMsg:nil];
}

- (void)networkStatusHandler:(id)obj // NSNotification OR NSTimer
{
    static NSTimer *netStatusTimer = nil;
    static BOOL createTimer = YES;
    
    NSNumber *available = [[obj userInfo] objectForKey:PM_NOTIFICATION_NETWORK_STATUS_KEY];
    
    if (netStatusTimer) {
        if (netStatusTimer != obj)
            [netStatusTimer invalidate];
        netStatusTimer = nil;
        createTimer = NO; // Only try the timer once
    }
    
    if (statusItem) {
        static BOOL isOrange = NO;
        if (available && ![available boolValue]) {
            NSString *msg = [[obj userInfo] objectForKey:PM_NOTIFICATION_NETWORK_MSG_KEY];
            if (!msg || 0 == [msg length])
                msg = NSLocalizedString(@"Network is not available.", "");
            [statusItem updateStatusWithColor:[NSColor orangeColor] withMsg:msg];
            isOrange = YES;
        } else if (isOrange) {
            [statusItem updateStatusWithColor:[statusItem defaultStatusColor] withMsg:nil];
            isOrange = NO;
        }
    } else if (createTimer) {
        // At launch, the status item will be nil when the Protocol Mgr is initialized,
        // so we create a timer to deal with this.
        // 2 seconds should be plenty of time for launch to finish
        netStatusTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                target:self
                                selector:@selector(networkStatusHandler:)
                                userInfo:[obj userInfo]
                                repeats:NO];
    }
}

// End PM Notifications

- (void)profileDidReset:(NSNotification*)note
{
    static int doreset = 0;
    if (!doreset) {
        doreset = 1;
        // make sure we run after every other observer
        [self performSelector:@selector(profileDidReset:) withObject:note afterDelay:0.0];
        return;
    }
    
    doreset = 0;
    ScrobLog(SCROB_LOG_INFO, @"*** Reset ***");
}

- (BOOL)updateInfoForSong:(SongData*)song
{
    // Run the script to get the info not included in the dict
    NSDictionary *errInfo = nil;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&errInfo] ;
    if (result) {
        if ([result numberOfItems] > 1) {
            TrackType_t trackType = trackTypeUnknown;
            u_int64_t trackiTunesDatabaseID = 0;
            NSNumber *trackPosition, *trackRating, *trackPlaylistID, *trackPodcast, *trackPlayCount;
            NSDate *trackLastPlayed = nil;
            NSString *trackSourceName = nil, *trackComment = nil, *trackUUID = nil;
            NSArray *values;
            @try {
                values = [result objCObjectValue];
                trackType = (TrackType_t)[[values objectAtIndex:0] intValue];
                trackiTunesDatabaseID = [[values objectAtIndex:1] intValue];
                trackPosition = [values objectAtIndex:2];
                trackRating = [values objectAtIndex:3];
                trackLastPlayed = [values objectAtIndex:4];
                trackPlaylistID = [values objectAtIndex:5];
                trackSourceName = [values objectAtIndex:6];
                trackPodcast = [values objectAtIndex:7];
                trackComment = [values objectAtIndex:8];
                trackPlayCount = [values objectAtIndex:9];
                trackUUID = [values objectAtIndex:10];
            } @catch (NSException *exception) {
                ScrobLog(SCROB_LOG_ERR, @"GetTrackInfo script invalid result: parsing exception %@\n.", exception);
                return (NO);
            }
            
            if (IsTrackTypeValid(trackType) && trackiTunesDatabaseID >= 0 && [trackPosition intValue] >= 0) {
                [song setType:trackType];
                [song setiTunesDatabaseID:trackiTunesDatabaseID];
                [song setPosition:trackPosition];
                
                @try {
                    [song setRating:trackRating];
                } @catch (NSException* exception) {
                }
                [song setPlaylistID:trackPlaylistID];
                if (trackSourceName && [trackSourceName length] > 0)
                    [song setSourceName:trackSourceName];
                #ifdef obsolete
                // We now use this to calculate elapsed time, so don't update it with the iTunes value
                if (trackLastPlayed)
                    [song setLastPlayed:trackLastPlayed];
                #endif
                if (trackPodcast && [trackPodcast intValue] > 0)
                    [song setIsPodcast:YES];
                if (trackComment)
                    [song setComment:trackComment];
                [song setPlayCount:trackPlayCount];
                [song setPlayerUUID:trackUUID];
                return (YES);
            } else {
                ScrobLog(SCROB_LOG_ERR, @"GetTrackInfo script invalid result: bad type, db id, or position (%d:%d:%d)\n.",
                    trackType, trackiTunesDatabaseID, trackPosition);
            }
        } else {
            ScrobLog(SCROB_LOG_ERR, @"GetTrackInfo script invalid result: bad item count: %d\n.", [result numberOfItems]);
        }
    } else {
        ScrobLog(SCROB_LOG_ERR, @"GetTrackInfo script execution error: %@\n.", errInfo);
    }
    
    return (NO);
}

#define KillQueueTimer() do { \
[currentSongQueueTimer invalidate]; \
[currentSongQueueTimer release]; \
currentSongQueueTimer = nil; \
} while (0) 

- (BOOL)queueSongsForLaterSubmission
{
    return ([[NSUserDefaults standardUserDefaults] boolForKey:@"ForcePlayCache"] ||
        ([[NSUserDefaults standardUserDefaults] boolForKey:@"QueueSubmissionsIfiPodIsMounted"] && iPodMountCount > 0));
}

- (void)queueCurrentSong:(NSTimer*)timer
{
    SongData *song = [[SongData alloc] init];
    
    KillQueueTimer();
    timer = nil;
    
    if (!currentSong || (currentSong && [currentSong hasQueued])) {
        goto queue_exit;
    }
    
    if ([currentSong isPlayeriTunes] && ![self updateInfoForSong:song]) {
        ScrobLog(SCROB_LOG_TRACE, @"GetTrackInfo execution error. Trying again in %0.1f seconds.",
            2.5);
        currentSongQueueTimer = [[NSTimer scheduledTimerWithTimeInterval:2.5l
                                    target:self
                                    selector:@selector(queueCurrentSong:)
                                    userInfo:nil
                                    repeats:NO] retain];
        goto queue_exit;
    } else if (![currentSong isPlayeriTunes]) {
        [song setPosition:[currentSong elapsedTime]];
    }
    
    if (![currentSong isPlayeriTunes] || [song iTunesDatabaseID] == [currentSong iTunesDatabaseID]) {
        [currentSong updateUsingSong:song];
        
        // Try submission
        QueueResult_t qr = [[QueueManager sharedInstance] queueSong:currentSong];
        if (kqFailed == qr) {
            // Fire ourself again in half of the remaining track play time.
            // The queue can fail when playing from a network stream (or CD),
            // and iTunes has to re-buffer. This means the elapsed track play time
            // would be less than elapsed real-world time and the track may not be 1/2
            // done.
            double fireInterval = [currentSong resubmitInterval];
            if (fireInterval >= 1.0) {
                ScrobLog(SCROB_LOG_VERBOSE,
                    @"Track '%@' failed submission rules. "
                    @"Trying again in %0.0lf seconds.\n", [currentSong brief], fireInterval);
                currentSongQueueTimer = [[NSTimer scheduledTimerWithTimeInterval:fireInterval
                                target:self
                                selector:@selector(queueCurrentSong:)
                                userInfo:nil
                                repeats:NO] retain];
            } else {
                ScrobLog(SCROB_LOG_WARN, @"Track '%@' failed submission rules. "
                    @"There is not enough play time left to retry submission.\n",
                    [currentSong brief]);
            }
        }
    } else {
        ScrobLog(SCROB_LOG_ERR, @"Lost track! current: (%@, %d), itunes: (%@, %d)\n.",
            currentSong, [currentSong iTunesDatabaseID], song, [song iTunesDatabaseID]);
    }
    
queue_exit:
    [song release];
}

- (void)queueSong:(SongData*)song
{
    [song setPosition:[song elapsedTime]];
    QueueResult_t qr = [[QueueManager sharedInstance] queueSong:song];
    if (kqFailed == qr) {
        ScrobLog(SCROB_LOG_WARN, @"Track '%@' failed submission rules.", [song brief]);
    }
}

#define ReleaseCurrentSong() do { \
if (currentSong) { \
    if ([currentSong isPaused]) \
        [currentSong didResumeFromPause]; \
    if ([currentSong submitIntervalFromNow] >= PM_SUBMIT_AT_TRACK_END && ![currentSong hasQueued] && !submissionsDisabled) \
        [self queueSong:currentSong]; \
    [currentSong setLastPlayed:[NSDate date]]; \
    [currentSong release]; \
    currentSong = nil; \
} \
} while(0)

- (void)iTunesPlayerInfoHandler:(NSNotification*)note
{
    static int retryCount = 0;
    // Invalidate any possible outstanding error handler
    [getTrackInfoTimer invalidate];
    getTrackInfoTimer = nil;
    
    double fireInterval;
    NSDictionary *info = [note userInfo];
    static BOOL isiTunesPlaying = NO;
    BOOL wasiTunesPlaying = isiTunesPlaying;
    isiTunesPlaying = [@"Playing" isEqualToString:[info objectForKey:@"Player State"]];
    BOOL isPlayeriTunes = [@"com.apple.iTunes.playerInfo" isEqualToString:[note name]];
    BOOL isRepeat = NO;
    
    ScrobLog(SCROB_LOG_TRACE, @"%@ notification received: %@\n", [note name], [info objectForKey:@"Player State"]);
    
    // Even if subs are disabled, we still have to update the iTunes play time, as the user
    // could enable subs, plug-in the ipod, and then we'd pick up everything that was supposed to
    // have been ignored in iTunes (because the play time had not been updated).
    SongData *song = nil;
    if (submissionsDisabled) {
        ReleaseCurrentSong();
        goto player_info_exit;
    }
    
    @try {
        if (![@"Stopped" isEqualToString:[info objectForKey:@"Player State"]]) {
            if (!(song = [[SongData alloc] initWithiTunesPlayerInfo:info]))
                ScrobLog(SCROB_LOG_ERR, @"Error creating track with info: %@\n", info);
        } else {
            ReleaseCurrentSong();
        }
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Exception creating track (%@): %@\n", info, exception);
    }
    if (!song) {
        [self updateMenu];
        goto player_info_exit;
    }
    
    BOOL didInfoUpdate;
    if (isPlayeriTunes)
        didInfoUpdate = [self updateInfoForSong:song];
    else {
        // player is PandoraBoy, etc
        [song setIsPlayeriTunes:NO];
        didInfoUpdate = YES;
        [song setType:trackTypeFile];
    }
    
    if (didInfoUpdate) {
        @try {
        if ([song ignore]) {
            ScrobLog(SCROB_LOG_VERBOSE, @"Song '%@' filtered.\n", [song brief]);
            [song release];
            song = nil;
            ReleaseCurrentSong();
            goto player_info_exit;
        }
        } @catch (NSException *exception) {
            ScrobLog(SCROB_LOG_ERR, @"Exception filtering track (%@): %@\n", song, exception);
        }
    } else if (isPlayeriTunes) {
        if (retryCount < 3) {
            retryCount++;
            [getTrackInfoTimer invalidate];
            getTrackInfoTimer = [NSTimer scheduledTimerWithTimeInterval:2.5
                                    target:self
                                    selector:@selector(retryInfoHandler:)
                                    userInfo:note
                                    repeats:NO];
            ScrobLog(SCROB_LOG_TRACE, @"GetTrackInfo execution error (%d). Trying again in %0.1f seconds.",
                retryCount, 2.5);
        } else {
            ScrobLog(SCROB_LOG_TRACE, @"GetTrackInfo execution error after %d retries. Giving up.\n", retryCount);
            retryCount = 0;
            isiTunesPlaying = NO;
            ReleaseCurrentSong();
        }
        goto player_info_exit;
    }
    retryCount = 0;
    
    ScrobLog(SCROB_LOG_TRACE, @"iTunes Data: (T,Al,Ar,P,D) = (%@,%@,%@,%@,%@)",
        [song title], [song album], [song artist], [song position], [song duration]);
    
    if (currentSong && [currentSong isEqualToSong:song]) {
        // The pause data needs to be update before a repeat check
        if (isiTunesPlaying && !wasiTunesPlaying) { // and a resume
            currentSongPaused = NO;
            if (![currentSong hasQueued])
                [currentSong didResumeFromPause];
        }
        
        // Try to determine if the song is being played twice (or more in a row)
        fireInterval = 0.0;
        float pos = [song isPlayeriTunes] ? [[song position] floatValue] : [[song elapsedTime] floatValue];
        if (pos + [SongData songTimeFudge] <  [[currentSong elapsedTime] floatValue] &&
             (pos <= [SongData songTimeFudge]) &&
             // The following condition does not work with iTunes 4.7, since we are not
             // constantly updating the song's position by polling iTunes. With 4.7 we update
             // when the song first plays, when it's ready for submission or if the user
             // changes some song metadata -- that's it.
        #if 0
              // Could be a new play, or they could have seek'd back in time. Make sure it's not the latter.
             (([[firstSongInList duration] floatValue] - [[firstSongInList position] floatValue])
        #endif
             ([currentSong hasQueued] || ([currentSong submitIntervalFromNow] >= PM_SUBMIT_AT_TRACK_END) && [currentSong canSubmit])) {
            ScrobLog(SCROB_LOG_TRACE, @"Repeat play detected: '%@'", [currentSong brief]);
            ReleaseCurrentSong();
            isRepeat = YES;
        } else {
            [currentSong updateUsingSong:song];
            if (pos < 1.0 && ![currentSong hasQueued]) {
                [currentSong setStartTime:[NSDate date]];
                [currentSong setPostDate:[NSCalendarDate date]];
            }
            
            if (!isiTunesPlaying) { // Handle a pause
                [currentSong didPause];
                currentSongPaused = YES;
                if (![currentSong hasQueued])
                    KillQueueTimer();
                ScrobLog(SCROB_LOG_TRACE, @"'%@' paused", [currentSong brief]);
            } else  if (isiTunesPlaying && !wasiTunesPlaying) { // and a resume
                if (![currentSong hasQueued]) {
                    ISASSERT(!currentSongQueueTimer, "Timer is active!");
                    fireInterval = [currentSong resubmitInterval];
                    if (fireInterval > 0) {
                        currentSongQueueTimer = [[NSTimer scheduledTimerWithTimeInterval:fireInterval
                                    target:self
                                    selector:@selector(queueCurrentSong:)
                                    userInfo:nil
                                    repeats:NO] retain];
                    }
                    ScrobLog(SCROB_LOG_TRACE, @"'%@' resumed (elapsed: %.1fs) -- sub in %.1lfs", [currentSong brief],
                        [[currentSong elapsedTime] floatValue], fireInterval);
                }
                
                if ([[NSUserDefaults standardUserDefaults] boolForKey:@"GrowlOnResume"]) {
                    goto notify_growl;
                }
            }
            
            goto player_info_exit;
        }
    }
    
    // Kill the current timer
    KillQueueTimer();
    
    /* Workaround for iTunes bug (as of 4.7):
       If the script is run at the exact moment a track switch on an Audio CD occurs,
       the new track will have the previous track's duration set as its current position.
       Since the notification happens at that moment we are always hit by the bug.
       Note: This seems to only affect Audio CD's, encoded files aren't affected. (Shared tracks?)
       Note 2: It would be possible for our conditions to occur while not on a track switch if for
       instance the user changed some song meta-data. However this should be a very rare occurence.
       */
    if (currentSong && ![currentSong isEqualToSong:song] &&
            ([[currentSong duration] isEqualToNumber:[song position]] ||
            [[song position] isGreaterThan:[song duration]])) {
        [song setPosition:[NSNumber numberWithUnsignedInt:0]];
        // Reset the start time too, since it will be off
        [song setStartTime:[NSDate date]];
    }
    
    #if 0
    fireInterval = currentSong ? [currentSong submitIntervalFromNow] : 0.0f;
    if (fireInterval >= PM_SUBMIT_AT_TRACK_END) {
        if (![currentSong isEqualToSong:song] && [currentSong canSubmit]) {
            [self queueSong:currentSong];
        }
    }
    #endif
    
    if (isiTunesPlaying) {
        currentSongPaused = NO;
        // Fire the main timer at the appropos time to get it queued (proto 1.1 only)
        fireInterval = [song submitIntervalFromNow];
        if (fireInterval >= PM_SUBMIT_AT_TRACK_END) {
            ;
        } else if (fireInterval > 0.0) { // Seems there's a problem with some CD's not giving us correct info.
            ScrobLog(SCROB_LOG_TRACE, @"Firing sub timer in %0.2lf seconds for track '%@'.\n",
                fireInterval, [song brief]);
            currentSongQueueTimer = [[NSTimer scheduledTimerWithTimeInterval:fireInterval
                            target:self
                            selector:@selector(queueCurrentSong:)
                            userInfo:nil
                            repeats:NO] retain];
        } else {
            ScrobLog(SCROB_LOG_WARN,
                @"Invalid submit interval '%0.2lf' for track '%@'. Track will not be submitted. Duration: %@, Position: %@.\n",
                fireInterval, [song brief], [song duration], [song position]);
        }
        
        // Update Recent Songs list
        int i, found = 0, count = [songList count];
        for(i = 0; i < count; ++i) {
            if ([[songList objectAtIndex:i] isEqualToSong:song]) {
                found = i;
                break;
            }
        }

        // If the track wasn't found anywhere in the list, we add a new item
        if (found) {
            // If the trackname was found elsewhere in the list, we remove the old item
            [songList removeObjectAtIndex:found];
        } else
            ScrobLog(SCROB_LOG_VERBOSE, @"Added '%@'\n", [song brief]);
        [songList pushSong:song];
        
        if ((count = [songList count] - [prefs integerForKey:@"Number of Songs to Save"]) > 0) {
            NSRange r = NSMakeRange([prefs integerForKey:@"Number of Songs to Save"], count);
            ISASSERT((r.location + r.length) == [songList count], "invalid range!");
            [songList removeObjectsInRange:r];
        }
        
        ReleaseCurrentSong();
        currentSong = song;
        song = nil; // Make sure it's not released
        
        [self updateMenu];
        
notify_growl:
        [self displayNowPlaying];
    }
    
player_info_exit:
    if (song)
        [song release];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:isRepeat], @"repeat",
        [NSNumber numberWithBool:isiTunesPlaying], @"isPlaying",
        nil];
    if (isiTunesPlaying && currentSongQueueTimer)
        [userInfo setObject:[currentSongQueueTimer fireDate] forKey:@"sub date"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"Now Playing"
        object:(isiTunesPlaying ? currentSong : nil) userInfo:userInfo];
    
    if (isiTunesPlaying || wasiTunesPlaying != isiTunesPlaying)
        [self setITunesLastPlayedTime:[NSDate date]];
    ScrobLog(SCROB_LOG_TRACE, @"iTunesLastPlayedTime == %@\n", iTunesLastPlayedTime);
}

- (void)retryInfoHandler:(NSTimer*)timer
{
    getTrackInfoTimer = nil;
    [self iTunesPlayerInfoHandler:[timer userInfo]];
}

- (void)enableStatusItemMenu:(BOOL)enable
{
    ISRadioController *rc = [ISRadioController sharedInstance];
    
    if (enable) {
        if (!statusItem) {
            statusItem = [[ISStatusItem alloc] initWithMenu:theMenu];
            [rc setRootMenu:[theMenu itemWithTag:RADIO_MENUITEM_TAG]];
        }
    } else if (statusItem) {
        [rc setRootMenu:nil];
        [statusItem release];
        statusItem = nil;
    }
}

-(id)init
{
    // Read in a defaults.plist preferences file
    NSString * file = [[NSBundle mainBundle] pathForResource:@"defaults" ofType:@"plist"];
    NSDictionary * defaultPrefs = [NSDictionary dictionaryWithContentsOfFile:file];
	
    prefs = [[NSUserDefaults standardUserDefaults] retain];
    [prefs registerDefaults:defaultPrefs];
    
    // This sucks. We added new columns to the Top Artists and Top Tracks lists in 1.0.1. But,
    // if the saved Column/Sort orderings don't match then the new column won't show.
    // So here, we delete the saved settings from version 1.0.0.
    if ([@"1.0.0" isEqualToString:[prefs objectForKey:@"version"]]) {
        [prefs removeObjectForKey:@"NSTableView Columns Top Artists"];
        [prefs removeObjectForKey:@"NSTableView Sort Ordering Top Artists"];
        [prefs removeObjectForKey:@"NSTableView Columns Top Tracks"];
        [prefs removeObjectForKey:@"NSTableView Sort Ordering Top Tracks"];
    }
    
    // One user has reported the version # showing up in his personal prefs.
    // I don't know how this is happening, but I've never seen it myself. So here,
    // we just force the version # from the defaults into the personal prefs.
    // This came in very handy above -- what foresight!
    [prefs setObject:[defaultPrefs objectForKey:@"version"] forKey:@"version"];
    
    [SongData setSongTimeFudge:5.0];
	
    // Request the password and lease it, this will force it to ask
    // permission when loading, so it doesn't annoy you halfway through
    // a song.
    (void)[[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler"
        account:[prefs stringForKey:@"username"]];
	
	// Create an instance of the preferenceController
    if(!preferenceController)
        preferenceController=[[PreferenceController alloc] init];
	
    // Register our image conversion handler for AE descriptors (KFASHandlerAdditions)
    [NSAppleEventDescriptor registerConversionHandler:self
        selector:@selector(aeImageConversionHandler:)
        forDescriptorTypes:typePict, typeTIFF, typeJPEG, typeGIF, nil];
    
	// Create the GetInfo script
    file = [[[NSBundle mainBundle] resourcePath]
                stringByAppendingPathComponent:@"Scripts/iTunesGetCurrentTrackInfo.scpt"];
    NSURL *url = [NSURL fileURLWithPath:file];
    script = [[NSAppleScript alloc] initWithContentsOfURL:url error:nil];
    if (!script) {
        ScrobLog(SCROB_LOG_CRIT, @"Could not load iTunesGetCurrentTrackInfo.scpt!\n");
        [self showApplicationIsDamagedDialog];
        [NSApp terminate:nil];
    }
    
    [self restoreITunesLastPlayedTime];
    
    if ((self = [super init])) {
        [NSApp setDelegate:self];
        
        (void)[ISiTunesLibrary sharedInstance]; // init before any threads start
        
        nc=[NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(handlePrefsChanged:)
            name:SCROB_PREFS_CHANGED
            object:nil];
        
        // iPod notes
        [nc addObserver:self
                selector:@selector(iPodSyncBegin:)
                name:IPOD_SYNC_BEGIN
                object:nil];
        [nc addObserver:self
                selector:@selector(iPodSyncEnd:)
                name:IPOD_SYNC_END
                object:nil];
        
        // Register for mounts and unmounts (iPod support)
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
            selector:@selector(volumeDidMount:) name:NSWorkspaceDidMountNotification object:nil];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
            selector:@selector(volumeDidUnmount:) name:NSWorkspaceDidUnmountNotification object:nil];
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
            selector:@selector(applicationWillTerminate:) name:NSWorkspaceWillPowerOffNotification object:nil];
        // We can't prevent power off/logout via the GUI notification since we are a background app
        // We can only prevent idle sleep via idle sleep - don't know what to do about log off and user restart/shutdown
        // XXX: portRef, powerPort and source are all leaked objects on purpoose
        IONotificationPortRef portRef;
        io_object_t notifier;
        powerPort = IORegisterForSystemPower (NULL, &portRef, iokpm_callback, &notifier);
        if (powerPort) {
            CFRunLoopSourceRef source = IONotificationPortGetRunLoopSource(portRef);
            CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], source, kCFRunLoopDefaultMode);
        }

#ifndef __LP64__
        // Register with Growl
        [GrowlApplicationBridge setGrowlDelegate:self];
#else
; // Growl not 64bit yet
#endif
        // Register for iTunes track change notifications
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(iTunesPlayerInfoHandler:) name:@"com.apple.iTunes.playerInfo"
            object:nil];
        
        // Internal last.fm stream now playing info
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(iTunesPlayerInfoHandler:) name:@"org.bergstrand.iscrobbler.lasfm.playerInfo"
            object:nil];
        
        #ifdef notyet
        // Doesn't work yet, as "Total Time" is not included in the note
        // Register for PandoraBoy track change notifications
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(iTunesPlayerInfoHandler:) name:@"net.frozensilicon.pandoraBoy.playerInfo"
            object:nil];
        #endif
        
        // Create protocol mgr -- register the up/down notification before, because
        // PM init can send it
        [nc addObserver:self
                selector:@selector(networkStatusHandler:)
                name:PM_NOTIFICATION_NETWORK_STATUS
                object:nil];
        
        (void)[ProtocolManager sharedInstance];
        
        // Register for PM notifications
        [nc addObserver:self
                selector:@selector(handshakeCompleteHandler:)
                name:PM_NOTIFICATION_HANDSHAKE_COMPLETE
                object:nil];
        [nc addObserver:self
                selector:@selector(badAuthHandler:)
                name:PM_NOTIFICATION_BADAUTH
                object:nil];
        [nc addObserver:self
                selector:@selector(handshakeStartHandler:)
                name:PM_NOTIFICATION_HANDSHAKE_START
                object:nil];
        [nc addObserver:self
                selector:@selector(submitCompleteHandler:)
                name:PM_NOTIFICATION_SUBMIT_COMPLETE
                object:nil];
        [nc addObserver:self
                selector:@selector(submitStartHandler:)
                name:PM_NOTIFICATION_SUBMIT_START
                object:nil];
        
        [nc addObserver:self
            selector:@selector(profileDidReset:) name:RESET_PROFILE object:nil];
        
        // Create queue mgr
        (void)[QueueManager sharedInstance];
        if ([[QueueManager sharedInstance] count])
            [[QueueManager sharedInstance] submit];
        
        // Create top lists controller so it will pick up subs
        // We do this after creating the QM so that queued subs are not counted.
        if (isTopListsActive)
            (void)[TopListsController sharedInstance];
    }
    
    // Install ourself in the Login Items
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSString *pathToSelf = [[NSBundle mainBundle] bundlePath];
    if (![ws isLoginItem:pathToSelf]) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"Added to Login"]) {
            if ([ws addLoginItem:pathToSelf hidden:NO])
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Added to Login"];
        }
    }
    
    return self;
}

- (void)awakeFromNib
{
    // transition from old prefs domain
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id oldPrefs = [ud persistentDomainForName:@"org.flexistentialist.iscrobbler"];
    if (oldPrefs && NO == [ud boolForKey:@"PrefsMigrated"]) {
        [ud setPersistentDomain:oldPrefs forName:[[NSBundle mainBundle] bundleIdentifier]];
        [ud removePersistentDomainForName:@"org.flexistentialist.iscrobbler"];
        
        NSArray *keys = [oldPrefs allKeys];
        NSEnumerator *en = [keys objectEnumerator];
        id key;
        while ((key = [en nextObject])) {
            [ud setObject:[oldPrefs objectForKey:key] forKey:key];
        }
        [ud setBool:YES forKey:@"PrefsMigrated"];
        [ud synchronize];
    }
    
    songList=[[NSMutableArray alloc ]init];
    
// We don't need to do this right now, as the only thing that uses playlists is the prefs.
#if 0
    // Timer to update our internal copy of iTunes playlists
    [[NSTimer scheduledTimerWithTimeInterval:300.0
        target:self
        selector:@selector(iTunesPlaylistUpdate:)
        userInfo:nil
        repeats:YES] fire];
#endif

    BOOL enableMenu = [[NSUserDefaults standardUserDefaults] boolForKey:@"Display Control Menu"];
    if (!enableMenu && (GetCurrentKeyModifiers() & shiftKey))
        enableMenu = YES;
    [self enableStatusItemMenu:enableMenu];
    
    // Setup the action menu template
    songActionMenu = [[NSMenu alloc] init];
    [songActionMenu setAutoenablesItems:NO];
    NSMenuItem *item;
    NSString *title;
    title = [NSString stringWithFormat:@"%C ", 0x2665];
    item = [[NSMenuItem alloc] initWithTitle:[title stringByAppendingString:NSLocalizedString(@"Love", "")]
        action:@selector(loveTrack:) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:MACTION_LOVE_TAG];
    [item setEnabled:YES];
    [songActionMenu addItem:item];
    [item release];
    
    title = [NSString stringWithFormat:@"%C ", 0x2298];
    item = [[NSMenuItem alloc] initWithTitle:[title stringByAppendingString:NSLocalizedString(@"Ban", "")]
        action:@selector(banTrack:) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:MACTION_BAN_TAG];
    [item setEnabled:YES];
    [songActionMenu addItem:item];
    [item release];
    
    title = [NSString stringWithFormat:@"%C ", 0x270E];
    item = [[NSMenuItem alloc] initWithTitle:[title stringByAppendingString:NSLocalizedString(@"Tag", "")]
        action:@selector(tagTrack:) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:MACTION_TAG_TAG];
    [item setEnabled:YES];
    [songActionMenu addItem:item];
    [item release];
    
    title = [NSString stringWithFormat:@"%C ", 0x2709];
    item = [[NSMenuItem alloc] initWithTitle:[title stringByAppendingString:NSLocalizedString(@"Recommend", "")]
        action:@selector(recommendTrack:) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:MACTION_RECOMEND_TAG];
    [item setEnabled:YES];
    [songActionMenu addItem:item];
    [item release];
    
    [songActionMenu addItem:[NSMenuItem separatorItem]];
    
    item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Open Last.fm Artist Page", "")
        action:@selector(openTrackURL:) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:MACTION_OPEN_ARTIST_PAGE];
    [item setEnabled:YES];
    [songActionMenu addItem:item];
    [item release];
    
    item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Open Last.fm Track Page", "")
        action:@selector(openTrackURL:) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:MACTION_OPEN_TRACK_PAGE];
    [item setEnabled:YES];
    [songActionMenu addItem:item];
    [item release];
    
    
    #ifdef notyet
    item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Play", "")
        action:@selector(playSong:) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:MACTION_PLAY_TAG];
    [item setEnabled:YES];
    [songActionMenu addItem:item];
    [item release];
    #endif
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(id /*NSApplication**/)sender
{
    if (isTopListsActive && [[PersistentProfile sharedInstance] importInProgress]) {
        #ifdef notyet
        if ([NSWorkspace sharedWorkspace] == sender) {
            // documented as not implemeted, and it's not (as of 10.4.10
            int given = [[NSWorkspace sharedWorkspace] extendPowerOffBy:INT_MAX];
            ScrobDebug(@"given %d ms of delayed log out", given);
        }
        #endif
        
        // display warning - don't use Growl as it may not be running if the user attemped a restart/shutdown
        NSError *error = [NSError errorWithDomain:@"iscrobbler" code:0 userInfo:
        [NSDictionary dictionaryWithObjectsAndKeys:
            NSLocalizedString(@"Quit Cancelled", nil), NSLocalizedFailureReasonErrorKey,
            NSLocalizedString(@"iScrobbler is busy importing data into the local charts. The import cannot be interrupted. Please wait for the import to finish.", nil),
                NSLocalizedDescriptionKey,
            NSLocalizedString(@"OK", nil), @"defaultButton",
            nil]];
        
        [self presentError:error withDidEndHandler:nil];
        return (NSTerminateCancel);
    }
    
    return (NSTerminateNow);
}

- (void)applicationWillTerminate:(NSNotification *)note
{
    if ([[note name] isEqualToString:NSWorkspaceWillPowerOffNotification]) {
        (void)[self applicationShouldTerminate:[NSWorkspace sharedWorkspace]];
    }
    
    [[QueueManager sharedInstance] syncQueue:nil];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)checkForOtherScrobblers:(id)arg
{
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"CheckForOtherScrobblers"]) {
        NSEnumerator *en = [[[NSWorkspace sharedWorkspace] launchedApplications] objectEnumerator];
        NSDictionary *d;
        while ((d = [en nextObject])) {
            if ([[d objectForKey:@"NSApplicationBundleIdentifier"] hasPrefix:@"fm.last"]) {
                [self displayErrorWithTitle:NSLocalizedString(@"Another Last.FM Client is Active", "")
                    message:NSLocalizedString(@"Multiple active Last.FM clients may cause duplicate submissions or other problems.", "")];
                break;
            }
        }
    }
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    // Register to handle URLs
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(getUrl:withReplyEvent:)
        forEventClass:kInternetEventClass andEventID:kAEGetURL];
    
    (void)[ISPluginController sharedInstance]; // load plugins
    
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:OPEN_STATS_WINDOW_AT_LAUNCH]) {
        [self openStatistics:nil];
    }
    if ([ud boolForKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH] && isTopListsActive) {
        [self openTopLists:nil];
    }
    
    if (0 == [[prefs stringForKey:@"username"] length] || 0 == 
        [[[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler"
            account:[prefs stringForKey:@"username"]] length]) {
        // No clue why, but calling this method directly here causes the status item
        // to permantly stop functioning. Maybe something to do with the run-loop
        // not having run yet?
        [self performSelector:@selector(openPrefs:) withObject:nil afterDelay:0.1];
    }
    
    if (!iPodMountPath) {
        // Simulate mount events for current mounts so that any mounted iPod is found
        NSEnumerator *en = [[[NSWorkspace sharedWorkspace] mountedLocalVolumePaths] objectEnumerator];
        NSString *path;
        while ((path = [en nextObject])) {
            NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:path, @"NSDevicePath", nil];
            NSNotification *note = [NSNotification notificationWithName:NSWorkspaceDidMountNotification
                object:[NSWorkspace sharedWorkspace] userInfo:dict];
            [self volumeDidMount:note];
        }
    }
    
    // warn user if Growl is not installed
    if (![GrowlApplicationBridge isGrowlInstalled] || ![GrowlApplicationBridge isGrowlRunning]) {
        NSError *error = [NSError errorWithDomain:@"iscrobbler" code:0 userInfo:
        [NSDictionary dictionaryWithObjectsAndKeys:
            NSLocalizedString(@"Growl Is Not Available", nil), NSLocalizedFailureReasonErrorKey,
            NSLocalizedString(@"iScrobbler uses Growl for 99%% of its notification dialogs. To get the most out of iScrobbler please install or activate Growl.", nil),
                NSLocalizedDescriptionKey,
            NSLocalizedString(@"OK", nil), @"defaultButton",
            NSLocalizedString(@"Open Growl Home Page", nil), @"otherButton",
            nil]];
        
        [self presentError:error withDidEndHandler:@selector(noGrowlDidEnd:returnCode:contextInfo:)];
    }
    
    // warn user if last.fm app is running
    [self checkForOtherScrobblers:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
            selector:@selector(checkForOtherScrobblers:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    
    if (NO == [ud boolForKey:@"BBNetUpdateDontAutoCheckVersion"]) {
        // Check the version now and then every 72 hours
        [[NSTimer scheduledTimerWithTimeInterval:259200.0
            target:self selector:@selector(checkForUpdate:) userInfo:nil repeats:YES] fire];
    }
}


- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	NSString *url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    [[ISRadioController sharedInstance] tuneStationWithName:nil url:url];
}

-(IBAction)checkForUpdate:(id)sender
{
    if ([sender isKindOfClass:[NSTimer class]]) {
        //automatic check - make sure we have an inet connection
        if (NO == [[ProtocolManager sharedInstance] isNetworkAvailable]) {
            ScrobLog(SCROB_LOG_TRACE, @"Network not available, skipping version check.");
            return;
        }
        sender = nil;
    }
    [BBNetUpdateVersionCheckController checkForNewVersion:nil interact:(sender ? YES : NO)];
}

- (void)noGrowlDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    if (returnCode == NSAlertAlternateReturn) {
        NSURL *url = [NSURL URLWithString:@"http://growl.info/"];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
    
    [(id)contextInfo performSelector:@selector(close) withObject:nil afterDelay:0.0];
}

- (void)setSubmissionsEnabled:(BOOL)enabled
{
    submissionsDisabled = !enabled;
    [statusItem setSubmissionsEnabled:!submissionsDisabled];
    if (submissionsDisabled && [[NSUserDefaults standardUserDefaults] boolForKey:@"WarnIfSubmissionsDisabled"])
        [self displayErrorWithTitle:NSLocalizedString(@"Submissions Disabled", "") message:@""];
}

-(IBAction)enableDisableSubmissions:(id)sender
{
    if (!submissionsDisabled) {
        [self setSubmissionsEnabled:NO];
        [sender setTitle:NSLocalizedString(@"Resume Submissions", "")];
    } else {
        [self setSubmissionsEnabled:YES];
        [sender setTitle:NSLocalizedString(@"Pause Submissions", "")];
    }
}

- (void)updateMenu
{
    NSMenuItem *item;
    NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
    SongData *song;
    int addedSongs = 0;
    // ScrobTrace(@"updating menu");
	
    // remove songs from menu
    while((item = [enumerator nextObject])) {
        if ([[item representedObject] isKindOfClass:[SongData class]]) {
            [item setRepresentedObject:nil];
            [theMenu removeItem:item];
        }
    }
    
    // Remove separator
    if ([theMenu numberOfItems] && [[theMenu itemAtIndex:0] isSeparatorItem])
        [theMenu removeItemAtIndex:0];
    
    // add songs from songList array to menu
    enumerator=[songList reverseObjectEnumerator];
    int songsToDisplay = [prefs integerForKey:@"Number of Songs to Save"];
    while ((song = [enumerator nextObject]) && addedSongs < songsToDisplay) {
        item = [[[NSMenuItem alloc] initWithTitle:[song title]
                                    action:![song isLastFmRadio] ? @selector(playSong:) : nil
                                    keyEquivalent:@""] autorelease];
        
        [item setTarget:self];
        [item setRepresentedObject:song];
        [theMenu insertItem:item atIndex:0];
        ++addedSongs;
		//    ScrobTrace(@"added item to menu");
    }
    
    if (addedSongs) {
        if (songActionMenu && (song = [self nowPlaying])) {
            // Setup the action menu for the currently playing song  
            NSMenu *m = [songActionMenu copy];
            NSMenuItem *item;
            if ([song isLastFmRadio]) {
                NSString *title = [NSString stringWithFormat:@"%C ", 0x27A0];
                item = [[NSMenuItem alloc] initWithTitle:[title stringByAppendingString:NSLocalizedString(@"Skip", "")]
                    action:@selector(skip) keyEquivalent:@""];
                [item setTarget:[ISRadioController sharedInstance]];
                [item setTag:MACTION_SKIP];
                [item setEnabled:YES];
                @try {
                [m insertItem:item atIndex:[m indexOfItemWithTag:MACTION_RECOMEND_TAG]+1];
                } @catch (id e) {
                    ScrobDebug(@"exception: %@", e);
                }
                [item release];
                
                // Use the radio ban instead of the XML one so that the track is skipped as well as banned
                item = [m itemWithTag:MACTION_BAN_TAG];
                [item setAction:@selector(ban)];
                [item setTarget:[ISRadioController sharedInstance]];
            }
            [[m itemArray] makeObjectsPerformSelector:@selector(setRepresentedObject:) withObject:song];
            
            item = [theMenu itemAtIndex:0];
            ISASSERT(song == [item representedObject], "songs don't match!");
            [item setAction:nil];
            [item setSubmenu:m];
            if ([song isLastFmRadio]) {
                NSString *tip;
                unsigned int days, hours, minutes, seconds;
                ISDurationsFromTime([[song duration] unsignedIntValue], &days, &hours, &minutes, &seconds);
                if (0 == hours)
                    tip = [NSString stringWithFormat:@"%@: %u:%02u", NSLocalizedString(@"Duration", ""), minutes, seconds];
                else
                    tip = [NSString stringWithFormat:@"%@: %u:%02u:%02u", NSLocalizedString(@"Duration", ""), hours, minutes, seconds];
                [item setToolTip:tip];
            }
            [m release];
            
        }
        [theMenu insertItem:[NSMenuItem separatorItem] atIndex:addedSongs];
    }
}

-(IBAction)clearMenu:(id)sender{
    NSMenuItem *item;
    NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
	
	ScrobTrace(@"clearing menu");
    [songList removeAllObjects];
    
	while(item=[enumerator nextObject])
        if([item action]==@selector(playSong:))
            [theMenu removeItem:item];
	
    // remove the first separator
    if ([theMenu numberOfItems] && [[theMenu itemAtIndex:0] isSeparatorItem])
        [theMenu removeItemAtIndex:0];
}

-(IBAction)playSong:(id)sender{
    static NSAppleScript *iTunesPlayTrackScript = nil;
    
    if (!iTunesPlayTrackScript) {
        NSURL *file = [NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                    stringByAppendingPathComponent:@"Scripts/iTunesPlaySpecifiedTrack.scpt"]];
        iTunesPlayTrackScript = [[NSAppleScript alloc] initWithContentsOfURL:file error:nil];
        if (!iTunesPlayTrackScript) {
            ScrobLog(SCROB_LOG_CRIT, @"Could not load iTunesPlaySpecifiedTrack.scpt!\n");
            [self showApplicationIsDamagedDialog];
            return;
        }
    }
    
    SongData *song = [sender representedObject];
	
    if (![song playlistID] || ![song sourceName]) {
        ScrobLog(SCROB_LOG_WARN, @"Can't play track '%@' -- missing iTunes library info.", [song brief]);
        return;
    }
    
    @try {
        (void)[iTunesPlayTrackScript executeHandler:@"PlayTrack" withParameters:[song sourceName],
            [song playlistID], [NSNumber numberWithInt:[song iTunesDatabaseID]], nil];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Can't play track -- script error: %@.", exception);
    }
}

-(IBAction)openPrefs:(id)sender{
    // ScrobTrace(@"opening prefs");
    
    if(!preferenceController)
        preferenceController=[[PreferenceController alloc] init];
    
    // Update iTunes playlists
    if ([prefs boolForKey:@"Sync iPod"])
        [self iTunesPlaylistUpdate:nil];
    
    [NSApp activateIgnoringOtherApps:YES];
    [preferenceController showPreferencesWindow];
}

-(IBAction)openScrobblerHomepage:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"http://www.last.fm/group/iScrobbler"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

-(IBAction)openUserHomepage:(id)sender
{
    NSString *prefix = @"http://www.last.fm/user/";
    NSURL *url = [NSURL URLWithString:[prefix stringByAppendingString:[prefs stringForKey:@"username"]]];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

-(IBAction)openStatistics:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    [[StatisticsController sharedInstance] showWindow:sender];
}

-(IBAction)openTopLists:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    [[TopListsController sharedInstance] showWindow:sender];
}

- (IBAction)donate:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:
        [NSURL URLWithString:@"http://www.bergstrand.org/brian/donate"]];
}

-(void) handlePrefsChanged:(NSNotification *)aNotification
{
    // Song Count
    while([songList count]>[prefs integerForKey:@"Number of Songs to Save"])
        [songList removeObject:[songList lastObject]];
    [self updateMenu];

// We don't have a UI to control this pref because it would cause support nightmares
// with noobs enabling it w/o actually knowing what it does. If a UI is ever added,
// enable the following code block.
#ifdef notyet
    // Status menu
    [self enableStatusItemMenu:
        [[NSUserDefaults standardUserDefaults] boolForKey:@"Display Control Menu"]];
#endif
}

-(void)dealloc{
	[nc removeObserver:self];
	[nc release];
	[statusItem release];
	[songList release];
	[script release];
	KillQueueTimer();
	[prefs release];
	[preferenceController release];
	[super dealloc];
}

- (NSString *)md5hash:(id)input
{
	if ([input isKindOfClass:[NSString class]])
        input = [input dataUsingEncoding:NSUTF8StringEncoding];
    else if (nil == input || NO == [input isKindOfClass:[NSData class]])
        return (nil);
    
    unsigned char *hash = MD5((unsigned char*)[input bytes], [input length], NULL);
	int i;
    
	NSMutableString *hashString = [NSMutableString string];
	
    // Convert the binary hash into a string
    for (i = 0; i < MD5_DIGEST_LENGTH; i++)
		[hashString appendFormat:@"%02x", *hash++];
    
    return (hashString);
}

-(SongData*)nowPlaying
{
    return (!currentSongPaused ? currentSong : nil);
}

#define URI_RESERVED_CHARS_TO_ESCAPE CFSTR(";/+?:@&=$,")
- (NSString*)stringByEncodingURIChars:(NSString*)str
{
    // last.fm double encodes everything for URLs
    // i.e. '/' is %2F but last.fm enocodes the '%' char too so
    // the final form is %252f
    str = [(NSString*)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
        (CFStringRef)str, CFSTR(" "), URI_RESERVED_CHARS_TO_ESCAPE, kCFStringEncodingUTF8) autorelease];
    str = (NSString*)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
        (CFStringRef)str, CFSTR(" "), NULL, kCFStringEncodingUTF8);
    return ([str autorelease]);
}

-(NSURL*)audioScrobblerURLWithArtist:(NSString*)artist trackTitle:(NSString*)title
{
    static NSString *baseURL = nil;
    static NSString *artistTitlePathSeparator = nil;
    
    if (!artist)
        return (nil);
    
    if (!baseURL) {
        baseURL = [[NSUserDefaults standardUserDefaults]
            objectForKey:@"AS Artist Root URL"];
        if (!baseURL)
            baseURL = @"http://www.last.fm/music/";
        artistTitlePathSeparator = [[NSUserDefaults standardUserDefaults]
            objectForKey:@"AS Artist-Track Path Separator"];
        if (!artistTitlePathSeparator)
            artistTitlePathSeparator = @"/_/";
    }
    
    NSMutableString *url = [[baseURL mutableCopy] autorelease];
    
    artist = [self stringByEncodingURIChars:artist];
    if (!title)
        [url appendString:artist];
    else {
        title = [self stringByEncodingURIChars:title];
        [url appendFormat:@"%@%@%@", artist, artistTitlePathSeparator, title];
    }
    // Replace spaces with + (why doesn't AS use %20)?
    [url replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [url length])];
    return ([NSURL URLWithString:url]); // This will throw if nil or an invalid url
}

-(IBAction)cleanLog:(id)sender
{
    ScrobLogTruncate();
}

-(IBAction)performFindPanelAction:(id)sender
{
    NSWindow *w = [NSApp keyWindow];
    if (w && [[w windowController] respondsToSelector:@selector(performFindPanelAction:)])
        [[w windowController] performFindPanelAction:sender];
    else
        NSBeep();
}

- (void)badCredentialsDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    if (returnCode == NSAlertDefaultReturn)
		[self performSelector:@selector(openPrefs:) withObject:nil afterDelay:0.0];
	else if (returnCode == NSAlertAlternateReturn)
		[self openScrobblerHomepage:self];
    
    badAuthAlertIsOpen = NO;
    [(id)contextInfo performSelector:@selector(close) withObject:nil afterDelay:0.0];
}

- (void)showBadCredentialsDialog
{
    if (badAuthAlertIsOpen)
        return;
    
	// we should give them the option to ignore
	// these messages, and only update the menu icon... -- ECS 10/30/04
    NSError *error = [NSError errorWithDomain:@"iscrobbler" code:0 userInfo:
        [NSDictionary dictionaryWithObjectsAndKeys:
            NSLocalizedString(@"Authentication Failure", nil), NSLocalizedFailureReasonErrorKey,
            NSLocalizedString(@"Last.fm did not accept your username and/or password.  Please verify your credentials are set correctly in the iScrobbler preferences.", nil),
                NSLocalizedDescriptionKey,
            NSLocalizedString(@"Open iScrobbler Preferences", nil), @"defaultButton",
             NSLocalizedString(@"New Account", nil), @"alternateButton",
            nil]];
    
    [self presentError:error withDidEndHandler:@selector(badCredentialsDidEnd:returnCode:contextInfo:)];
    badAuthAlertIsOpen = YES;
}

- (void)presentError:(NSError*)error withDidEndHandler:(SEL)selector
{
    [NSApp activateIgnoringOtherApps:YES];
    
    // Create a new transparent window (with click through) so that we don't block the app event loop
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, 100.0, 100.0)
        styleMask:NSBorderlessWindowMask
        backing:NSBackingStoreBuffered defer:NO];
    [w setReleasedWhenClosed:YES];
    [w setHasShadow:NO];
    [w setBackgroundColor:[NSColor clearColor]];
    [w setAlphaValue:0.0];
    // Switch to Nonretained after making above settings to avoid
    // nasty console messages from the window server about an
    // "invalid window type"
    [w setBackingType:NSBackingStoreNonretained];
    // This has to be done before changing click through properties,
    // otherwise things won't work
    [w orderFront:nil];
    // Carbon apps
    (void)ChangeWindowAttributes ([w windowRef], kWindowIgnoreClicksAttribute, kWindowNoAttributes);
    [w setIgnoresMouseEvents:YES]; // For Cocoa apps
    // [w setDelegate:self];
    [w center];
    
    NSDictionary *info = [error userInfo];
    
    // A sheet sliding out from the middle of nowhere looks weird, so set a very small delay
    [[NSUserDefaults standardUserDefaults] setFloat:.001 forKey:@"NSWindowResizeTime"];
    
    NSAlert *a = [NSAlert alertWithMessageText:[info objectForKey:NSLocalizedFailureReasonErrorKey]
        defaultButton:[info objectForKey:@"defaultButton"]
        // the old NSBegin*AlertSheet() APIs hand the meaning of other and alternate buttons reversed
        alternateButton:[info objectForKey:@"otherButton"]
        otherButton:[info objectForKey:@"alternateButton"]
        informativeTextWithFormat:
        [info objectForKey:NSLocalizedDescriptionKey], nil];
    [a beginSheetModalForWindow:w modalDelegate:self didEndSelector:selector contextInfo:w];
    
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSWindowResizeTime"];
}

- (void)showApplicationIsDamagedDialog
{
	[NSApp activateIgnoringOtherApps:YES];
	int result = NSRunCriticalAlertPanel(NSLocalizedString(@"Critical Error", nil),
        NSLocalizedString(@"The iScrobbler application appears to be damaged.  Please download a new copy from the iScrobbler homepage.", nil),
        NSLocalizedString(@"Quit", nil),
        NSLocalizedString(@"Open iScrobbler Homepage", nil), nil);
	if (result == NSAlertAlternateReturn)
		[self openScrobblerHomepage:self];
	
	[NSApp terminate:self];
}

// Track menu actions
- (IBAction)openTrackURL:(id)sender
{
    SongData *song = [sender representedObject];
    if (!song)
        return;
    
    NSURL *url = [self audioScrobblerURLWithArtist:[song artist] trackTitle:
        MACTION_OPEN_TRACK_PAGE == [sender tag] ? [song title] : nil];
    if (url)
        [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)loveTrack:(id)sender
{
    SongData *song = [sender representedObject];
    
    ASXMLRPC *req = [[ASXMLRPC alloc] init];
    [req setMethod:@"loveTrack"];
    NSMutableArray *p = [req standardParams];
    [p addObject:[song artist]];
    [p addObject:[song title]];
    [req setParameters:p];
    [req setDelegate:self];
    [req setRepresentedObject:song];
    [req sendRequest];
}

- (IBAction)banTrack:(id)sender
{
    SongData *song = [sender representedObject];
    
    ASXMLRPC *req = [[ASXMLRPC alloc] init];
    [req setMethod:@"banTrack"];
    NSMutableArray *p = [req standardParams];
    [p addObject:[song artist]];
    [p addObject:[song title]];
    [req setParameters:p];
    [req setDelegate:self];
    [req setRepresentedObject:song];
    [req sendRequest];
}

- (void)recommendSheetDidEnd:(NSNotification*)note
{
    ISRecommendController *rc = [note object];
    if ([rc send]) {
        ASXMLRPC *req = [[ASXMLRPC alloc] init];
        NSMutableArray *p = [req standardParams];
        SongData *song = [rc representedObject];
        switch ([rc type]) {
            case rt_track:
                [req setMethod:@"recommendTrack"];
                [p addObject:[song artist]];
                [p addObject:[song title]];
            break;
            
            case rt_artist:
                [req setMethod:@"recommendArtist"];
                [p addObject:[song artist]];
            break;
            
            case rt_album:
                [req setMethod:@"recommendAlbum"];
                [p addObject:[song artist]];
                [p addObject:[song album]];
            break;
            
            default:
                [req release];
                goto exit;
            break;
        }
        [p addObject:[rc who]];
        [p addObject:[rc message]];
        
        [req setParameters:p];
        [req setDelegate:self];
        [req setRepresentedObject:song];
        [req sendRequest];
    }
    
exit:
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISRecommendDidEnd object:rc];
    [rc release];
}

- (IBAction)recommendTrack:(id)sender
{
    SongData *song = [sender representedObject];
    
    ISRecommendController *rc = [[ISRecommendController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recommendSheetDidEnd:)
        name:ISRecommendDidEnd object:rc];
    [rc setRepresentedObject:song];
    [NSApp activateIgnoringOtherApps:YES];
    [[rc window] setTitle:[NSString stringWithFormat:@"%@ - %@", [song artist], [song title]]];
    [[rc window] center];
    [rc showWindow:nil];
}

- (void)tagSheetDidEnd:(NSNotification*)note
{    
    ISTagController *tc = [note object];
    NSArray *tags = [tc tags];
    if (tags && [tc send]) {
        ASXMLRPC *req = [[ASXMLRPC alloc] init];
        NSMutableArray *p = [req standardParams];
        SongData *song = [tc representedObject];
        NSString *mode = [tc editMode] == tt_overwrite ? @"set" : @"append";
        switch ([tc type]) {
            case tt_track:
                [req setMethod:@"tagTrack"];
                [p addObject:[song artist]];
                [p addObject:[song title]];
            break;
            
            case tt_artist:
                [req setMethod:@"tagArtist"];
                [p addObject:[song artist]];
            break;
            
            case tt_album:
                [req setMethod:@"tagAlbum"];
                [p addObject:[song artist]];
                [p addObject:[song album]];
            break;
            
            default:
                [req release];
                goto exit;
            break;
        }
        [p addObject:tags];
        [p addObject:mode];
        
        [req setParameters:p];
        [req setDelegate:self];
        [req setRepresentedObject:song];
        [req sendRequest];
    }

exit:
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISTagDidEnd object:tc];
    [tc release];
}

- (IBAction)tagTrack:(id)sender
{
    SongData *song = [sender representedObject];
    
    ISTagController *tc = [[ISTagController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tagSheetDidEnd:)
        name:ISTagDidEnd object:tc];
    [tc setRepresentedObject:song];
    [NSApp activateIgnoringOtherApps:YES];
    [[tc window] setTitle:[NSString stringWithFormat:@"%@ - %@", [song artist], [song title]]];
    [[tc window] center];
    [tc showWindow:nil];
}

#ifdef notyet
- (IBAction)showLovedBanned:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    [[ISLoveBanListController sharedController] showWindow:[self window]];
}
#endif

// ASXMLRPC
- (void)responseReceivedForRequest:(ASXMLRPC*)request
{
    if (NSOrderedSame != [[request response] compare:@"OK" options:NSCaseInsensitiveSearch]) {
        NSError *err = [NSError errorWithDomain:@"iScrobbler" code:-1 userInfo:
            [NSDictionary dictionaryWithObject:[request response] forKey:@"Response"]];
        [self error:err receivedForRequest:request];
        return;
    }
    
    NSString *method = [request method];
    NSString *tag = nil;
    if ([method isEqualToString:@"loveTrack"]) {
        [[request representedObject] setLoved:YES];
        tag = @"loved";
    } else if ([method isEqualToString:@"banTrack"]) {
        [[request representedObject] setBanned:YES];
        tag = @"banned";
    } else if ([method hasPrefix:@"tag"])
        [ASXMLFile expireCacheEntryForURL:[ASWebServices currentUserTagsURL]];
    
    ScrobLog(SCROB_LOG_TRACE, @"RPC request '%@' successful (%@)",
        method, [request representedObject]);
    
    if (tag && [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTagLovedBanned"]) {
        ASXMLRPC *tagReq = [[ASXMLRPC alloc] init];
        NSMutableArray *p = [tagReq standardParams];
        SongData *song = [request representedObject];
        [tagReq setMethod:@"tagTrack"];
        [p addObject:[song artist]];
        [p addObject:[song title]];
        [p addObject:[NSArray arrayWithObject:tag]];
        [p addObject:@"append"];
        
        [tagReq setParameters:p];
        [tagReq setDelegate:self];
        [tagReq setRepresentedObject:song];
        [tagReq performSelector:@selector(sendRequest) withObject:nil afterDelay:0.0];
    }
    
    [request autorelease];
}

- (void)error:(NSError*)error receivedForRequest:(ASXMLRPC*)request
{
    ScrobLog(SCROB_LOG_ERR, @"RPC request '%@' for '%@' returned error: %@",
        [request method], [request representedObject], error);
    
    [request autorelease];
}

- (void)iPodSyncBegin:(NSNotification*)note
{

}

- (void)iPodSyncEnd:(NSNotification*)note
{
#ifndef __LP64__
    NSString *msg = [[note userInfo] objectForKey:IPOD_SYNC_KEY_SCRIPT_MSG];
    if (!msg)
        msg = [NSString stringWithFormat:@"%@ %@", [[note userInfo] objectForKey:IPOD_SYNC_KEY_TRACK_COUNT], NSLocalizedString(@"tracks submitted", "")];
    [GrowlApplicationBridge
            notifyWithTitle:NSLocalizedString(@"iPod Sync Finished", "")
            description:msg
            notificationName:IS_GROWL_NOTIFICATION_IPOD_DID_SYNC
            iconData:nil
            priority:0.0
            isSticky:NO
            clickContext:nil];
#else
; // Growl not 64bit yet
#endif
}

// Bindings

- (BOOL)isIPodMounted
{
    return ((BOOL)(iPodMountCount > 0));
}

- (void)setIsIPodMounted:(BOOL)val
{
    // just here, so KVO notifications work
}

- (void)growlNotificationWasClicked:(id)context
{
    ISASSERT([context isKindOfClass:[NSString class]], @"click context is not a string!");
    [[NSNotificationCenter defaultCenter] postNotificationName:context object:nil];
}

// AppleScript support
// Useful debug info: defaults write NSGlobalDomain NSScriptingDebugLogLevel 1
- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key
{
    ScrobDebug(@"wants key: %@", key);
    return ([key isEqualToString:@"lastfmUser"]
        || [key isEqualToString:@"queueSubmissions"]
        || [key isEqualToString:@"scrobbleTracks"]
        || [key isEqualToString:@"queueSubmissions"]
        || [key isEqualToString:@"radioController"]);
}

#ifdef ISDEBUG
- (id)valueForUndefinedKey:(NSString*)key
{
    ScrobDebug(@"%@", key);
    return (nil);
}

- (id)valueWithName:(NSString *)name inPropertyWithKey:(NSString *)key
{
    ScrobDebug(@"name: %@, key: %@", name, key);
    return (nil);
}
#endif

- (id)valueWithUniqueID:(id)uniqueID inPropertyWithKey:(NSString *)key
{
    ScrobDebug(@"uuid: %@, key: %@", uniqueID, key);
    return ([key isEqualToString:@"radioController"] ? [ISRadioController sharedInstance] : nil);
}

- (id)radioController
{
    return ([ISRadioController sharedInstance]);
}

- (NSString*)lastfmUser
{
    return ([[ProtocolManager sharedInstance] userName]);
}

- (BOOL)queueSubmissions
{
    return ([[NSUserDefaults standardUserDefaults] boolForKey:@"ForcePlayCache"]);
}

- (void)setQueueSubmissions:(BOOL)queue
{
    BOOL forceCache = ![[NSUserDefaults standardUserDefaults] boolForKey:@"ForcePlayCache"];
    [[NSUserDefaults standardUserDefaults] setBool:forceCache forKey:@"ForcePlayCache"];
    ScrobLog(SCROB_LOG_TRACE, @"ForcePlayCache %@\n", forceCache ? @"set" : @"unset");
    
    if (!forceCache)
        [[QueueManager sharedInstance] performSelector:@selector(submit) withObject:nil afterDelay:0.0];
}

- (BOOL)scrobbleTracks
{
    return (!submissionsDisabled);
}

- (void)setScrobbleTracks:(BOOL)scrob
{
    [self setSubmissionsEnabled:scrob];
}

// commands

- (id)flushCaches:(NSScriptCommand*)command
{
    [SongData drainArtworkCache];
    [ASXMLFile expireAllCacheEntries];
    return (nil);
}

// End AppleScript

@end

@interface ISAppScriptCommand : NSScriptCommand {
}
@end

@implementation ISAppScriptCommand

- (id)performDefaultImplementation
{
    NSMenuItem *item;
    switch ([[self commandDescription] appleEventCode]) {
        case 'Fcch': // flush caches
            [[NSApp delegate] performSelector:@selector(flushCaches:) withObject:self afterDelay:0.0];
        break;
        case 'NPly': // show now playing
            [[NSApp delegate] performSelector:@selector(displayNowPlaying) withObject:nil afterDelay:0.0];
        break;
        case 'TagS': // tag currently playing song
            item = [[[NSApp delegate] valueForKey:@"theMenu"] itemAtIndex:0];
            if ([item hasSubmenu]) {
                if ((item = [[item submenu] itemWithTag:MACTION_TAG_TAG]))
                    [[NSApp delegate] performSelector:@selector(tagTrack:) withObject:item afterDelay:0.0];
            }
        break;
        case 'LovS': // love currently playing song
            item = [[[NSApp delegate] valueForKey:@"theMenu"] itemAtIndex:0];
            if ([item hasSubmenu]) {
                if ((item = [[item submenu] itemWithTag:MACTION_LOVE_TAG]))
                    [[NSApp delegate] performSelector:@selector(loveTrack:) withObject:item afterDelay:0.0];
            }
        break;
        case 'BanS': // ban currently playing song
            item = [[[NSApp delegate] valueForKey:@"theMenu"] itemAtIndex:0];
            if ([item hasSubmenu]) {
                if ((item = [[item submenu] itemWithTag:MACTION_BAN_TAG]))
                    [[NSApp delegate] performSelector:@selector(banTrack:) withObject:item afterDelay:0.0];
            }
        break;
        default:
            ScrobLog(SCROB_LOG_TRACE, @"ISAppScriptCommand: unknown aevt code: %c", [[self commandDescription] appleEventCode]);
        break;
    }
    return (nil);
}

@end

@implementation SongData (iScrobblerControllerAdditions)

- (SongData*)initWithiTunesPlayerInfo:(NSDictionary*)dict
{
    self = [self init];
    
    NSString *iname, *ialbum, *iartist, *ipath, *igenre;
    NSURL *location = nil;
    NSNumber *irating, *iduration, *itrackNumber;
#ifdef notyet
    NSString *composer;
    NSNumber *year;
#endif
    NSTimeInterval durationInSeconds;
    
    iname = [dict objectForKey:@"Name"];
    ialbum = [dict objectForKey:@"Album"];
    iartist = [dict objectForKey:@"Artist"];
    ipath = [dict objectForKey:@"Location"];
    irating = [dict objectForKey:@"Rating"];
    iduration = [dict objectForKey:@"Total Time"];
    igenre = [dict objectForKey:@"Genre"];
    itrackNumber = [dict objectForKey:@"Track Number"];
    
    if (ipath) {
        @try {
        location = [NSURL URLWithString:ipath];
        } @catch(id e) {location = nil;}
    }
    
    if (!iname || !iartist || !iduration /*|| (location && ![location isFileURL])*/) {
        //if (!(location && [location isFileURL])) // don't allow streaming URLs
        if (!location || [location isFileURL])
            ScrobLog(SCROB_LOG_WARN, @"Invalid song data: track name, artist, or duration is missing.\n");
        [self dealloc];
        return (nil);
    }
    
    [self setTitle:iname];
    [self setArtist:iartist];
    durationInSeconds = floor([iduration doubleValue] / 1000.0); // Convert from milliseconds
    [self setDuration:[NSNumber numberWithDouble:durationInSeconds]];
    if (ialbum)
        [self setAlbum:ialbum];
    if (location && [location isFileURL])
        [self setPath:[location path]];
    if (irating)
        [self setRating:irating];
    if (igenre)
        [self setGenre:igenre];
    if (itrackNumber)
        [self setTrackNumber:itrackNumber];

    [self setPostDate:[NSCalendarDate date]];
    [self setHasQueued:NO];
    
    // extra data from a last.fm stream
    id o = [dict objectForKey:@"last.fm"];
    if (o) {
        isLastFmRadio = YES;
        [self setType:trackTypeShared];
        
        // Load artwork if possible
        @try {
        if (!(ialbum = [[[ASWebServices sharedInstance] nowPlayingInfo] objectForKey:@"albumcover_medium"]))
            ialbum = [[[ASWebServices sharedInstance] nowPlayingInfo] objectForKey:@"albumcover_small"];
        
        if (ialbum)
            [self loadAlbumArtFromURL:[NSURL URLWithString:ialbum]];
        } @catch (id e) {}
        
        ScrobDebug(@"created '%@' track from last.fm radio", [self brief]);
    }
    
    return (self);
}

- (void)updateUsingSong:(SongData*)song
{
    [self setPosition:[song position]];
    [self setRating:[song rating]];
    [self setIsPlayeriTunes:[song isPlayeriTunes]];
    if ((isLastFmRadio = [song isLastFmRadio]))
        [self setType:trackTypeShared];
}

- (NSString*)growlDescriptionWithFormat:(NSString*)format
{
    NSMutableString *fmt = [format mutableCopy];
    @try {
        NSRange r = [fmt rangeOfString:@"%t"];
        if (NSNotFound != r.location)
            [fmt replaceCharactersInRange:r withString:[self title]];
        
        r = [fmt rangeOfString:@"%r"];
        if (NSNotFound != r.location)
            [fmt replaceCharactersInRange:r withString:[self starRating]];
        
        r = [fmt rangeOfString:@"%A"];
        if (NSNotFound != r.location)
            [fmt replaceCharactersInRange:r withString:[self album]];
        
        r = [fmt rangeOfString:@"%a"];
        if (NSNotFound != r.location)
            [fmt replaceCharactersInRange:r withString:[self artist]];
        
        r = [fmt rangeOfString:@"%d"];
        if (NSNotFound != r.location) {
            NSString *timeStr;
            unsigned time = [[self duration] unsignedIntValue];
            unsigned days, hours, mins, secs;
            ISDurationsFromTime(time, &days, &hours, &mins, &secs);
            
            if (time < 3600)
                timeStr = [NSString stringWithFormat:@"%u:%02u", mins, secs];
            else
                timeStr = [NSString stringWithFormat:@"%u:%02u:%02u", hours, mins, secs];
            
            time = [[self elapsedTime] unsignedIntValue];
            if (time > 0) {
                NSString *tmp;
                ISDurationsFromTime(time, &days, &hours, &mins, &secs);
                if (time < 3600)
                    tmp = [NSString stringWithFormat:@"%u:%02u", mins, secs];
                else
                    tmp = [NSString stringWithFormat:@"%u:%02u:%02u", hours, mins, secs];
                
                timeStr = [NSString stringWithFormat:@"%@/%@", tmp, timeStr];
            }
            
            [fmt replaceCharactersInRange:r withString:timeStr];
        }
        
        [fmt replaceOccurrencesOfString:@"%n" withString:@"\n" options:0 range:NSMakeRange(0, [fmt length])];
        
        if ([fmt hasSuffix:@"\n"])
            [fmt deleteCharactersInRange:NSMakeRange([fmt length]-1, 1)];
        
        return ([fmt autorelease]);
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"%s: -Exception- %@ while processing %@\n", __FUNCTION__, e,
            [[NSUserDefaults standardUserDefaults] stringForKey:@"GrowlPlayFormat"]);
    }
    
    [fmt release];
    return (@"");
}

- (NSString*)growlDescription
{
    NSString *f = [[NSUserDefaults standardUserDefaults] stringForKey:@"GrowlPlayFormat"];
    if ([self isLastFmRadio] && NSNotFound == [f rangeOfString:@"%d"].location)
        f = [@"%d%n" stringByAppendingString:f];
    return ([self growlDescriptionWithFormat:f]);
}

- (NSString*)growlTitle
{
    
    return ([self growlDescriptionWithFormat:[[NSUserDefaults standardUserDefaults] stringForKey:@"GrowlPlayTitle"]]);
}

@end

@implementation NSMutableArray (iScrobblerContollerFifoAdditions)
- (void)pushSong:(id)obj
{
    if ([self count])
        [self insertObject:obj atIndex:0];
    else
        [self addObject:obj];
}
@end

#if 0
@implementation NSScriptCommand (ISExtensions)

- (id) evaluatedDirectParameters
{
    id param = [self directParameter];
    if ([param isKindOfClass: [NSScriptObjectSpecifier class]])
    {
        NSScriptObjectSpecifier *spec = (NSScriptObjectSpecifier *)param;
        id container = [[spec containerSpecifier] objectsByEvaluatingSpecifier];
        param = [spec objectsByEvaluatingWithContainers: container];
    }
    return param;
}

@end
#endif

void ISDurationsFromTime(unsigned int time, unsigned int *days, unsigned int *hours,
    unsigned int *minutes, unsigned int *seconds)
{
    *days = time / 86400U;
    *hours = (time % 86400U) / 3600U;
    *minutes = ((time % 86400U) % 3600U) / 60U;
    *seconds = ((time % 86400U) % 3600U) % 60U;
}

void ISDurationsFromTime64(unsigned long long time, unsigned int *days, unsigned int *hours,
    unsigned int *minutes, unsigned int *seconds)
{
    *days = (time / 86400U);
    *hours = (time % 86400U) / 3600U;
    *minutes = ((time % 86400U) % 3600U) / 60U;
    *seconds = ((time % 86400U) % 3600U) % 60U;
}

#include "iScrobblerController+Private.m"

static void iokpm_callback (void *myData, io_service_t service, natural_t message, void *arg)
{
    ScrobDebug(@"power event - code = %x", err_get_code(message));

    switch(message) {
        // must always respond to the power state change messages
        case kIOMessageSystemWillSleep:
        case kIOMessageCanSystemSleep:
        // we can't prevent user initiated power off, only idle power off
        case kIOMessageSystemWillPowerOff:
        case kIOMessageSystemWillRestart:
            IOAllowPowerChange(powerPort, (long)arg);
        break;
        
        case kIOMessageCanSystemPowerOff:
            if (isTopListsActive && [[PersistentProfile sharedInstance] importInProgress]) {
                IOCancelPowerChange(powerPort, (long)arg);
            } else
                IOAllowPowerChange(powerPort, (long)arg);
        break;

        default:
        break;
    };
}

