//
//  Created by Brian Bergstrand on 4/4/2005.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

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
        }
    }
    
    NSAppleEventDescriptor *executionResult = [iTunesPlaylistScript executeAndReturnError:nil];
    if(executionResult ) {
        NSArray *parsedResult = [[executionResult stringValue] componentsSeparatedByString:@"$$$"];
        NSEnumerator *en = [parsedResult objectEnumerator];
        NSString *playlist;
        NSMutableArray *names = [NSMutableArray arrayWithCapacity:[parsedResult count]];
        
        while ((playlist = [en nextObject])) {
            NSArray *properties = [playlist componentsSeparatedByString:@"***"];
            NSString *name = [properties objectAtIndex:0];
            
            if (name && [name length] > 0)
                [names addObject:name];
        }
        
        if ([names count]) {
            [self setValue:[names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]
                forKey:@"iTunesPlaylists"];
        }
    }
}

// =========== iPod Support ============

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

#define IPOD_UPDATE_SCRIPT_DATE_TOKEN @"Thursday, January 1, 1970 12:00:00 AM"
#define IPOD_UPDATE_SCRIPT_SONG_TOKEN @"$$$"
#define IPOD_UPDATE_SCRIPT_DEFAULT_PLAYLIST @"Recently Played"

- (IBAction)syncIPod:(id)sender
{
    ScrobTrace (@"syncIpod: called: script=%p, sync pref=%i\n", iPodUpdateScript, [prefs boolForKey:@"Sync iPod"]);
    
    if (iPodUpdateScript && [prefs boolForKey:@"Sync iPod"]) {
        // Copy the script
        NSMutableString *text = [iPodUpdateScript mutableCopy];
        NSAppleScript *iuscript;
        NSAppleEventDescriptor *result;
        NSDictionary *errInfo, *localeInfo;
        NSTimeInterval now, fudge;
        NSMutableString *formatString;
        unsigned int added;
        
        // Just a little extra fudge time
        fudge = [iTunesLastPlayedTime timeIntervalSince1970]+[SongData songTimeFudge];
        now = [[NSDate date] timeIntervalSince1970];
        if (now > fudge) {
            [self setITunesLastPlayedTime:[NSDate dateWithTimeIntervalSince1970:fudge]];
        } else {
            [self setITunesLastPlayedTime:[NSDate date]];
        }
        
        // AppleScript expects the date string formated according to the users's system settings
        localeInfo = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        formatString = [NSMutableString stringWithString:[localeInfo objectForKey:NSTimeDateFormatString]];
        // Remove the pesky human readable TZ specifier -- it causes AppleScript to fail for some locales
        [formatString replaceOccurrencesOfString:@" %Z" withString:@""
            options:0 range:NSMakeRange(0,[formatString length])];
        
        // Replace the date token with our last update
        [text replaceOccurrencesOfString:IPOD_UPDATE_SCRIPT_DATE_TOKEN
            withString:[iTunesLastPlayedTime descriptionWithCalendarFormat:formatString
                 timeZone:nil locale:localeInfo]
            options:0 range:NSMakeRange(0, [text length])];
        
        // Replace the default playlist with the user's choice
        [text replaceOccurrencesOfString:IPOD_UPDATE_SCRIPT_DEFAULT_PLAYLIST
            withString:[prefs stringForKey:@"iPod Submission Playlist"]
            options:0 range:NSMakeRange(0, [text length])];
        
        ScrobLog(SCROB_LOG_VERBOSE, @"syncIPod: Requesting songs played after '%@'\n",
            [iTunesLastPlayedTime descriptionWithCalendarFormat:formatString
                timeZone:nil locale:localeInfo]);
        // Run script
        iuscript = [[NSAppleScript alloc] initWithSource:text];
        if ((result = [iuscript executeAndReturnError:&errInfo])) {
            if (![[result stringValue] hasPrefix:@"INACTIVE"]) {
                NSArray *songs = [[result stringValue]
                    componentsSeparatedByString:IPOD_UPDATE_SCRIPT_SONG_TOKEN];
                NSEnumerator *en = [songs objectEnumerator];
                NSString *data;
                SongData *song;
                NSMutableArray *iqueue = [NSMutableArray array];
                
                if ([[result stringValue] hasPrefix:@"ERROR"]) {
                    NSString *errmsg, *errnum;
                    @try {
                    errmsg = [songs objectAtIndex:1];
                    errnum = [songs objectAtIndex:2];
                    } @catch (NSException *exception) {
                    errmsg = errnum = @"UNKNOWN";
                    }
                    // Display dialog instead of logging?
                    ScrobLog(SCROB_LOG_ERR, @"syncIPod: iPodUpdateScript returned error: \"%@\" (%@)\n",
                        errmsg, errnum);
                    goto sync_ipod_script_release;
                }
                
                added = 0;
                while ((data = [en nextObject]) && [data length] > 0) {
                    NSTimeInterval postDate;
                    song = [[SongData alloc] initWithiTunesResultString:data];
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
                    [song setiTunesDatabaseID:-1]; // Placeholder val
                    ScrobLog(SCROB_LOG_VERBOSE, @"syncIPod: Queuing '%@' with postDate '%@'\n", [song brief], [song postDate]);
                    (void)[[QueueManager sharedInstance] queueSong:song submit:NO];
                    ++added;
                }
                
                [self setITunesLastPlayedTime:[NSDate date]];
                if (added > 0) {
                    [[QueueManager sharedInstance] submit];
                }
            }
        } else if (!result) {
            // Script error
            ScrobLog(SCROB_LOG_ERR, @"iPodUpdateScript execution error: %@\n", errInfo);
        }
        
sync_ipod_script_release:
        [iuscript release];
        [text release];
    } else {
        ScrobLog(SCROB_LOG_CRIT, @"iPodUpdateScript missing\n");
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
