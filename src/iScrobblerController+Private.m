//
//  Created by Brian Bergstrand on 4/4/2005.
//  Copyright 2005-2007 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  iscrobbler/res/gpl.txt
//

@interface SongData (iScrobblerControllerPrivateAdditions)
    - (SongData*)initWithiPodUpdateArray:(NSArray*)data;
@end

@implementation iScrobblerController (iScrobblerControllerPrivate)

- (void)iTunesPlaylistUpdate:(NSTimer*)timer
{
    static NSAppleScript *iTunesPlaylistScript = nil;
    
    if (!iTunesPlaylistScript) {
        NSURL *file = [NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                    stringByAppendingPathComponent:@"Scripts/iTunesGetPlaylists.scpt"]];
        iTunesPlaylistScript = [[NSAppleScript alloc] initWithContentsOfURL:file error:nil];
        if (!iTunesPlaylistScript) {
            ScrobLog(SCROB_LOG_CRIT, @"Could not load iTunesGetPlaylists.scpt!\n");
            [self showApplicationIsDamagedDialog];
            return;
        }
    }
    
    NSDictionary *errInfo = nil;
    NSAppleEventDescriptor *executionResult = [iTunesPlaylistScript executeAndReturnError:&errInfo];
    if (executionResult) {
        NSArray *parsedResult;
        NSEnumerator *en;
        
        @try {
            parsedResult = [executionResult objCObjectValue];
            en = [parsedResult objectEnumerator];
        } @catch (NSException *exception) {
            ScrobLog(SCROB_LOG_ERR, @"GetPlaylists script invalid result: parsing exception %@\n.", exception);
            [self setValue:[NSArray arrayWithObject:@"Recently Played"] forKey:@"iTunesPlaylists"];
            return;
        }
        
        NSString *playlist;
        NSMutableArray *names = [NSMutableArray arrayWithCapacity:[parsedResult count]];
        while ((playlist = [en nextObject])) {
            if ([playlist length] > 0)
                [names addObject:playlist];
        }
        
        if ([names count]) {
            [self setValue:[names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]
                forKey:@"iTunesPlaylists"];
        }
    }
}

// =========== NSAppleEventDescriptor Image conversion handler ===========

- (NSImage*)aeImageConversionHandler:(NSAppleEventDescriptor*)aeDesc
{
    NSImage *image = [[NSImage alloc] initWithData:[aeDesc data]];
    return ([image autorelease]);
}

// =========== iPod Support ============

#define IPOD_SYNC_VALUE_COUNT 14

#define ONE_DAY 86400.0
#define ONE_WEEK (ONE_DAY * 7.0)
- (void) restoreITunesLastPlayedTime
{
    NSTimeInterval ti = [[prefs stringForKey:@"iTunesLastPlayedTime"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDate *tr = [NSDate dateWithTimeIntervalSince1970:ti];

    if (!ti || ti > (now + [SongData songTimeFudge]) || ti < (now - (ONE_WEEK * 2))) {
        ScrobLog(SCROB_LOG_WARN, @"Discarding invalid iTunesLastPlayedTime value (ti=%.0lf, now=%.0lf).\n",
            ti, now);
        tr = [NSDate date];
    }
    
    [self setITunesLastPlayedTime:tr];
}

- (void) setITunesLastPlayedTime:(NSDate*)date
{
    [date retain];
    [iTunesLastPlayedTime release];
    iTunesLastPlayedTime = date;
    // Update prefs
    [prefs setObject:[NSString stringWithFormat:@"%.2lf", [iTunesLastPlayedTime timeIntervalSince1970]]
        forKey:@"iTunesLastPlayedTime"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)fixIPodShuffleTimes:(NSArray*)songs withRequestDate:(NSDate*)requestEpoch
{
    NSArray *sorted = [songs sortedArrayUsingSelector:@selector(compareSongLastPlayedDate:)];
    int i;
    unsigned count = [sorted count];
    // Shuffle plays will have a last played equal to the time the Shuffle was sync'd
    NSTimeInterval shuffleEpoch = [[NSDate date] timeIntervalSince1970] - 1.0;
    SongData *song;
    for (i = 1; i < count; ++i) {
        song = [sorted objectAtIndex:i-1];
        SongData *nextSong = [sorted objectAtIndex:i];
        if (NSOrderedSame != [song compareSongLastPlayedDate:nextSong]) {
            requestEpoch = [song postDate];
            continue;
        }
        
        NSDate *shuffleBegin = [song lastPlayed];
        shuffleEpoch = [shuffleBegin timeIntervalSince1970];
        ScrobLog(SCROB_LOG_TRACE, @"Shuffle play block begins at %@", shuffleBegin);
        for (i -= 1; i < count; ++i) {
            song = [sorted objectAtIndex:i];
            if (NSOrderedSame != [[song lastPlayed] compare:shuffleBegin]) {
                i = count;
                break;
            }
            [song setLastPlayed:[NSDate dateWithTimeIntervalSince1970:shuffleEpoch]];
            shuffleEpoch -= [[song duration] doubleValue];
            [song setPostDate:[NSCalendarDate dateWithTimeIntervalSince1970:shuffleEpoch]];
            // Make sure the song passes submission rules                            
            [song setStartTime:[NSDate dateWithTimeIntervalSince1970:shuffleEpoch]];
            [song setPosition:[song duration]];
        }
    }
    
    if ([[NSDate dateWithTimeIntervalSince1970:shuffleEpoch] isLessThan:requestEpoch])
        ScrobLog(SCROB_LOG_WARN, @"All iPod Shuffle tracks could not be adjusted to fit into the time period since "
            @"the last submission. Some tracks may not be submitted or may be rejected by the last.fm servers.");
}

/*
Validate all of the post dates. We do this, because there seems
to be a iTunes bug that royally screws up last played times during daylight
savings changes.

Scenario: Unplug iPod on 10/30, play a lot of songs, then sync the next day (10/31 - after 0200)
and some of the last played dates will be very bad.
*/
- (NSMutableArray*)validateIPodSync:(NSArray*)songs
{
    NSMutableArray *sorted = [[songs sortedArrayUsingSelector:@selector(compareSongPostDate:)] mutableCopy];
    int i;
    unsigned count;
    
validate:
    count = [sorted count];
    for (i = 1; i < count; ++i) {
        SongData *thisSong = [sorted objectAtIndex:i];
        SongData *lastSong = [sorted objectAtIndex:i-1];
        NSTimeInterval thisPost = [[thisSong postDate] timeIntervalSince1970];
        NSTimeInterval lastPost = [[lastSong postDate] timeIntervalSince1970];
        
        // 2 seconds of fudge.
        if ((lastPost + ([[lastSong duration] doubleValue] - 2.0)) > thisPost) {
            ScrobLog(SCROB_LOG_WARN, @"iPodSync: Discarding '%@' because of invalid play time.\n\t'%@' = Start: %@, Duration: %@"
                "\n\t'%@' = Start: %@, Duration: %@\n", [thisSong brief], [lastSong brief], [lastSong postDate], [lastSong duration],
                [thisSong brief], [thisSong postDate], [thisSong duration]);
            [sorted removeObjectAtIndex:i];
            goto validate;
        }
    }
    
    return ([sorted autorelease]);
}

- (IBAction)syncIPod:(id)sender
{
    static NSAppleScript *iPodUpdateScript = nil;
    ScrobTrace (@"syncIpod: called: script=%p, sync pref=%i\n", iPodUpdateScript, [prefs boolForKey:@"Sync iPod"]);
    
    if ([prefs boolForKey:@"Sync iPod"] && !submissionsDisabled) {
        NSArray *trackList, *trackData;
        NSString *errInfo = nil, *playlist;
        NSTimeInterval now, fudge;
        unsigned int added;
        
        // Get our iPod update script
        if (!iPodUpdateScript) {
            #define path playlist
            path = [[[NSBundle mainBundle] resourcePath]
                        stringByAppendingPathComponent:@"Scripts/iPodUpdate.scpt"];
            NSURL *url = [NSURL fileURLWithPath:path];
            iPodUpdateScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:nil];
            if (!iPodUpdateScript) {
                ScrobLog(SCROB_LOG_CRIT, @"Failed to load iPodUpdateScript!\n");
                return;
            }
            #undef path
        }
        
        if (!(playlist = [prefs stringForKey:@"iPod Submission Playlist"]) || ![playlist length]) {
            ScrobLog(SCROB_LOG_ERR, @"iPod playlist not set, aborting sync.");
            return;
        }
        
        [[NSNotificationCenter defaultCenter]  postNotificationName:IPOD_SYNC_BEGIN
            object:nil
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:iPodMountPath, IPOD_SYNC_KEY_PATH,
                iPodIcon, IPOD_SYNC_KEY_ICON, nil]];
        
        // Just a little extra fudge time
        fudge = [iTunesLastPlayedTime timeIntervalSince1970]+[SongData songTimeFudge];
        now = [[NSDate date] timeIntervalSince1970];
        if (now > fudge) {
            [self setITunesLastPlayedTime:[NSDate dateWithTimeIntervalSince1970:fudge]];
        } else {
            [self setITunesLastPlayedTime:[NSDate date]];
        }
        // There's a bug here: if the user pauses submissions, then turns them back on
        // and plugs in the iPod, the last q'd/sub'd date will be used and most/all
        // of the tracks played during the pause will be picked up (in auto-sync mode).
        // I really can't think of a way to catch this case w/o all kinds of hackery
        // in the Q/Protocol mgr's, so I'm just going to let it stand.
        SongData *lastSubmission = [[ProtocolManager sharedInstance] lastSongSubmitted];
        NSDate *requestDate, *iPodMountEpoch;
        iPodMountEpoch = [[[iPodMounts allValues] sortedArrayUsingSelector:@selector(compare:)] lastObject];
        if (lastSubmission) {
            requestDate = [NSDate dateWithTimeIntervalSince1970:
                [[lastSubmission startTime] timeIntervalSince1970] +
                [[lastSubmission duration] doubleValue]];
            // If the song was paused the following will be true.
            if ([[lastSubmission lastPlayed] isGreaterThan:requestDate])
                requestDate = [lastSubmission lastPlayed];
            
            requestDate = [NSDate dateWithTimeIntervalSince1970:
                [requestDate timeIntervalSince1970] + [SongData songTimeFudge]];
        } else
            requestDate = iTunesLastPlayedTime;
        
        ScrobLog(SCROB_LOG_VERBOSE, @"syncIPod: Requesting songs played after '%@'\n",
            requestDate);
        // Run script
        trackList = nil;
        @try {
            trackList = [iPodUpdateScript executeHandler:@"UpdateiPod" withParameters:
                playlist, requestDate, nil];
        } @catch (NSException *exception) {
            errInfo = [exception description];
        }
        
        enum {
            iTunesIsInactive = -1,
            iTunesError = -2,
        };
        if (trackList) {
            int scriptMsgCode;
            @try {
                trackData = [trackList objectAtIndex:0];
                scriptMsgCode = [[trackData objectAtIndex:0] intValue];
            } @catch (NSException *exception) {
                ScrobLog(SCROB_LOG_ERR, @"iPodUpdateScript script invalid result: parsing exception %@\n.", exception);
                goto sync_exit_with_note;
            }
            
            if (iTunesError == scriptMsgCode) {
                NSString *errmsg;
                NSNumber *errnum;
                @try {
                    errmsg = [trackData objectAtIndex:1];
                    errnum = [trackData objectAtIndex:2];
                } @catch (NSException *exception) {
                    errmsg = @"UNKNOWN";
                    errnum = [NSNumber numberWithInt:-1];
                }
                // Display dialog instead of logging?
                ScrobLog(SCROB_LOG_ERR, @"syncIPod: iPodUpdateScript returned error: \"%@\" (%@)\n",
                    errmsg, errnum);
                goto sync_exit_with_note;
            }

            if (iTunesIsInactive != scriptMsgCode) {
                NSEnumerator *en = [trackList objectEnumerator];
                SongData *song;
                NSMutableArray *iqueue = [NSMutableArray arrayWithCapacity:[trackList count]];
                NSDate *currentDate = [NSDate date];
                
                added = 0;
                while ((trackData = [en nextObject])) {
                    NSTimeInterval postDate;
                    song = [[SongData alloc] initWithiPodUpdateArray:trackData];
                    if (song) {
                        if ([song ignore]) {
                            ScrobLog(SCROB_LOG_VERBOSE, @"Song '%@' filtered.\n", [song brief]);
                            [song release];
                            continue;
                        }
                        // Since this song was played "offline", we set the post date
                        // in the past 
                        postDate = [[song lastPlayed] timeIntervalSince1970] - [[song duration] doubleValue];
                        [song setPostDate:[NSCalendarDate dateWithTimeIntervalSince1970:postDate]];
                        // Make sure the song passes submission rules                            
                        [song setStartTime:[NSDate dateWithTimeIntervalSince1970:postDate]];
                        [song setPosition:[song duration]];
                        
                        if ([[song postDate] isGreaterThan:currentDate]) {
                            ScrobLog(SCROB_LOG_WARN,
                                @"Discarding '%@': future post date.\n\t"
                                "Current Date: %@, Post Date: %@, requestDate: %@.\n",
                                [song brief], currentDate, [song postDate], requestDate);
                            [song release];
                            continue;
                        }
                        
                        [iqueue addObject:song];
                        [song release];
                    }
                }
                
                [self fixIPodShuffleTimes:iqueue withRequestDate:requestDate];
                iqueue = [self validateIPodSync:iqueue];
                
                en = [iqueue objectEnumerator];
                while ((song = [en nextObject])) {
                    if (![[song postDate] isGreaterThan:requestDate]) {
                        ScrobLog(SCROB_LOG_WARN,
                            @"Discarding '%@': anachronistic post date.\n\t"
                            "Post Date: %@, Last Played: %@, Duration: %.0lf, requestDate: %@.\n",
                            [song brief], [song postDate], [song lastPlayed], [[song duration] doubleValue],
                            requestDate);
                        continue;
                    }
                    if ([[song lastPlayed] isGreaterThan:iPodMountEpoch]) {
                        ScrobLog(SCROB_LOG_INFO,
                            @"Discarding '%@' in the assumption that it was played after an iPod sync began.\n\t"
                            "Post Date: %@, Last Played: %@, Duration: %.0lf, requestDate: %@, iPodMountEpoch: %@.\n",
                            [song brief], [song postDate], [song lastPlayed], [[song duration] doubleValue],
                            requestDate, iPodMountEpoch);
                        continue;
                    }
                    [song setType:trackTypeFile]; // Only type that's valid for iPod
                    [song setReconstituted:YES];
                    ScrobLog(SCROB_LOG_TRACE, @"syncIPod: Queuing '%@' with postDate '%@'\n", [song brief], [song postDate]);
                    (void)[[QueueManager sharedInstance] queueSong:song submit:NO];
                    ++added;
                }
                
                [self setITunesLastPlayedTime:[NSDate date]];
                if (added > 0) {
                    [[QueueManager sharedInstance] submit];
                }
            }
        } else {
            // Script error
            ScrobLog(SCROB_LOG_ERR, @"iPodUpdateScript execution error: %@\n", errInfo);
        }

sync_exit_with_note:
        [[NSNotificationCenter defaultCenter]  postNotificationName:IPOD_SYNC_END
            object:nil
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:iPodMountPath, IPOD_SYNC_KEY_PATH, nil]];
        
    } // if ("Sync iPod")
}

// NSWorkSpace mount notifications
- (void)volumeDidMount:(NSNotification*)notification
{
    NSDictionary *info = [notification userInfo];
	NSString *mountPath = [info objectForKey:@"NSDevicePath"];
    NSString *iPodControlPath = [mountPath stringByAppendingPathComponent:@"iPod_Control"];
	
    ScrobLog(SCROB_LOG_TRACE, @"Volume mounted: %@", info);
    
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:iPodControlPath isDirectory:&isDir] && isDir) {
        [self setValue:mountPath forKey:@"iPodMountPath"];
        if (!iPodMounts)
            iPodMounts = [[NSMutableDictionary alloc] init];
        [iPodMounts setObject:[NSDate date] forKey:mountPath];
        
        ISASSERT(iPodIcon == nil, "iPodIcon exists!");
        if ([[NSFileManager defaultManager] fileExistsAtPath:
            [mountPath stringByAppendingPathComponent:@".VolumeIcon.icns"]]) {
            iPodIcon = [[NSImage alloc] initWithContentsOfFile:
                [mountPath stringByAppendingPathComponent:@".VolumeIcon.icns"]];
            [iPodIcon setName:IPOD_ICON_NAME];
        }
        ++iPodMountCount;
        ISASSERT(iPodMountCount > -1, "negative ipod count!");
        [self setValue:[NSNumber numberWithBool:YES] forKey:@"isIPodMounted"];
    }
}

- (void)volumeDidUnmount:(NSNotification*)notification
{
    NSDictionary *info = [notification userInfo];
	NSString *mountPath = [info objectForKey:@"NSDevicePath"];
	
    ScrobLog(SCROB_LOG_TRACE, @"Volume unmounted: %@.\n", info);
    
    if ([iPodMounts objectForKey:mountPath]) {
        [self syncIPod:nil]; // now that we're sure iTunes synced, we can sync...
        [self setValue:nil forKey:@"iPodMountPath"];
        [iPodIcon release];
        iPodIcon = nil;
        
        --iPodMountCount;
        ISASSERT(iPodMountCount > -1, "negative ipod count!");
        [iPodMounts removeObjectForKey:mountPath];
        if (0 == iPodMountCount) {
            [self setValue:[NSNumber numberWithBool:NO] forKey:@"isIPodMounted"];
            [[QueueManager sharedInstance] submit];
        }
    }
}

@end

@implementation SongData (iScrobblerControllerPrivateAdditions)

- (SongData*)initWithiPodUpdateArray:(NSArray*)data
{
    self = [self init];
    ScrobLog(SCROB_LOG_TRACE, @"Song components from iPodUpdate result: %@\n", data);
    
    if (IPOD_SYNC_VALUE_COUNT != [data count]) {
bad_song_data:
        ScrobLog(SCROB_LOG_WARN, @"Bad track data received.\n");
        [self dealloc];
        return (nil);
    }
    
    @try {
        [self setiTunesDatabaseID:[[data objectAtIndex:0] intValue]];
        [self setPlaylistID:[data objectAtIndex:1]];
        [self setTitle:[data objectAtIndex:2]];
        [self setDuration:[data objectAtIndex:3]];
        [self setPosition:[data objectAtIndex:4]];
        [self setArtist:[data objectAtIndex:5]];
        [self setPath:[data objectAtIndex:6]];
        [self setAlbum:[data objectAtIndex:7]];
        NSDate *lastPlayedTime = [data objectAtIndex:8];
        [self setLastPlayed:lastPlayedTime ? lastPlayedTime : [NSDate date]];
        [self setRating:[data objectAtIndex:9]];
        [self setGenre:[data objectAtIndex:10]];
        NSNumber *trackPodcast = [data objectAtIndex:11];
        if (trackPodcast && [trackPodcast intValue] > 0)
            [self setIsPodcast:YES];
        NSString *commentArg = [data objectAtIndex:12];
        if (commentArg)
            [self setComment:commentArg];
        NSNumber *trackNum = [data objectAtIndex:13];
        if (trackNum)
            [self setTrackNumber:trackNum];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_WARN, @"Exception generated while processing iPodUpdate track data: %@\n", exception);
        goto bad_song_data;
    }    
    [self setStartTime:[NSDate dateWithTimeIntervalSinceNow:-[[self position] doubleValue]]];
    [self setPostDate:[NSCalendarDate date]];
    [self setHasQueued:NO];
    //ScrobTrace(@"SongData allocated and filled");
    return (self);
}

@end

@implementation iScrobblerController (GrowlAdditions)

- (NSDictionary *) registrationDictionaryForGrowl
{
    NSArray *notifications = [NSArray arrayWithObject:IS_GROWL_NOTIFICATION_TRACK_CHANGE];
    return ( [NSDictionary dictionaryWithObjectsAndKeys:
        notifications, GROWL_NOTIFICATIONS_ALL,
        notifications, GROWL_NOTIFICATIONS_DEFAULT,
        nil] );
}

@end
