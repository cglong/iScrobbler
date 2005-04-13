//
//  Created by Brian Bergstrand on 4/4/2005.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
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

#define IPOD_SYNC_VALUE_COUNT 10

#define ONE_DAY 86400.0
#define ONE_WEEK (ONE_DAY * 7.0)
- (void) restoreITunesLastPlayedTime
{
    NSTimeInterval ti = [[prefs stringForKey:@"iTunesLastPlayedTime"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDate *tr = [NSDate dateWithTimeIntervalSince1970:ti];

    if (!ti || ti > (now + [SongData songTimeFudge]) || ti < (now - (ONE_WEEK + ONE_DAY))) {
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
    
validate:
    for (i = 1; i < [sorted count]; ++i) {
        SongData *thisSong = [sorted objectAtIndex:i];
        SongData *lastSong = [sorted objectAtIndex:i-1];
        NSTimeInterval thisPost = [[thisSong postDate] timeIntervalSince1970];
        NSTimeInterval lastPost = [[lastSong postDate] timeIntervalSince1970];
        
        if ((lastPost + [[lastSong duration] doubleValue]) > thisPost) {
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
    
    if ([prefs boolForKey:@"Sync iPod"]) {
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
        
        // Just a little extra fudge time
        fudge = [iTunesLastPlayedTime timeIntervalSince1970]+[SongData songTimeFudge];
        now = [[NSDate date] timeIntervalSince1970];
        if (now > fudge) {
            [self setITunesLastPlayedTime:[NSDate dateWithTimeIntervalSince1970:fudge]];
        } else {
            [self setITunesLastPlayedTime:[NSDate date]];
        }
        
        ScrobLog(SCROB_LOG_VERBOSE, @"syncIPod: Requesting songs played after '%@'\n",
            iTunesLastPlayedTime);
        // Run script
        trackList = nil;
        @try {
            trackList = [iPodUpdateScript executeHandler:@"UpdateiPod" withParameters:
                playlist, iTunesLastPlayedTime, nil];
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
                return;
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
                return;
            }

            if (iTunesIsInactive != scriptMsgCode) {
                NSEnumerator *en = [trackList objectEnumerator];
                SongData *song;
                NSMutableArray *iqueue = [NSMutableArray arrayWithCapacity:[trackList count]];
                
                added = 0;
                while ((trackData = [en nextObject])) {
                    NSTimeInterval postDate;
                    song = [[SongData alloc] initWithiPodUpdateArray:trackData];
                    if (song) {
                        // Since this song was played "offline", we set the post date
                        // in the past 
                        postDate = [[song lastPlayed] timeIntervalSince1970] - [[song duration] doubleValue];
                        [song setPostDate:[NSCalendarDate dateWithTimeIntervalSince1970:postDate]];
                        // Make sure the song passes submission rules                            
                        [song setStartTime:[NSDate dateWithTimeIntervalSince1970:postDate]];
                        [song setPosition:[song duration]];
                        
                        [iqueue addObject:song];
                        [song release];
                    }
                }
                
                iqueue = [self validateIPodSync:iqueue];
                
                en = [iqueue objectEnumerator];
                while ((song = [en nextObject])) {
                    if (![[song postDate] isGreaterThan:iTunesLastPlayedTime]) {
                        ScrobLog(SCROB_LOG_WARN,
                            @"Anachronistic post date for song '%@'. Discarding -- possible date parse error.\n\t"
                            "Post Date: %@, Last Played: %@, Duration: %.0lf, iTunesLastPlayed: %@.\n",
                            [song brief], [song postDate], [song lastPlayed], [[song duration] doubleValue],
                            iTunesLastPlayedTime);
                        continue;
                    }
                    [song setType:trackTypeFile]; // Only type that's valid for iPod
                    ScrobLog(SCROB_LOG_VERBOSE, @"syncIPod: Queuing '%@' with postDate '%@'\n", [song brief], [song postDate]);
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
    }
}

// NSWorkSpace mount notifications
- (void)volumeDidMount:(NSNotification*)notification
{
    NSDictionary *info = [notification userInfo];
	NSString *mountPath = [info objectForKey:@"NSDevicePath"];
    NSString *iPodControlPath = [mountPath stringByAppendingPathComponent:@"iPod_Control"];
	
    ScrobTrace(@"Volume mounted: %@", info);
    
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:iPodControlPath isDirectory:&isDir] && isDir) {
        [self setValue:mountPath forKey:@"iPodMountPath"];
        [self setValue:[NSNumber numberWithBool:YES] forKey:@"isIPodMounted"];
    }
}

- (void)volumeDidUnmount:(NSNotification*)notification
{
    NSDictionary *info = [notification userInfo];
	NSString *mountPath = [info objectForKey:@"NSDevicePath"];
	
    ScrobTrace(@"Volume unmounted: %@.\n", info);
    
    if ([iPodMountPath isEqualToString:mountPath]) {
        [self syncIPod:nil]; // now that we're sure iTunes synced, we can sync...
        [self setValue:nil forKey:@"iPodMountPath"];
        [self setValue:[NSNumber numberWithBool:NO] forKey:@"isIPodMounted"];
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
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_WARN, @"Exception generated while processing iPodUpdate track data.\n");
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
