//
//  iPodController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/8/08.
//  Copyright 2004-2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <IOKit/IOMessage.h>
#import <IOKit/storage/IOMedia.h>

#import "iPodController.h"
#import "iScrobblerController.h"
#import "SongData.h"
#import "QueueManager.h"
#import "ProtocolManager.h"
#import "ISiTunesLibrary.h"

#ifdef IS_SCRIPT_PROXY
#import "ISProxyProtocol.h"
#else
#import "MobileDeviceSupport.h"
#endif

static iPodController *sharedController = nil;

// this is used to trigger a copy of the iTunes library
#define ISCOPY_OF_ITUNES_LIB [@"~/Library/Caches/org.bergstrand.iscrobbler.iTunesLibCopy.xml" stringByExpandingTildeInPath]
static void IOMediaAddedCallback(void *refcon, io_iterator_t iter);

@interface iPodController (Private)
- (void)volumeDidMount:(NSNotification*)notification;
- (void)volumeDidUnmount:(NSNotification*)notification;
- (void)presentiPodWarning;
@end

@interface SongData (iScrobblerControllerPrivateAdditions)
- (SongData*)initWithiPodUpdateArray:(NSArray*)data;
@end

@implementation iPodController

+ (iPodController*)sharedInstance
{
    return (sharedController ? sharedController : (sharedController = [[iPodController alloc] init]));
}

- (IBAction)synciPod:(id)sender
{
    NSString *path = [self valueForKey:@"iPodMountPath"];
    ISASSERT(path != nil, "bad iPod path!");
    
    ScrobLog(SCROB_LOG_TRACE, @"User initiated iPod sync for: %@", path);
    
    // Fake an unmount event for the current mount path. When the volume is actually unmounted,
    // volumeDidUnmount: won't find it in the iPodMounts dict anymore and we won't try to sync again.
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:path, @"NSDevicePath", nil];
    NSNotification *note = [NSNotification notificationWithName:NSWorkspaceDidUnmountNotification
        object:[NSWorkspace sharedWorkspace] userInfo:d];
    [self volumeDidUnmount:note];
}

- (BOOL)isiPodMounted
{
    return (iPodMountCount > 0);
}

// Private

- (id)init
{
    self = [super init];
    
    // Register for mounts and unmounts
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
        selector:@selector(volumeDidMount:) name:NSWorkspaceDidMountNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
        selector:@selector(volumeDidUnmount:) name:NSWorkspaceDidUnmountNotification object:nil];
    
    // this is used to trigger copying of the iTunes library for multiple iPod play detection
    static BOOL registeredForIOMediaEvents = NO;
    if (0 == registeredForIOMediaEvents) {
        IONotificationPortRef portRef = IONotificationPortCreate(kIOMasterPortDefault);
        CFRunLoopSourceRef source;
        io_iterator_t medidAddedNotification;
        // Add matching for iPhone/Touch (IOUSBDevice) ?
        kern_return_t kr = IOServiceAddMatchingNotification (portRef, kIOMatchedNotification,
            IOServiceMatching(kIOMediaClass), IOMediaAddedCallback, NULL, &medidAddedNotification);
        if (0 == kr && 0 != medidAddedNotification) {
            registeredForIOMediaEvents = YES;
            source = IONotificationPortGetRunLoopSource(portRef);
            CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], source, kCFRunLoopCommonModes);
            // prime the queue, necessary to arm the notification
            io_object_t iomedia;
            while ((iomedia = IOIteratorNext(medidAddedNotification)))
                IOObjectRelease(iomedia);
        } else
            ScrobLog(SCROB_LOG_ERR, @"Failed to register for system media addition events.");
    }
    
    iPodMounts = [[NSMutableDictionary alloc] init];
    
    // iPhone/iPod Touch support
    NSString *framework = [[NSUserDefaults standardUserDefaults] stringForKey:@"Apple MobileDevice Framework"];
    if ([framework UTF8String]) {
        // subscribe
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(amdsDidFail:) name:@"org.bergstrand.amds.intializeDidFail" object:nil];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(amdsDidFinishSync:) name:@"org.bergstrand.amds.syncDidFinish" object:nil];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(amdsDidStartSync:) name:@"org.bergstrand.amds.syncDidStart" object:nil];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(amdsDidConnect:) name:@"org.bergstrand.amds.connect" object:nil];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(amdsDidDisconnect:) name:@"org.bergstrand.amds.disconnect" object:nil];
    
        #ifdef IS_SCRIPT_PROXY
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(proxyDidStart:) name:@"proxyStart" object:nil];
        #else
        (void)IntializeMobileDeviceSupport([framework UTF8String], NULL);
        #endif
    }
    
    return (self);
}

- (void)dealloc
{
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [super dealloc];
}

// =========== iPod Core ============

#define IPOD_SYNC_VALUE_COUNT 17

- (BOOL)setSongPlayTimes:(SongData*)song findingTimeinGaps:(NSMutableArray*)playGaps
{
    NSEnumerator *en = [playGaps objectEnumerator];
    NSMutableDictionary *entry;
    while ((entry = [en nextObject])) {
        if ([[entry objectForKey:@"gap"] isGreaterThanOrEqualTo:[song duration]])
            break;
    }
    
    if (entry) {
        NSTimeInterval secStart, gap, duration;
        secStart = [[entry objectForKey:@"start"] doubleValue];
        gap = [[entry objectForKey:@"gap"] doubleValue];
        duration = [[song duration] doubleValue];
        
        // update the song
        [song setPostDate:[NSDate dateWithTimeIntervalSince1970:secStart]];
        secStart += duration;
        [song setLastPlayed:[NSDate dateWithTimeIntervalSince1970:secStart]];
        
        // update the entry
        if ((gap -= duration) > [SongData songTimeFudge]) {
            [entry setObject:[NSNumber numberWithDouble:gap] forKey:@"gap"];
            [entry setObject:[NSNumber numberWithDouble:secStart] forKey:@"start"];
        } else
            [playGaps removeObject:entry];
        
        if ([playGaps count] > 1) {
            [playGaps sortUsingDescriptors:
                [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"gap" ascending:YES] autorelease]]];
        }
        
        return (YES);
    }
    
    return (NO);
}

- (NSMutableArray*)findInitialFreeTimeGaps:(NSArray*)sortedByLastPlayed /*songs*/
{
    NSMutableArray *entries = [NSMutableArray array];
    NSMutableDictionary *entry;
    NSUInteger count = [sortedByLastPlayed count] - 1;
    NSTimeInterval secStart, secEnd;
    NSTimeInterval gap;
    for (NSUInteger i = 0; i < count; ++i) {
        secStart = [[[sortedByLastPlayed objectAtIndex:i] lastPlayed] timeIntervalSince1970];
        secEnd = [[[sortedByLastPlayed objectAtIndex:i+1] startTime] timeIntervalSince1970];
        gap = floor(secEnd - secStart);
        if (gap > [SongData songTimeFudge]) {
            entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithDouble:gap], @"gap",
                [NSNumber numberWithDouble:secStart], @"start",
                [NSNumber numberWithDouble:secStart], @"end",
                nil];
            [entries addObject:entry];
        }
    }
    
    if ([entries count] > 1) {
        [entries sortUsingDescriptors:
            [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"gap" ascending:YES] autorelease]]];
    }
    
    return (entries);
}

- (NSMutableArray*)detectAndSynthesizeMultiplePlays:(NSArray*)songs iTunesTracks:(NSDictionary*)iTunesTracks
    iPodMountDate:(NSDate*)mountEpoch requestDate:(NSDate*)requestDate
{
    NSMutableArray *extras = [NSMutableArray array];
    NSArray *sortedByLastPlayed = [songs sortedArrayUsingSelector:@selector(compareSongLastPlayedDate:)];
    NSArray *sortedByDuration = [songs sortedArrayUsingDescriptors:
        [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"duration" ascending:NO] autorelease]]];
    
    // The easiest option is to use the interval between the last iPod play and the iPod mount, but that may not be possible
    NSTimeInterval postiPodEpochSince1970 = [[[sortedByLastPlayed lastObject] lastPlayed] timeIntervalSince1970] + 1.0;
    NSTimeInterval postiPodFreeSeconds = floor([mountEpoch timeIntervalSince1970] - postiPodEpochSince1970);
    if (postiPodFreeSeconds < 0.0)
        postiPodFreeSeconds = 0.0; // something is probably off with the iPod clock
    // or the interval between the last queued song and the first iPod play
    NSTimeInterval preiPodEpochSince1970 = [requestDate timeIntervalSince1970] + 1.0;
    NSTimeInterval preiPodFreeSeconds = [[[sortedByLastPlayed objectAtIndex:0] postDate] timeIntervalSince1970] - 1.0;
    preiPodFreeSeconds = floor(preiPodFreeSeconds - preiPodEpochSince1970);
    if (preiPodFreeSeconds < 0.0)
        preiPodFreeSeconds = 0.0; // something is seriously wrong
    
    // And our fallback of play gaps in between the songs
    NSMutableArray *playGaps = [self findInitialFreeTimeGaps:sortedByLastPlayed];
    
    NSArray *allTracks = [iTunesTracks allValues]; // we pre-flight this here so we don't have to do it every time in the loop
    NSNumber *dbCount;
    NSEnumerator *en = [sortedByDuration objectEnumerator];
    SongData *song, *newSong;
    while ((song = [en nextObject])) {
        // XXX songs are keyed on the 'database ID' in the XML file, but these can change at any time
        // even between different iTunes run instances. What a mess.
        NSString *songUUID = [song playerUUID];
        NSNumber *trackKey = [NSString stringWithFormat:@"%llu", [song iTunesDatabaseID]];
        NSDictionary *track = [iTunesTracks objectForKey:trackKey];
        if (!track || NSOrderedSame != [songUUID caseInsensitiveCompare:[track objectForKey:@"Persistent ID"]]) {
            // Sometimes the id's only change by 1...
            trackKey = [NSString stringWithFormat:@"%llu", [song iTunesDatabaseID] + 1];
            track = [iTunesTracks objectForKey:trackKey];
            if (!track || NSOrderedSame != [songUUID caseInsensitiveCompare:[track objectForKey:@"Persistent ID"]]) {
                trackKey = [NSString stringWithFormat:@"%llu", [song iTunesDatabaseID] - 1];
                track = [iTunesTracks objectForKey:trackKey];
                if (!track || NSOrderedSame != [songUUID caseInsensitiveCompare:[track objectForKey:@"Persistent ID"]]) {
                    // OK, fall back to an expensive array search, we could use NSPredicate, but it's so SLOW
                    NSEnumerator *trackEN = [allTracks objectEnumerator];
                    while ((track = [trackEN nextObject])) {
                        if (NSOrderedSame == [songUUID caseInsensitiveCompare:[track objectForKey:@"Persistent ID"]])
                            break;
                    }
                    
                }
            }
        }
        
        if (!(dbCount = [track objectForKey:@"Play Count"])) {
            ScrobLog(SCROB_LOG_ERR, @"Failed to retrieve play count for '%@' from iTunes library using db id '%@' and persitent id '%@'.",
                [song brief], trackKey, songUUID);
            continue;
        }
        
        int extraPlays;
        // we subtract one from the current playCount to account for the instance of the song retrieved from iTunes
        if ((extraPlays = (([[song playCount] unsignedIntValue] - 1) - [dbCount unsignedIntValue])) > 0) {
            ScrobLog(SCROB_LOG_TRACE, @"Found %d iPod plays for '%@', attempting to synthesize extra plays...", extraPlays+1, [song brief]);
            double duration = [[song duration] doubleValue];
            for (int i = 0; i < extraPlays; ++i) {
                newSong = [song copy];
                if (postiPodFreeSeconds >= duration) {
                    postiPodFreeSeconds -= duration;
                    [newSong setPostDate:[NSDate dateWithTimeIntervalSince1970:postiPodEpochSince1970]];
                    postiPodEpochSince1970 += duration;
                    [newSong setLastPlayed:[NSDate dateWithTimeIntervalSince1970:postiPodEpochSince1970]];
                } else if (preiPodFreeSeconds >= duration) {
                    preiPodFreeSeconds -= duration;
                    [newSong setPostDate:[NSDate dateWithTimeIntervalSince1970:preiPodEpochSince1970]];
                    preiPodEpochSince1970 += duration;
                    [newSong setLastPlayed:[NSDate dateWithTimeIntervalSince1970:preiPodEpochSince1970]];
                }
                // this is the hard part, we have to fit the extra play into the free space between the times iTunes gave us
                else if (![self setSongPlayTimes:newSong findingTimeinGaps:playGaps]) {
                    ScrobLog(SCROB_LOG_ERR, @"Unable to synthesize play time for song '%@' with duration %.0f", [song brief], duration);
                    ScrobLog(SCROB_LOG_TRACE, @"preiPodFreeSeconds: %.0f, postiPodFreeSeconds: %.0f, playGaps:%@", preiPodFreeSeconds, postiPodFreeSeconds, playGaps);
                    [newSong release];
                    if (0 == [playGaps count])
                        break;
                    else
                        continue;
                }
                
                [newSong setPosition:[song duration]];
                [newSong setStartTime:[newSong postDate]];
                [extras addObject:newSong];
                [newSong release];
            }
        }
    }
    
    return (extras);
}

- (void)fixIPodShuffleTimes:(NSArray*)songs withRequestDate:(NSDate*)requestEpoch withiPodMountDate:(NSDate*)mountEpoch
{
    NSArray *sorted = [songs sortedArrayUsingSelector:@selector(compareSongLastPlayedDate:)];
    NSUInteger i;
    NSUInteger count = [sorted count];
    // Shuffle plays will have a last played equal to the time the Shuffle was sync'd
    NSTimeInterval shuffleEpoch = [mountEpoch timeIntervalSince1970];
    SongData *song;
    for (i = 1; i < count; ++i) {
        song = [sorted objectAtIndex:i-1];
        SongData *nextSong = [sorted objectAtIndex:i];
        if (NSOrderedSame != [song compareSongLastPlayedDate:nextSong]) {
            requestEpoch = [song postDate];
            continue;
        }
        
        NSDate *shuffleBegin = [song lastPlayed];
        shuffleEpoch = [shuffleBegin timeIntervalSince1970] - 1.0;
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
    
    if ([[[NSDate dateWithTimeIntervalSince1970:shuffleEpoch] GMTDate] isLessThan:[requestEpoch GMTDate]])
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
    NSUInteger i;
    NSUInteger count;
    
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

- (void)beginiPodSync:(id)sender
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"Sync iPod"] && ![[[NSApp delegate] valueForKey:@"submissionsDisabled"] boolValue]) {
        NSString *path = [self valueForKey:@"iPodMountPath"];
        ISASSERT(path != nil, "bad iPod path!");
        
        NSDate *epoch = [iPodMounts objectForKey:path];
        ISASSERT(epoch != nil, "iPod epoch not found!");
        
        NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
            path, IPOD_SYNC_KEY_PATH,
            epoch, @"epoch",
            nil];
        [[ISiTunesLibrary sharedInstance] loadInBackgroundFromPath:ISCOPY_OF_ITUNES_LIB
            withDelegate:self didFinishSelector:@selector(synciPodWithiTunesLibrary:) context:d];
    }
}

- (void)synciPodWithiTunesLibrary:(NSDictionary*)arg
{
#ifndef IS_SCRIPT_PROXY
    static NSAppleScript *iPodUpdateScript = nil;
#endif
    ScrobTrace (@"synciPod: using playlist %@", [[NSUserDefaults standardUserDefaults] stringForKey:@"iPod Submission Playlist"]);
    
    NSAutoreleasePool *workPool = nil;
    NSDictionary *iTunesLib = [arg objectForKey:@"iTunesLib"];
    @try {
        NSDictionary *context = [arg objectForKey:@"context"];
        ISASSERT(context != nil,  "missing context!");
        
        NSString *iPodVolPath = [context objectForKey:IPOD_SYNC_KEY_PATH];
        NSDate *iPodMountEpoch = [context objectForKey:@"epoch"];
        if (!iPodVolPath || !iPodMountEpoch) {
            ScrobLog(SCROB_LOG_ERR, @"synciPod: missing iPod path or epoch (%@ , %@)", iPodVolPath, iPodMountEpoch);
            @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"missing epoch or vol path" userInfo:nil]);
        }
        NSDate *iPodMountEpochGMT = [iPodMountEpoch GMTDate];
        
        NSArray *trackList, *trackData;
        NSString *errInfo = nil, *playlist;
        NSTimeInterval now, fudge;
        unsigned int added = 0;
        
#ifndef IS_SCRIPT_PROXY
        // Get our iPod update script
        if (!iPodUpdateScript) {
            NSURL *url = [NSURL fileURLWithPath:
                [[[NSBundle bundleForClass:[self class]] resourcePath] stringByAppendingPathComponent:@"Scripts/iPodUpdate.scpt"]];
            iPodUpdateScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:nil];
            if (!iPodUpdateScript) {
                ScrobLog(SCROB_LOG_CRIT, @"Failed to load iPodUpdateScript!");
                @throw ([NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to load iPodUpdateScript!" userInfo:nil]);
            }
        }
#endif
        
        if (!(playlist = [[NSUserDefaults standardUserDefaults] stringForKey:@"iPod Submission Playlist"]) || ![playlist length]) {
            @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"iPod playlist not set, aborting sync." userInfo:nil]);
        }
        
        [[NSNotificationCenter defaultCenter]  postNotificationName:IPOD_SYNC_BEGIN
            object:nil
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:iPodVolPath, IPOD_SYNC_KEY_PATH,
                iPodIcon, IPOD_SYNC_KEY_ICON, nil]];
        
        // Just a little extra fudge time
        fudge = [[[NSApp delegate] valueForKey:@"iTunesLastPlayedTime"] timeIntervalSince1970] + [SongData songTimeFudge];
        now = [[NSDate date] timeIntervalSince1970];
        if (now > fudge) {
            [[NSApp delegate] setValue:[NSDate dateWithTimeIntervalSince1970:fudge] forKey:@"iTunesLastPlayedTime"];
        } else {
            [[NSApp delegate] setValue:[NSDate date] forKey:@"iTunesLastPlayedTime"];
        }
        
        SongData *lastSubmission;
        NSArray *allQueuedSongs = [[[QueueManager sharedInstance] songs] sortedArrayUsingSelector:@selector(compareSongLastPlayedDate:)];
        if ([allQueuedSongs count] > 0) {
            NSEnumerator *queuedEnum = [allQueuedSongs reverseObjectEnumerator];
            while ((lastSubmission = [queuedEnum nextObject])) {
                if ([[[lastSubmission lastPlayed] GMTDate] isLessThan:iPodMountEpochGMT])
                    break;
            }
        } else
            lastSubmission = nil;
        if (!lastSubmission)
            lastSubmission = [[QueueManager sharedInstance] lastSongQueued];
        if (!lastSubmission)
            lastSubmission = [[ProtocolManager sharedInstance] lastSongSubmitted];
        NSDate *requestDate;
        if (lastSubmission) {
            requestDate = [NSDate dateWithTimeIntervalSince1970:
                [[lastSubmission startTime] timeIntervalSince1970] +
                [[lastSubmission duration] doubleValue]];
            // If the song was paused the following will be true.
            if ([[[lastSubmission lastPlayed] GMTDate] isGreaterThan:[requestDate GMTDate]])
                requestDate = [lastSubmission lastPlayed];
            
            requestDate = [NSDate dateWithTimeIntervalSince1970:
                [requestDate timeIntervalSince1970] + [SongData songTimeFudge]];
        } else
            requestDate = [[NSApp delegate] valueForKey:@"iTunesLastPlayedTime"];
        
        NSDate *requestDateGMT= [requestDate GMTDate];
        
        ScrobLog(SCROB_LOG_VERBOSE, @"synciPod: Requesting songs played after '%@'",
            requestDate);
        // Run script
        @try {
            NSArray *args = [NSArray arrayWithObjects:playlist, requestDate, nil];
#ifdef IS_SCRIPT_PROXY
            NSURL *surl = [NSURL fileURLWithPath:
                [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Scripts/iPodUpdate.scpt"]];
            NSDictionary *result;
            result = [[NSApp delegate] runScript:surl handler:@"UpdateiPod" parameters:args];
            if (!(trackList = [result objectForKey:@"result"]))
                errInfo = [result objectForKey:@"error"];
#else
            trackList = [[NSApp delegate] runCompiledScript:iPodUpdateScript handler:@"UpdateiPod" parameters:args];
#endif
        } @catch (NSException *exception) {
            trackList = nil;
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
                errInfo = [exception description];
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
                if (errnum)
                    ScrobLog(SCROB_LOG_ERR, @"synciPod: iPodUpdateScript returned error: \"%@\" (%@)",
                        errmsg, errnum);
                else
                    ScrobLog(SCROB_LOG_ERR, @"synciPod: \"%@\" (%@)", errmsg, errnum);
                errInfo = errmsg;
                goto sync_exit_with_note;
            }

            if (iTunesIsInactive != scriptMsgCode) {
                NSEnumerator *en = [trackList objectEnumerator];
                SongData *song;
                NSMutableArray *iqueue = [NSMutableArray arrayWithCapacity:[trackList count]];
                NSDate *currentDate = [NSDate date];
                NSDate *currentDateGMT = [currentDate GMTDate];
                
                // the first entry is metadata
                NSNumber *sourceIsiTunes = [NSNumber numberWithBool:NO];
                trackData = [en nextObject];
                @try {
                sourceIsiTunes = [trackData objectAtIndex:0];
                // NSString *iTunesVersion = [trackData objectAtIndex:0];
                } @catch (id e) {
                    ScrobLog(SCROB_LOG_ERR, @"exception retriving iPod sync metadata: %@.", e);
                }
                added = 0;
                ScrobLog(SCROB_LOG_TRACE, @"iPodSync: script returned %lu tracks", [trackList count]-1);
                while ((trackData = [en nextObject])) {
                    NSTimeInterval postDate;
                    song = [[SongData alloc] initWithiPodUpdateArray:trackData];
                    if (song) {
                        if ([song ignore]) {
                            ScrobLog(SCROB_LOG_VERBOSE, @"Song '%@' filtered.", [song brief]);
                            [song release];
                            continue;
                        }
                        // Since this song was played "offline", we set the post date in the past 
                        postDate = [[song lastPlayed] timeIntervalSince1970] - [[song duration] doubleValue];
                        [song setPostDate:[NSCalendarDate dateWithTimeIntervalSince1970:postDate]];
                        // Make sure the song passes submission rules                            
                        [song setStartTime:[NSDate dateWithTimeIntervalSince1970:postDate]];
                        [song setPosition:[song duration]];
                        
                        if ([[[song postDate] GMTDate] isGreaterThan:currentDateGMT]) {
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
                
                if (0 == [iqueue count]) {
                    // this can occur when all the songs are filtered or had date problems
                    errInfo = @"No Matching Tracks";
                    goto sync_exit_with_note;
                }
                
                NSMutableArray *extraPlays;
                if (iTunesLib && [sourceIsiTunes boolValue]) {
                    workPool = [[NSAutoreleasePool alloc] init];
                    extraPlays = [[self detectAndSynthesizeMultiplePlays:iqueue iTunesTracks:[iTunesLib objectForKey:@"Tracks"]
                        iPodMountDate:iPodMountEpoch requestDate:requestDate] retain];
                    [workPool release];
                    [extraPlays autorelease];
                    workPool = nil;
                } else {
                    extraPlays = nil;
                    if (!iTunesLib)
                        ScrobLog(SCROB_LOG_WARN, @"Could not find/open iTunes library copy, multiple iPod play detection will not be attempted.");
                    else
                        ScrobLog(SCROB_LOG_WARN, @"Multiple iPod play detection is not supported for iPods in manual sync mode.");
                }
                
                [self fixIPodShuffleTimes:iqueue withRequestDate:requestDate withiPodMountDate:iPodMountEpoch];
                iqueue = [self validateIPodSync:iqueue];
                
                NSNumber *zero = [NSNumber numberWithInt:0];
validate_song_queue:
                en = [iqueue objectEnumerator];
                while ((song = [en nextObject])) {
                    if (![[[song postDate] GMTDate] isGreaterThan:requestDateGMT]) {
                        ScrobLog(SCROB_LOG_WARN,
                            @"Discarding '%@': anachronistic post date.\n\t"
                            "Post Date: %@, Last Played: %@, Duration: %.0lf, requestDate: %@.\n",
                            [song brief], [song postDate], [song lastPlayed], [[song duration] doubleValue],
                            requestDate);
                        continue;
                    }
                    if ([[[song lastPlayed] GMTDate] isGreaterThan:iPodMountEpochGMT]) {
                        ScrobLog(SCROB_LOG_INFO,
                            @"Discarding '%@' in the assumption that it was played after an iPod sync began.\n\t"
                            "Post Date: %@, Last Played: %@, Duration: %.0lf, requestDate: %@, iPodMountEpoch: %@.\n",
                            [song brief], [song postDate], [song lastPlayed], [[song duration] doubleValue],
                            requestDate, iPodMountEpoch);
                        continue;
                    }
                    [song setType:trackTypeFile]; // Only type that's valid for iPod
                    [song setReconstituted:YES];
                    [song setPlayCount:zero]; // we don't want the iTunes play count to update the db
                    ScrobLog(SCROB_LOG_TRACE, @"synciPod: Queuing '%@' with postDate '%@'", [song brief], [song postDate]);
                    (void)[[QueueManager sharedInstance] queueSong:song submit:NO];
                    ++added;
                }
                
                if (extraPlays) {
                    ScrobLog(SCROB_LOG_TRACE, @"Validating and queueing synthesized iPod plays...");
                    iqueue = [self validateIPodSync:extraPlays];
                    extraPlays = nil;
                    goto validate_song_queue;
                }
                
                [[NSApp delegate] setValue:[NSDate date] forKey:@"iTunesLastPlayedTime"];
                if (added > 0) {
                    // we have to delay this, so the plays are submitted AFTER the we finish
                    // otherwise, the queue won't submit because it thinks an iPod is still mounted
                    [[QueueManager sharedInstance] performSelector:@selector(submit) withObject:nil afterDelay:0.0];
                }
            }
        } else {
            // Script error
            ScrobLog(SCROB_LOG_ERR, @"iPodUpdateScript execution error: %@", errInfo);
        }

sync_exit_with_note:
        [[NSNotificationCenter defaultCenter]  postNotificationName:IPOD_SYNC_END
            object:nil
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                iPodVolPath, IPOD_SYNC_KEY_PATH,
                [NSNumber numberWithUnsignedInt:added], IPOD_SYNC_KEY_TRACK_COUNT,
                // errInfo may be nil, so it should always be last in the arg list
                errInfo, IPOD_SYNC_KEY_SCRIPT_MSG,
                nil]];
        
        // copy the iTunes lib for later use in detecting multiple iPod plays
        [[ISiTunesLibrary sharedInstance] copyToPath:ISCOPY_OF_ITUNES_LIB];
        
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"synciPod: exception %@", e);
        [workPool release];
    }
    
    --iPodMountCount; // clean up our extra "fake" count, don't need to update the binding
    ISASSERT(iPodMountCount > -1, "negative ipod count!");
    
    if (iTunesLib) {
        // Release the copy of the iTunes lib on the background thread as it can take quite a bit of time to free if the lib is large
        // By delaying this until the next run loop cyle, we are assured the current auotrelease pool retain is released and
        // the object will actually be released on the background thread
        [[ISiTunesLibrary sharedInstance] performSelector:@selector(releaseiTunesLib:) withObject:[iTunesLib retain] afterDelay:0.0];
    }
}

- (void)deviceWillSync:(NSString*)device
{
    [self setValue:device forKey:@"iPodMountPath"];
    [iPodMounts setObject:[NSDate date] forKey:device];
    
    [[NSApp delegate] willChangeValueForKey:@"isIPodMounted"]; // update our binding
    ++iPodMountCount;
    [[NSApp delegate] didChangeValueForKey:@"isIPodMounted"];
    ISASSERT(iPodMountCount > -1, "negative ipod count!");
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"QueueSubmissionsIfiPodIsMounted"]) {
        [[NSApp delegate] displayWarningWithTitle:NSLocalizedString(@"Queuing Submissions", "")
            message:NSLocalizedString(@"An iPod has been detected. All track plays will be queued until the iPod is ejected.", "")];
    }
}

- (void)syncDevice:(NSString*)device
{
    if ([iPodMounts objectForKey:device]) {
        NSString *curPath = [self valueForKey:@"iPodMountPath"];
        if ([curPath isEqualToString:device]) {
            curPath = nil;
            [iPodIcon release];
            iPodIcon = nil;
        } else
            [self setValue:device forKey:@"iPodMountPath"]; // temp for syncIPod
        
        [self beginiPodSync:nil]; // now that we're sure iTunes synced, we can sync...
        
        [self setValue:curPath forKey:@"iPodMountPath"];
        
        [[NSApp delegate] willChangeValueForKey:@"isIPodMounted"]; // update our binding
        --iPodMountCount;
        [[NSApp delegate] didChangeValueForKey:@"isIPodMounted"];
        ISASSERT(iPodMountCount > -1, "negative ipod count!");
        [iPodMounts removeObjectForKey:device];
        
        // beginiPodSync is async and will return before updating actually begins so,
        // add a "fake" count while we wait for the lib to load so plays are still queued until we are done.
        // This is done outside of a binding update so the GUI does not notice it.
        ++iPodMountCount;
    }
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
        // The iPod icon is no longer used as of 2.1.
        // In addition there's been at least 2 crash reports in 10.5.2 due to what looks like corrupted iPod icons and a problem in NSImage.
        #ifdef notyet
        ISASSERT(iPodIcon == nil, "iPodIcon exists!");
        if ([[NSFileManager defaultManager] fileExistsAtPath:
            [mountPath stringByAppendingPathComponent:@".VolumeIcon.icns"]]) {
            iPodIcon = [[NSImage alloc] initWithContentsOfFile:
                [mountPath stringByAppendingPathComponent:@".VolumeIcon.icns"]];
            [iPodIcon setName:IPOD_ICON_NAME];
        }
        #endif
        [self deviceWillSync:mountPath];
    }
}

- (void)volumeDidUnmount:(NSNotification*)notification
{
    NSDictionary *info = [notification userInfo];
	NSString *mountPath = [info objectForKey:@"NSDevicePath"];
	
    ScrobLog(SCROB_LOG_TRACE, @"Volume unmounted: %@.", info);
    
    [self syncDevice:mountPath];
}

// =========== iPod Core ============

// =========== iPhone/iPod Touch support ===========

- (void)amdsDidStartSync:(NSNotification*)note
{
    ScrobLog(SCROB_LOG_TRACE, @"Mobile Device sync start: %@", [note userInfo]);
}

- (void)amdsDidFinishSync:(NSNotification*)note
{
    ScrobLog(SCROB_LOG_TRACE, @"Mobile Device sync done: %@", [note userInfo]);
    
    [self syncDevice:[note object]];
}

- (void)amdsDidConnect:(NSNotification*)note
{
    ScrobLog(SCROB_LOG_TRACE, @"Mobile Device attached: %@", [note userInfo]);
    
    // sync message does not occur until after iTunes media has been synced, so do the sync setup here
    [self deviceWillSync:[note object]];
    
    [[ISiTunesLibrary sharedInstance] copyToPath:ISCOPY_OF_ITUNES_LIB];
}

- (void)amdsDidDisconnect:(NSNotification*)note
{
    ScrobLog(SCROB_LOG_TRACE, @"Mobile Device ejected: %@", [note userInfo]);
    
    [self syncDevice:[note object]]; // just in case a sync end note was missed (or not sent)
    
    [self presentiPodWarning];
}

- (void)amdsDidFail:(NSNotification*)note
{
    ScrobLog(SCROB_LOG_ERR, @"Failed to initialize iPhone/iPod Touch support: %@", [note object]);
    [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Failed to initialize iPhone/iPod Touch support.", "") message:nil];
}

// =========== iPhone/iPod Touch support ===========

- (void)presentiPodWarning
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SupressiPodWarning"])
        return;

    // warn user of possible lost scrobbles
    NSError *error = [NSError errorWithDomain:@"iscrobbler" code:0 userInfo:
    [NSDictionary dictionaryWithObjectsAndKeys:
        NSLocalizedString(@"iPod Scrobbling Help", nil), NSLocalizedFailureReasonErrorKey,
        NSLocalizedString(@"An iPod has been ejected. If any song is played on your computer and submitted to Last.fm before you sync your iPod again, some or all iPod submissions may be lost. To avoid this, please sync your iPod before playing any music on your computer (via iTunes, Last.fm Radio, etc).", nil),
            NSLocalizedDescriptionKey,
        NSLocalizedString(@"OK", nil), @"defaultButton",
        NSLocalizedString(@"Don't show this message again.", nil), @"supressionButton",
        nil]];
    [[NSApp delegate] presentError:error modalDelegate:self didEndHandler:@selector(iPodWarningDidEnd:returnCode:contextInfo:)];
}

- (void)iPodWarningDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void*)contextInfo
{
    LEOPARD_BEGIN
    if ([alert showsSuppressionButton] && NSOnState == [[alert suppressionButton] state])
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SupressiPodWarning"];
    LEOPARD_END
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
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
}

#ifdef IS_SCRIPT_PROXY
- (void)proxyDidStart:(NSNotification*)note
{
    NSDistantObject<ISProxyProtocol> *proxy = [note object];
    NSString *framework = [[NSUserDefaults standardUserDefaults] stringForKey:@"Apple MobileDevice Framework"];
    [proxy initializeMobileDeviceSupport:framework];
}
#endif

@end

@implementation SongData (iScrobblerControllerPrivateAdditions)

- (SongData*)initWithiPodUpdateArray:(NSArray*)data
{
    self = [self init];
    ScrobLog(SCROB_LOG_TRACE, @"Song components from iPodUpdate result: %@", data);
    
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
        [self setPlayCount:[data objectAtIndex:14]];
        [self setPlayerUUID:[data objectAtIndex:15]];
        NSNumber *newYear= [data objectAtIndex:16];
        if (newYear && [newYear unsignedIntValue] > 0)
            [self setYear:newYear];
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

// iTunes sends com.apple.iTunes.sourceSaved when it saves the XML - should we watch for that instead
static void IOMediaAddedCallback(void *refcon, io_iterator_t iter)
{
    io_service_t iomedia;
    CFMutableDictionaryRef properties;
    kern_return_t kr;
    while ((iomedia = IOIteratorNext(iter))) {
        kr = IORegistryEntryCreateCFProperties(iomedia, &properties, kCFAllocatorDefault, 0);
        if (kr == 0 && [[(NSDictionary*)properties objectForKey:@kIOMediaWholeKey] boolValue]) {
            // We could get fancy and make sure the media is an iPod, but for now we'll just copy blindly.
            ScrobDebug(@"");
            [[ISiTunesLibrary sharedInstance] copyToPath:ISCOPY_OF_ITUNES_LIB];
        }
        CFRelease(properties);
        IOObjectRelease(iomedia);
    }
}
