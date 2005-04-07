//
//  iScrobblerController.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net/

#import <openssl/md5.h>

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

@interface iScrobblerController (iScrobblerControllerPrivate)

- (IBAction)syncIPod:(id)sender;
- (void) restoreITunesLastPlayedTime;
- (void) setITunesLastPlayedTime:(NSDate*)date;

- (void) volumeDidMount:(NSNotification*)notification;
- (void) volumeDidUnmount:(NSNotification*)notification;

- (void)iTunesPlaylistUpdate:(NSTimer*)timer;

@end

@interface iScrobblerController (Private)
    - (void)showNewVersionExistsDialog;
@end

// See iTunesPlayerInfoHandler: for why this is needed
@interface ProtocolManager (NoCompilerWarnings)
    - (float)minTimePlayed;
@end

#define CLEAR_MENUITEM_TAG          1
#define SUBMIT_IPOD_MENUITEM_TAG    4

@interface SongData (iScrobblerControllerAdditions)
    - (SongData*)initWithiTunesResultString:(NSString*)string;
    - (SongData*)initWithiTunesPlayerInfo:(NSDictionary*)dict;
    - (void)updateUsingSong:(SongData*)song;
@end

@interface NSMutableArray (iScrobblerContollerLifoAdditions)
    - (void)push:(SongData*)song;
    - (void)pop;
    - (SongData*)peek;
@end

@implementation iScrobblerController

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    //ScrobTrace(@"%@", [anItem title]);
    if(SUBMIT_IPOD_MENUITEM_TAG == [anItem tag] &&
         (!iPodMountPath || ![prefs boolForKey:@"Sync iPod"]))
        return NO;
    return YES;
}

- (void)handshakeCompleteHandler:(NSNotification*)note
{
    ProtocolManager *pm = [note object];
    
    if (([pm updateAvailable] && ![prefs boolForKey:@"Disable Update Notification"]))
        [self showNewVersionExistsDialog];
    else if ([[pm lastHandshakeResult] isEqualToString:HS_RESULT_BADAUTH])
        [self showBadCredentialsDialog];
}

- (void)badAuthHandler:(NSNotification*)note
{
    [self showBadCredentialsDialog];
}

- (BOOL)updateInfoForSong:(SongData*)song
{
    // Run the script to get the info not included in the dict
    NSDictionary *errInfo;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&errInfo] ;
    if (result) {
        if ([result numberOfItems] > 1) {
            TrackType_t trackType = trackTypeUnknown;
            int trackPosition = -1, trackiTunesDatabaseID = -1, trackRating = 0;
            NSString *trackLastPlayed = nil;
            NSAppleEventDescriptor *desc;
            @try {
                // NSAppleEventDescriptor indices are 1 based
                desc = [result descriptorAtIndex:1];
                trackType = (TrackType_t)[desc int32Value];
                desc = [result descriptorAtIndex:2];
                trackiTunesDatabaseID = [desc int32Value];
                desc = [result descriptorAtIndex:3];
                trackPosition = [desc int32Value];
                desc = [result descriptorAtIndex:4];
                trackRating = [desc int32Value];
                desc = [result descriptorAtIndex:5];
                trackLastPlayed = [desc stringValue];
            } @catch (NSException *exception) {
                ScrobLog(SCROB_LOG_ERR, @"GetSongInfo script invalid result: parsing exception %@\n.", exception);
                return (NO);
            }
            
            if (IsTrackTypeValid(trackType) && trackiTunesDatabaseID >= 0 && trackPosition >= 0) {
                [song setType:trackType];
                [song setiTunesDatabaseID:trackiTunesDatabaseID];
                [song setPosition:[NSNumber numberWithInt:trackPosition]];
                
                if (trackRating >= 0 && trackRating <= 100) {
                    [song setRating:[NSNumber numberWithInt:trackRating]];
                }
            } else {
                ScrobLog(SCROB_LOG_ERR, @"GetSongInfo script invalid result: bad type, db id, or position (%d:%d:%d)\n.",
                    trackType, trackiTunesDatabaseID, trackPosition);
                return (NO);
            }
        } else {
            ScrobLog(SCROB_LOG_ERR, @"GetSongInfo script invalid result: bad item count: %d\n.", [result numberOfItems]);
            return (NO);
        }
    } else {
        ScrobLog(SCROB_LOG_ERR, @"GetSongInfo script execution error: %@\n.", errInfo);
        return (NO);
    }
    
    return (YES);
}

#define KillQueueTimer() do { \
[currentSongQueueTimer invalidate]; \
[currentSongQueueTimer release]; \
currentSongQueueTimer = nil; \
} while (0) 

- (void)queueCurrentSong:(NSTimer*)timer
{
    SongData *song = [[SongData alloc] init];
    
    KillQueueTimer();
    timer = nil;
    
    if (!currentSong || (currentSong && [currentSong hasQueued]) || ![self updateInfoForSong:song]) {
        [song release];
        return;
    }
    
    if ([song iTunesDatabaseID] == [currentSong iTunesDatabaseID]) {
        [currentSong updateUsingSong:song];
        
        // Try submission
        QueueResult_t qr = [[QueueManager sharedInstance] queueSong:currentSong];
        if (kqFailed == qr) {
            // Fire ourself again in half of the remaining track play time.
            // The queue can fail when playing from a network stream (or CD),
            // and iTunes has to re-buffer. This means the elapsed track play time
            // would be less than elapsed real-world time and the track may not be 1/2
            // done.
            double fireInterval = [[currentSong duration] doubleValue] -
                [[currentSong position] doubleValue];
            if (fireInterval > 1.0)
                fireInterval /= 2.0;
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
        ScrobLog(SCROB_LOG_ERR, @"Lost song! current: (%@, %d), itunes: (%@, %d)\n.",
            currentSong, [currentSong iTunesDatabaseID], song, [song iTunesDatabaseID]);
    }
    
    [song release];
}

- (void)iTunesPlayerInfoHandler:(NSNotification*)note
{
    NSDictionary *info = [note userInfo];
    static BOOL isiTunesPlaying = NO;
    BOOL wasiTunesPlaying = isiTunesPlaying;
    isiTunesPlaying = [@"Playing" isEqualToString:[info objectForKey:@"Player State"]];
    
    ScrobLog(SCROB_LOG_TRACE, @"iTunes notification received: %@\n", [info objectForKey:@"Player State"]);
    
    SongData *song = nil;
    @try {
        song = [[SongData alloc] initWithiTunesPlayerInfo:info];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Exception creating song: %@\n", exception);
    }
    if (!song)
        goto player_info_exit;
    
    if (![self updateInfoForSong:song])
        goto player_info_exit;
    
    if (currentSong && [currentSong isEqualToSong:song]) {
        // Determine if the song is being played twice (or more in a row)
        float pos = [[song position] floatValue];
        if (pos <  [[currentSong position] floatValue] &&
             // The following conditions do not work with iTunes 4.7, since we are not
             // constantly updating the song's position by polling iTunes. With 4.7 we update
             // when the the song first plays, when it's ready for submission or if the user
             // changes some song metadata -- that's it.
        #if 0
             (pos <= [SongData songTimeFudge]) &&
             // Could be a new play, or they could have seek'd back in time. Make sure it's not the latter.
             (([[firstSongInList duration] floatValue] - [[firstSongInList position] floatValue])
        #endif
             [currentSong hasQueued] &&
             (pos <= [SongData songTimeFudge]) ) {
            [currentSong release];
            currentSong = nil;
        } else {
            [currentSong updateUsingSong:song];
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
    if (currentSong && ![currentSong isEqualToSong:song] && [[currentSong duration] isEqualToNumber:[song position]]) {
        [song setPosition:[NSNumber numberWithUnsignedInt:0]];
        // Reset the start time too, since it will be off
        [song setStartTime:[NSDate date]];
    }
    
    if (isiTunesPlaying) {
        // Fire the main timer at the appropos time to get it queued.
        double fireInterval = [song submitIntervalFromNow];
        if (fireInterval > 0.0) { // Seems there's a problem with some CD's not giving us correct info.
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
        //ScrobTrace(@"Found = %i",j);

        // If the track wasn't found anywhere in the list, we add a new item
        if (found) {
            // If the trackname was found elsewhere in the list, we remove the old item
            [songList removeObjectAtIndex:found];
        }
        else
            ScrobLog(SCROB_LOG_VERBOSE, @"Added '%@'\n", [song brief]);
        [songList push:song];
        
        while ([songList count] > [prefs integerForKey:@"Number of Songs to Save"])
            [songList pop];
        
        [self updateMenu];
        
        [currentSong release];
        currentSong = song;
        song = nil; // Make sure it's not released
    }
    
player_info_exit:
    if (song)
        [song release];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"Now Playing"
        object:(isiTunesPlaying ? currentSong : nil) userInfo:nil];
    
    if (isiTunesPlaying || wasiTunesPlaying != isiTunesPlaying)
        [self setITunesLastPlayedTime:[NSDate date]];
    ScrobTrace(@"iTunesLastPlayedTime == %@\n", iTunesLastPlayedTime);
}

- (void)enableStatusItemMenu:(BOOL)enable
{
    if (enable) {
        if (!statusItem) {
            statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
            
            // 0x266B == UTF8 barred eigth notes
            [statusItem setTitle:[NSString stringWithFormat:@"%C",0x266B]];
            [statusItem setHighlightMode:YES];
            [statusItem setMenu:theMenu];
            [statusItem setEnabled:YES];
        }
    } else if (statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
        [statusItem setMenu:nil];
        [statusItem release];
        statusItem = nil;
    }
}

-(id)init
{
    // Read in a defaults.plist preferences file
    NSString * file = [[NSBundle mainBundle]
        pathForResource:@"defaults" ofType:@"plist"];
	
    NSDictionary * defaultPrefs = [NSDictionary dictionaryWithContentsOfFile:file];
	
    prefs = [[NSUserDefaults standardUserDefaults] retain];
    [prefs registerDefaults:defaultPrefs];
    
    // This sucks. We added new columns to the Top Artists and Top Tracks lists in 1.0.1. But,
    // if the saved Column/Sort orderings don't match then the new column is won't show.
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
	
	// Set the script locations
    NSURL *url=[NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                stringByAppendingPathComponent:@"Scripts/iTunesGetCurrentSongInfo.scpt"] ];
	
    // Get our iPod update script as text
    file = [[[NSBundle mainBundle] resourcePath]
                stringByAppendingPathComponent:@"iPodUpdate.applescript"];
    iPodUpdateScript = [[NSString alloc] initWithContentsOfFile:file];
    if (!iPodUpdateScript)
        ScrobLog(SCROB_LOG_CRIT, @"Failed to load iPodUpdateScript!\n");
    
    [self restoreITunesLastPlayedTime];
    
    if(self=[super init])
    {
        [NSApp setDelegate:self];
        
        script=[[NSAppleScript alloc] initWithContentsOfURL:url error:nil];
        nc=[NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(handlePrefsChanged:)
                   name:SCROB_PREFS_CHANGED
                 object:nil];
        
        // Register for mounts and unmounts (iPod support)
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
            selector:@selector(volumeDidMount:) name:NSWorkspaceDidMountNotification object:nil];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
            selector:@selector(volumeDidUnmount:) name:NSWorkspaceDidUnmountNotification object:nil];
        
        // Register for iTunes track change notifications
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(iTunesPlayerInfoHandler:) name:@"com.apple.iTunes.playerInfo"
            object:nil];
        
        // Create protocol mgr
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
        
        // Create queue mgr
        (void)[QueueManager sharedInstance];
        if ([[QueueManager sharedInstance] count])
            [[QueueManager sharedInstance] submit];
        
        // Create top lists controller so it will pick up subs
        // We do this after creating the QM so that queued subs are not counted.
        (void)[TopListsController sharedInstance];
    }
    return self;
}

- (void)awakeFromNib
{
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
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [[QueueManager sharedInstance] syncQueue:nil];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:OPEN_STATS_WINDOW_AT_LAUNCH]) {
        [self openStatistics:nil];
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH]) {
        [self openTopLists:nil];
    }
    
    if (0 == [[prefs stringForKey:@"username"] length])
        [self openPrefs:nil];
}

- (void)updateMenu
{
    NSMenuItem *item;
    NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
    SongData *song;
    int addedSongs = 0;
    // ScrobTrace(@"updating menu");
	
    // remove songs from menu
    while(item=[enumerator nextObject])
        if([item action]==@selector(playSong:))
            [theMenu removeItem:item];
    
    // Remove separator
    if ([theMenu numberOfItems] && [[theMenu itemAtIndex:0] isSeparatorItem])
        [theMenu removeItemAtIndex:0];
    
    // add songs from songList array to menu
    enumerator=[songList reverseObjectEnumerator];
    int songsToDisplay = [prefs integerForKey:@"Number of Songs to Save"];
    while ((song = [enumerator nextObject]) && addedSongs < songsToDisplay) {
        item = [[[NSMenuItem alloc] initWithTitle:[song title]
                                           action:@selector(playSong:)
                                    keyEquivalent:@""] autorelease];
        
        [item setTarget:self];
        [theMenu insertItem:item atIndex:0];
        ++addedSongs;
		//    ScrobTrace(@"added item to menu");
    }
    
    if (addedSongs)
        [theMenu insertItem:[NSMenuItem separatorItem] atIndex:addedSongs];
    
}

#if 0
-(void)mainTimer:(NSTimer *)timer
{
    NSDictionary *errInfo = nil;
    // micah_modell@users.sourceforge.net
    // Check for null and branch to avoid having the application hang.
    NSAppleEventDescriptor * executionResult = [script executeAndReturnError:&errInfo] ;
    if( nil != executionResult )
    {
        NSString *result=[[NSString alloc] initWithString:[ executionResult stringValue]];
        SongData *nowPlaying = nil;
        
    //ScrobTrace(@"timer fired");
    //ScrobTrace(@"%@",result);
    
    // If the script didn't return an error, continue
    if([result hasPrefix:@"NOT PLAYING"]) {
		
    } else if([result hasPrefix:@"RADIO"]) {
		
    } else if([result hasPrefix:@"INACTIVE"]) {
        
    } else {
		NSDate *now;
        SongData *song = [[SongData alloc] initWithiTunesResultString:result];
        
        if (NO == [prefs boolForKey:@"Shared Music Submission"] &&
             [[song path] isEqualToString:@"Shared Track"]) {
            [song release];
            goto mainTimerReleaseResult;
        }
        
        // iPod sync date management, the goal is to detect the valid songs to sync
		now = [NSDate date];
        // XXX We need to do something fancy here, because this assumes
        // the user will sync the iPod before playing anything in iTunes.
        [self setITunesLastPlayedTime:now];
        
        // If the songlist is empty, then simply add the song object to the songlist
        if([songList count]==0)
        {
            ScrobLog(SCROB_LOG_VERBOSE, @"Added '%@'\n", [song brief]);
            [songList insertObject:song atIndex:0];
            nowPlaying = song;
        }
        else
        {
            SongData *firstSongInList = [songList objectAtIndex:0];
            // Is the track equal to the track that's
            // currently in first place in the song list? If so, update the
            // play time, and queue a submission.
            if ([song isEqualToSong:firstSongInList]) {
                // Determine if the song is being played twice (or more in a row)
                float pos = [[song position] floatValue];
                nowPlaying = firstSongInList;
                
                if (pos <  [[firstSongInList position] floatValue] &&
                     // The following conditions do not work with iTunes 4.7, since we are not
                     // constantly updating the song's position by polling iTunes. With 4.7 we update
                     // when the the song first plays, when it's ready for submission or if the user
                     // changes some song metadata -- that's it.
                #if 0
                     (pos <= [SongData songTimeFudge]) &&
                     // Could be a new play, or they could have seek'd back in time. Make sure it's not the latter.
                     (([[firstSongInList duration] floatValue] - [[firstSongInList position] floatValue])
                #endif
                     [firstSongInList hasQueued] &&
                     (pos <= [SongData songTimeFudge]) ) {
                    [songList insertObject:song atIndex:0];
                    nowPlaying = song;
                } else {
                    [firstSongInList setPosition:[song position]];
                    [firstSongInList setLastPlayed:[song lastPlayed]];
                    [firstSongInList setRating:[song rating]];
                    QueueResult_t qr = [[QueueManager sharedInstance] queueSong:firstSongInList];
                    if (kqFailed == qr) {
                        // Fire ourself again in half of the remaining track play time.
                        // The queue can fail when playing from a network stream (or CD),
                        // and iTunes has to re-buffer. This means the elapsed track play time
                        // would be less than elapsed real-world time and the track may not be 1/2
                        // done.
                        // This mismatched elapsed time can also occur when the user has crossfade
                        // turned on, since the new song will actually start playing while the current
                        // song is still playing.
                        //
                        // This can also occur spuriously if the user pauses/stops the song and then plays it again.
                        double fireInterval = [[firstSongInList duration] doubleValue] -
                            [[firstSongInList position] doubleValue];
                        if (fireInterval > 1.0)
                            fireInterval /= 2.0;
                        if (fireInterval >= 1.0) {
                            if (!mainTimer) {
                                // This will only occur if we are using iTunes notifications and
                                // in that case, iTunesPlayerInfoHandler: will release mainTimer.
                                ScrobLog(SCROB_LOG_VERBOSE,
                                    @"Track '%@' failed submission rules. "
                                    @"Trying again in %0.0lf seconds.\n", [firstSongInList brief], fireInterval);
                                mainTimer = [[NSTimer scheduledTimerWithTimeInterval:fireInterval
                                                target:self
                                                selector:@selector(mainTimer:)
                                                userInfo:nil
                                                repeats:NO] retain];
                            } // else there is already a timer set to fire on the track
                        } else {
                            ScrobLog(SCROB_LOG_WARN, @"Track '%@' failed submission rules. "
                                @"There is not enough play time left to retry submission.\n",
                                [firstSongInList brief]);
                        }
                    }
                }
            } else {
                // Check to see if the current track is anywhere in the songlist
                // If it is, we set found equal to the index position where it was found
                // ScrobTrace(@"Looking for track");
                int j;
                int found = 0;
                for(j = 0; j < [songList count]; j++) {
                    if([[songList objectAtIndex:j] isEqualToSong:song])
                    {
                        found = j;
                        break;
                    }
                }
                //ScrobTrace(@"Found = %i",j);
				
                // If the track wasn't found anywhere in the list, we add a new item
                if(!found)
                {
                    ScrobLog(SCROB_LOG_VERBOSE, @"Added '%@'\n", [song brief]);
                    [songList insertObject:song atIndex:0];
                }
                // If the trackname was found elsewhere in the list, we remove the old
                // item, and add the new one onto the beginning of the list.
                else
                {
                    //ScrobTrace(@"removing old, adding new");
                    [songList removeObjectAtIndex:found];
                    [songList insertObject:song atIndex:0];
                }
                
                nowPlaying = song;
            }
        }
        // If there are more items in the list than the user wanted
        // Then we remove the last item in the songlist.
        // XXX: We always retain the most recent song so that we can submit even
        // when the "Songs to Save" pref is 0.
        // This should really be re-visted as it's not clean at all. In fact, this whole
        // method needs to be scrapped and implemented correctly. There's too much cruft left
        // over from 0.6/0.7.x and supporting < iTunes 4.7.
        while([songList count] > 1 && [songList count] > [prefs integerForKey:@"Number of Songs to Save"]) {
            //ScrobTrace(@"Removed an item from songList");
            [songList removeObject:[songList lastObject]];
        }
		
        [self updateMenu];
        [nowPlaying retain];
        [song release];
    }
    
mainTimerReleaseResult:

    [[NSNotificationCenter defaultCenter] postNotificationName:@"Now Playing"
        object:nowPlaying userInfo:nil];
    [nowPlaying release];
    
    [result release];
    //ScrobTrace(@"result released");
    } else {
        ScrobLog(SCROB_LOG_ERR, @"controlscript execution error: %@\n\tTrying again in %0.1lf seconds.",
            errInfo, 2.5);
        [self performSelector:@selector(mainTimer:) withObject:nil afterDelay:2.5];
    }
}
#endif

-(IBAction)playSong:(id)sender{
    SongData *song;
    NSString *scriptText;
    NSAppleScript *play;
    NSDictionary *errInfo;
    int index = [[sender menu] indexOfItem:sender];
	
    song = [songList objectAtIndex:index];
	
    scriptText = [NSString stringWithFormat:
        @"tell application \"iTunes\"\ntell playlist \"Library\"\nplay (every track whose database ID is %d)\nend tell\nend tell\n",
        [song iTunesDatabaseID]];
	
    play = [[NSAppleScript alloc] initWithSource:scriptText];
	
    (void)[play executeAndReturnError:&errInfo];
    
    [play release];
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
        [theMenu removeItemAtIndex:0];}

-(IBAction)openPrefs:(id)sender{
    // ScrobTrace(@"opening prefs");
    
    // Update iTunes playlists
    [self iTunesPlaylistUpdate:nil];
    
    if(!preferenceController)
        preferenceController=[[PreferenceController alloc] init];
	
    [NSApp activateIgnoringOtherApps:YES];
    [preferenceController showPreferencesWindow];
}

-(IBAction)openScrobblerHomepage:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"http://www.audioscrobbler.com"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)openiScrobblerDownloadPage:(id)sender {
	//NSLog(@"openiScrobblerDownloadPage");
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.audioscrobbler.com/download.php"]];
}

-(IBAction)openUserHomepage:(id)sender
{
    NSString *prefix = @"http://www.audioscrobbler.com/user/";
    NSURL *url = [NSURL URLWithString:[prefix stringByAppendingString:[prefs stringForKey:@"username"]]];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

-(IBAction)openStatistics:(id)sender
{
    [[StatisticsController sharedInstance] showWindow:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

-(IBAction)openTopLists:(id)sender
{
    [[TopListsController sharedInstance] showWindow:sender];
    [NSApp activateIgnoringOtherApps:YES];
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

- (NSString *)md5hash:(NSString *)input
{
	unsigned char *hash = MD5([input cString], [input cStringLength], NULL);
	int i;
    
	NSMutableString *hashString = [NSMutableString string];
	
    // Convert the binary hash into a string
    for (i = 0; i < MD5_DIGEST_LENGTH; i++) {
		//ScrobTrace(@"Appending %X to hashString (currently %@)", *hash, hashString);
		[hashString appendFormat:@"%02x", *hash++];
	}
	
    //ScrobTrace(@"Returning hash... %@ for input: %@", hashString, input);
    return hashString;
}

-(IBAction)cleanLog:(id)sender
{
    ScrobLogTruncate();
}

- (void)showBadCredentialsDialog
{	
	[NSApp activateIgnoringOtherApps:YES];
	
	// we should give them the option to ignore
	// these messages, and only update the menu icon... -- ECS 10/30/04
	int result = NSRunAlertPanel(NSLocalizedString(@"Authentication Failure", nil),
								NSLocalizedString(@"Audioscrobbler.com did not accept your username and password.  Please update your user credentials in the iScrobbler preferences.", nil),
								NSLocalizedString(@"Open iScrobbler Preferences", nil),
								NSLocalizedString(@"New Account", nil),
								nil); // NSLocalizedString(@"Ignore", nil)
	
	if (result == NSAlertDefaultReturn)
		[self openPrefs:self];
	else if (result == NSAlertAlternateReturn)
		[self openScrobblerHomepage:self];
	//else
	//	ignoreBadCredentials = YES;
}

- (void)showNewVersionExistsDialog
{
	if (!haveShownUpdateNowDialog) {
		[NSApp activateIgnoringOtherApps:YES];
		int result = NSRunAlertPanel(NSLocalizedString(@"New Plugin Available", nil),
									 NSLocalizedString(@"A new version (%@) of the iScrobbler iTunes plugin is now available.  It strongly suggested you update to the latest version.", nil),
									 NSLocalizedString(@"Open Download Page", nil),
									 NSLocalizedString(@"Ignore", nil),
									 nil); // NSLocalizedString(@"Ignore", nil)
		if (result == NSAlertDefaultReturn)
			[self openiScrobblerDownloadPage:self];
		
		haveShownUpdateNowDialog = YES;
	}
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

@end

@implementation SongData (iScrobblerControllerAdditions)

- (SongData*)initWithiTunesResultString:(NSString*)string
{
    NSArray *data;
    
    self = [self init];
    
    @try {
        data = [[NSArray alloc] initWithArray:[string componentsSeparatedByString:@"***"]];
    } @catch (NSException *exception) {
        data = nil;
    }
    ScrobLog(SCROB_LOG_TRACE, @"Song components from iTunes result: %@\n", (id)data ? (id)data : (id)string);
    
    if (10 != [data count]) {
bad_song_data:
        ScrobLog(SCROB_LOG_WARN, @"Bad song data received.\n");
        [data release];
        [self dealloc];
        return (nil);
    }
    
    @try {
#if 0
    [self setTrackIndex:[NSNumber numberWithFloat:[[data objectAtIndex:0]
        floatValue]]];
    [self setPlaylistIndex:[NSNumber numberWithFloat:[[data objectAtIndex:1]
        floatValue]]];
#endif
    [self setTitle:[data objectAtIndex:2]];
    [self setDuration:[NSNumber numberWithFloat:[[data objectAtIndex:3] floatValue]]];
    [self setPosition:[NSNumber numberWithFloat:[[data objectAtIndex:4] floatValue]]];
    [self setArtist:[data objectAtIndex:5]];
    [self setAlbum:[data objectAtIndex:6]];
    [self setPath:[data objectAtIndex:7]];
    NSDate *lastPlayedTime = [NSDate dateWithNaturalLanguageString:[data objectAtIndex:8]
        locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
    [self setLastPlayed:lastPlayedTime ? lastPlayedTime : [NSDate date]];
    [self setRating:[NSNumber numberWithInt:[[data objectAtIndex:9] intValue]]];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_WARN, @"Exception generated while processing song data.\n");
        goto bad_song_data;
    }
    
    [data release];
    
    [self setStartTime:[NSDate dateWithTimeIntervalSinceNow:-[[self position] doubleValue]]];
    [self setPostDate:[NSCalendarDate date]];
    [self setHasQueued:NO];
    //ScrobTrace(@"SongData allocated and filled");
    return (self);
}

- (SongData*)initWithiTunesPlayerInfo:(NSDictionary*)dict
{
    self = [self init];
    
    NSString *iname, *ialbum, *iartist, *ipath;
    NSURL *location = nil;
    NSNumber *irating, *iduration;
#ifdef notyet
    NSString *genre, *composer;
    NSNumber *year;
#endif
    NSTimeInterval durationInSeconds;
    
    iname = [dict objectForKey:@"Name"];
    ialbum = [dict objectForKey:@"Album"];
    iartist = [dict objectForKey:@"Artist"];
    ipath = [dict objectForKey:@"Location"];
    irating = [dict objectForKey:@"Rating"];
    iduration = [dict objectForKey:@"Total Time"];
    
    if (ipath)
        location = [NSURL URLWithString:ipath];
    
    if (!iname || !iartist || !iduration || (location && ![location isFileURL])) {
        if (!iname || !iartist || !iduration)
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

    [self setPostDate:[NSCalendarDate date]];
    [self setHasQueued:NO];
    
    return (self);
}

- (void)updateUsingSong:(SongData*)song
{
    [self setPosition:[song position]];
    [self setRating:[song rating]];
}

@end

@implementation NSMutableArray (iScrobblerContollerLifoAdditions)
- (void)push:(SongData*)song
{
    if ([self count])
        [self insertObject:song atIndex:0];
    else
        [self addObject:song];
}

- (void)pop
{
    unsigned idx = [self count] - 1;
    
    if (idx >= 0)
        [self removeObjectAtIndex:idx];
}

- (SongData*)peek
{
    unsigned idx = [self count] - 1;
    
    if (idx >= 0)
        return ([self objectAtIndex:idx]);
    
    return (nil);
}
@end

void ISDurationsFromTime(unsigned int time, unsigned int *days, unsigned int *hours,
    unsigned int *minutes, unsigned int *seconds)
{
    *days = time / 86400U;
    *hours = (time % 86400U) / 3600U;
    *minutes = ((time % 86400U) % 3600U) / 60U;
    *seconds = ((time % 86400U) % 3600U) % 60U;
}

#include "iScrobblerController+Private.m"
