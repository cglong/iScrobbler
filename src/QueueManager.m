//
//  QueueManager.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/2004.
//  Copyright 2004-2008,2010 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <libkern/OSAtomic.h>

#import "QueueManager.h"
#import "SongData.h"
#import "iScrobblerController.h"
#import "ProtocolManager.h"
#import "iPodController.h"
#import "ISRadioController.h"
#import "ISThreadMessenger.h"

// serial queue to write the submission queue to disk
__private_extern__ dispatch_queue_t sqdq = NULL;
static void __attribute__((constructor)) sqdq_constructor(void)
{
    sqdq = dispatch_queue_create("org.bergstrand.qmanager", NULL);
}

static QueueManager *g_QManager = nil;

@implementation QueueManager

+ (QueueManager*)sharedInstance
{
    if (!g_QManager)
        g_QManager = [[QueueManager alloc] init];
    return (g_QManager);
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if (g_QManager == nil) {
            return ([super allocWithZone:zone]);
        }
    }

    return (g_QManager);
}

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

- (SongData*)lastSongQueued
{
    return (lastSongQueued);
}


- (void)setLastSongQueued:(SongData*)song
{
    if (!lastSongQueued || [[song postDate] isGreaterThan:[lastSongQueued postDate]]) {
        (void)[song retain];
        [lastSongQueued release];
        lastSongQueued = song;
        
        NSDictionary *d = [lastSongQueued songData];
        if (d) {
            [[NSUserDefaults standardUserDefaults] setObject:d forKey:@"LastSongQueued"];
            (void)[[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
}

// Queues a song and immediately tries to send it.
- (QueueResult_t)queueSong:(SongData*)song
{
    return ([self queueSong:song submit:YES]);
}

- (QueueResult_t)queueSong:(SongData*)song submit:(BOOL)submit
{
    SongData *found;
    NSEnumerator *en = [songQueue objectEnumerator];
    
    if ([song isLastFmRadio] && NO == [[ISRadioController sharedInstance] scrobbleRadioPlays]) {
        return (kqSuccess);
    }
    // We have to subit radio plays ourself when using the xspf protocol, so let them fall through
    
    if (![song canSubmit]) {
        ScrobLog(SCROB_LOG_TRACE, @"Track '%@ [%@ of %@]' failed submission rules. Not queuing.\n",
            [song brief], [song position], [song duration]);
        return (kqFailed);
    }
    
    if([song hasQueued]) {
        ScrobLog(SCROB_LOG_TRACE, @"Track '%@' is already queued for submission. Ignoring.\n", song);
        return (kqIsQueued);
    }
    
    while ((found = [en nextObject])) {
        if ([found isEqualToSong:song])
            break;
    }
    
    if (found) {
        // Found in queue
        // Check to see if the song has been played again
        if (![found hasPlayedAgain:song]) {
            ScrobLog(SCROB_LOG_TRACE, @"Track '%@' found in queue as '%@'. Ignoring.\n", song, found);
            return (kqIsQueued);
        }
        // Otherwise, the song will be in the queue twice,
        // on the assumption that it has been played again
    }
    
    ScrobLog(SCROB_LOG_VERBOSE, @"Queuing track '%@' for submission\n", [song brief]);
    
    // Add to top of list
    [song setHasQueued:YES];
    [songQueue addObject:song];
    ++totalSubmissions;
    totalSubmissionSeconds += [[song duration] unsignedIntValue];
    
    [self setLastSongQueued:song];
    
    @try {
    [[NSNotificationCenter defaultCenter] postNotificationName:QM_NOTIFICATION_SONG_QUEUED
        object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
            song, QM_NOTIFICATION_USERINFO_KEY_SONG,
            [NSNumber numberWithUnsignedLongLong:[songQueue count]], @"queueCount",
            nil]]; 
    } @catch (NSException *e) {
        ScrobDebug(@"exception: %@");
    }
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DisableSubmissions"]) {
        [songQueue removeAllObjects];
        submit = NO;
        [[ProtocolManager sharedInstance] performSelector:@selector(setLastSongSubmitted:) withObject:song];
    }
    
    if (submit) {
        [song setPostDate:[song startTime]];
        [self submit];
    }
    
    return (kqSuccess);
}

- (void)submit
{
    // Wake the protocol mgr
    if ([songQueue count]) {
        [self syncQueue:nil];
        if (NO == [[NSApp delegate] queueSongsForLaterSubmission])
            [[ProtocolManager sharedInstance] submit:nil];
        else {
            id paths = [[iPodController sharedInstance] valueForKey:@"iPodMounts"];
            ScrobLog(SCROB_LOG_INFO, @"QM: Submission is delayed. ForcePlayCache: %u, iPodMountCount: %@, iPodMount paths: %@",
                [[NSUserDefaults standardUserDefaults] boolForKey:@"ForcePlayCache"],
                [[iPodController sharedInstance] valueForKey:@"iPodMountCount"],
                paths ? paths : @"{none}");
        }
    }
}

- (BOOL)isSongQueued:(SongData*)song unique:(BOOL)unique
{
    SongData *found;
    NSEnumerator *en = [songQueue objectEnumerator];
    
    while ((found = [en nextObject])) {
        if ([found isEqualToSong:song]) {
            if (unique && ![[found songID] isEqualToNumber:[song songID]])
                continue;
            else
                break;
        }
    }
    
    return ((found ? YES : NO));
}

- (void)removeSong:(SongData*)song
{
    [self removeSong:song sync:YES];
}

- (void)removeSong:(SongData*)song sync:(BOOL)syncQueue
{
    SongData *found;
    NSUInteger idx, count;
    
    count = [songQueue count];
    for (idx = 0; idx < count; ++idx) {
        found = [songQueue objectAtIndex:idx];
        if ([found isEqualToSong:song] &&
             [[found songID] isEqualToNumber:[song songID]]) {
            
            [found retain];
            [songQueue removeObjectAtIndex:idx];
            
            @try {
            [[NSNotificationCenter defaultCenter] postNotificationName:QM_NOTIFICATION_SONG_DEQUEUED
                object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                    song, QM_NOTIFICATION_USERINFO_KEY_SONG,
                    [NSNumber numberWithUnsignedLongLong:[songQueue count]], @"queueCount",
                    nil]];
            } @catch (NSException *e) {
                ScrobDebug(@"exception: %@");
            }
    
            [found release];
            
            if (syncQueue)
                [self syncQueue:nil];
            break;
        }
    }
}

// Unsorted array of songs
- (NSArray*)songs
{
    return ([[songQueue copy] autorelease]);
}

- (NSUInteger)count
{
    return ([songQueue count]);
}

- (unsigned)totalSubmissionsCount
{
    return (totalSubmissions);
}

- (NSNumber*)totalSubmissionsPlayTimeInSeconds
{
    return ([NSNumber numberWithUnsignedInt:totalSubmissionSeconds]);
}

// Aliases for Protocol Manager methods
- (unsigned)submissionAttemptsCount
{
    return ([[ProtocolManager sharedInstance] submissionAttemptsCount]);
}

- (unsigned)successfulSubmissionsCount
{
    return ([[ProtocolManager sharedInstance] successfulSubmissionsCount]);
}

#define CACHE_SIG_KEY @"Persistent Cache Sig"

- (void)writeQueuedSongs:(NSArray*)songs
{
    NSData *data = [NSPropertyListSerialization dataFromPropertyList:songs
        format:NSPropertyListBinaryFormat_v1_0
        errorDescription:nil];
    if (data && [data writeToFile:queuePath atomically:YES]) {
        NSString *md5 = [[NSApp delegate] md5hash:data];
        [[NSUserDefaults standardUserDefaults] setObject:md5 forKey:CACHE_SIG_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        ScrobLog(SCROB_LOG_ERR, @"Failed to create queue file: %@!\n", queuePath);
    }
}

- (void)writeQueue:(NSString*)path
{
    NSMutableArray *songs = [NSMutableArray array];
    NSDictionary *songData;
    SongData *song;
    NSEnumerator *en = [songQueue objectEnumerator];
    
    while ((song = [en nextObject])) {
        if ((songData = [song songData]))
            [songs addObject:songData];
        else
            ScrobLog(SCROB_LOG_ERR, @"Failed to add '%@' to persitent store.\n", [song brief]);
    }
    
    dispatch_async(sqdq, ^{
    [self writeQueuedSongs:songs];
    });
}

- (void)removeQueue:(id)arg
{
    [[NSUserDefaults standardUserDefaults] setObject:@"" forKey:CACHE_SIG_KEY];
    [[NSFileManager defaultManager] removeItemAtPath:queuePath error:nil];
}

- (void)syncQueue:(id)sender
{
    if (0 == [songQueue count]) {
        dispatch_async(sqdq, ^{
        [self removeQueue:nil];
        });
    } else {
        [self writeQueue:queuePath];
    }
}

- (NSArray*)restoreQueueWithPath:(NSString*)path
{
    NSString *md51, *md52;
    NSData *data;
    NSArray *pCache = nil;
    
    //data = [NSString stringWithContentsOfFile:queuePath];
    data = [NSData dataWithContentsOfFile:queuePath];
    md51 = [[NSUserDefaults standardUserDefaults] stringForKey:CACHE_SIG_KEY];
    md52 = data ? [[NSApp delegate] md5hash:data] : @"";
    if (data && [md51 isEqualToString:md52]) {
        NSPropertyListFormat format;
        pCache = [NSPropertyListSerialization propertyListFromData:data
            mutabilityOption:NSPropertyListImmutable
            format:&format
            errorDescription:nil];
        if (NO == [pCache isKindOfClass:[NSArray class]])
            pCache = nil;
    } else if (data) {
        ScrobLog(SCROB_LOG_WARN, @"Ignoring persistent cache: it's corrupted.");
        // This will remove the file, since the queue is 0
    #ifdef notyet
        [self syncQueue:nil];
    #endif
    }
    return (pCache);
}

- (id)init
{
    if ((self = [super init])) {
        // We keep track of this for iPod support which uses lastSubmitted to
        // determine the timestamp used in played songs detection.
        NSDictionary *d = [[NSUserDefaults standardUserDefaults] objectForKey:@"LastSongQueued"];
        if (d) {
            SongData *song = [[SongData alloc] init];
            if ([song setSongData:d]) {
                ScrobLog(SCROB_LOG_TRACE, @"Restored '%@' as last queued song.", [song brief]);
                [song setStartTime:[song postDate]];
                [song setPosition:[song duration]];
                [self setLastSongQueued:song];
            } else
                ScrobLog(SCROB_LOG_ERR, @"Failed to restore last queued song: %@", d);
            [song release];
        }
        
        FSRef appSupport;
        NSString *tmp;
        if (noErr == FSFindFolder(kUserDomain, kApplicationSupportFolderType, kCreateFolder, &appSupport)) {
            NSURL *url = (NSURL*)CFURLCreateFromFSRef(kCFAllocatorSystemDefault, &appSupport);
            NSString *dirPath  = (NSString*)CFURLCopyFileSystemPath((CFURLRef)url, kCFURLPOSIXPathStyle);
            [url release];
            if (dirPath) {
                tmp = [dirPath stringByAppendingPathComponent:@"net_sourceforge_iscrobbler_cache.plist"];
                if ([[NSFileManager defaultManager] fileExistsAtPath:tmp]) {
                    (void)[[NSFileManager defaultManager] moveItemAtPath:tmp
                        toPath:[dirPath stringByAppendingPathComponent:@"org.bergstrand.iscrobbler.cache.plist"]
                        error:nil];
                }
                queuePath = [dirPath stringByAppendingPathComponent:@"org.bergstrand.iscrobbler.cache.plist"];
                [dirPath release];
            }
        }
        
        tmp = queuePath;
        queuePath = [[[[NSFileManager defaultManager] iscrobblerSupportFolder]
            stringByAppendingPathComponent:@"subcache.plist"] retain];
        if ([[NSFileManager defaultManager] fileExistsAtPath:tmp]) {
            (void)[[NSFileManager defaultManager] moveItemAtPath:tmp toPath:queuePath error:nil];
        }

        songQueue = [[NSMutableArray alloc] init];
        
        // Read in the persistent cache
        if (queuePath) {
            NSArray *pCache = [self restoreQueueWithPath:queuePath];
            if ([pCache count]) {
                NSEnumerator *en = [pCache objectEnumerator];
                SongData *song;
                NSDictionary *data;
                while ((data = [en nextObject])) {
                    song = [[SongData alloc] init];
                    if ([song setSongData:data]) {
                        ScrobLog(SCROB_LOG_VERBOSE, @"Restoring '%@' from persistent store.\n", [song brief]);
                        // Make sure the song passes submission rules
                        [song setStartTime:[song postDate]];
                        [song setPosition:[song duration]];
                        (void)[self queueSong:song submit:NO]; 
                    } else {
                        ScrobLog(SCROB_LOG_ERR, @"Failed to restore song from persistent store: %@\n", data); 
                    }
                    [song release];
                }
            }
        } else {
            ScrobLog(SCROB_LOG_ERR, @"Persistent cache disabled: could not find path.");
        }
    }
    
    return (self);
}

#ifdef notyet
- (void)dealloc
{
    [queuePath release];
    [songQueue release];
    [lastSongQueued release];
    [super dealloc];
}
#endif

@end
