//
//  QueueManager.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/2004.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "QueueManager.h"
#import "SongData.h"
#import "iScrobblerController.h"
#import "ProtocolManager.h"

static QueueManager *g_QManager = nil;

@implementation QueueManager

+ (QueueManager*)sharedInstance
{
    if (!g_QManager)
        g_QManager = [[QueueManager alloc] init];
    return (g_QManager);
}

// Queues a song and immediately tries to send it.
- (void)queueSong:(SongData*)song
{
    [self queueSong:song submit:YES];
}

- (void)queueSong:(SongData*)song submit:(BOOL)submit
{
    SongData *found;
    NSEnumerator *en = [songQueue objectEnumerator];
    
    if (![song canSubmit])
        return;
    
    if([song hasQueued])
        return;
    
    while ((found = [en nextObject])) {
        if ([found isEqualToSong:song])
            break;
    }
    
    if (found) {
        // Found in queue
        // Check to see if the song has been played again
        if (![found hasPlayedAgain:song])
            return;
        // Otherwise, the song will be in the queue twice,
        // on the assumption that it has been played again
    }
    
    // Add to top of list
    [song setHasQueued:YES];
    [songQueue addObject:song];
    ++totalSubmissions;
    totalSubmissionSeconds += [[song duration] unsignedIntValue];
    
    [[NSNotificationCenter defaultCenter]
        postNotificationName:QM_NOTIFICATION_SONG_QUEUED
        object:self
        userInfo:[NSDictionary dictionaryWithObject:song forKey:QM_NOTIFICATION_USERINFO_KEY_SONG]]; 

#define QM_NOTIFICATION_USERINFO_KEY_SONG @"Song"
    
    if (submit) {
        [song setPostDate:[song startTime]];
        [self submit];
    }
}

- (void)submit
{
    // Wake the protocol mgr
    if ([songQueue count]) {
        [self syncQueue:nil];
        [[ProtocolManager sharedInstance] submit:nil];
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

- (void)removeSong:(SongData*)song sync:(BOOL)sync
{
    SongData *found;
    unsigned int idx;
    
    for (idx = 0; idx < [songQueue count]; ++idx) {
        found = [songQueue objectAtIndex:idx];
        if ([found isEqualToSong:song] &&
             [[found songID] isEqualToNumber:[song songID]]) {
            
            [found retain];
            [songQueue removeObjectAtIndex:idx];
            
            [[NSNotificationCenter defaultCenter]
                postNotificationName:QM_NOTIFICATION_SONG_DEQUEUED
                object:self
                userInfo:[NSDictionary dictionaryWithObject:song forKey:QM_NOTIFICATION_USERINFO_KEY_SONG]];
        
            [found release];
            
            if (sync)
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

- (unsigned)count
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

- (BOOL)writeToFile:(NSString*)path atomically:(BOOL)atomic
{
    NSMutableArray *data = [NSMutableArray array];
    NSDictionary *songData;
    SongData *song;
    NSEnumerator *en = [songQueue objectEnumerator];
    
    if (0 == [songQueue count])
        return (NO);
    
    while ((song = [en nextObject])) {
        if ((songData = [song songData]))
            [data addObject:songData];
        else
            ScrobLog(SCROB_LOG_ERR, @"Failed to add '%@' to persitent store.\n", [song brief]);
    }
    
    return ([data writeToFile:path atomically:atomic]);
}

#define CACHE_SIG_KEY @"Persistent Cache Sig"

- (void)syncQueue:(id)sender
{
    BOOL good;
    if ((good = [self writeToFile:queuePath atomically:YES])) {
        NSString *data = [NSString stringWithContentsOfFile:queuePath];
        if (!data || 0 == [data length]) {
            ScrobLog(SCROB_LOG_ERR, @"Failed to read queue file: %@! Queue (%u entries) not saved.\n",
                queuePath, [songQueue count]);
            return;
        }
        NSString *md5 = [[NSApp delegate] md5hash:data];
        [[NSUserDefaults standardUserDefaults] setObject:md5 forKey:CACHE_SIG_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else if (0 == [songQueue count]) {
        [[NSUserDefaults standardUserDefaults] setObject:@"" forKey:CACHE_SIG_KEY];
        [[NSFileManager defaultManager] removeFileAtPath:queuePath handler:nil];
    } else {
        ScrobLog(SCROB_LOG_ERR, @"Failed to create queue file: %@!\n", queuePath);
    }
}

- (id)init
{
    if ((self = [super init])) {
        FSRef appSupport;
        
        if (noErr == FSFindFolder(kUserDomain, kApplicationSupportFolderType, kCreateFolder, &appSupport)) {
            NSURL *url = (NSURL*)CFURLCreateFromFSRef(kCFAllocatorSystemDefault, &appSupport);
            NSString *dirPath  = (NSString*)CFURLCopyFileSystemPath((CFURLRef)url, kCFURLPOSIXPathStyle);
            [url release];
            if (dirPath) {
                queuePath = [[dirPath stringByAppendingPathComponent:@"net_sourceforge_iscrobbler_cache.plist"] retain];
                [dirPath release];
            }
        }

        songQueue = [[NSMutableArray alloc] init];
        
        // Read in the persistent cache
        if (queuePath) {
            NSString *md51, *md52, *data;
            
            data = [NSString stringWithContentsOfFile:queuePath];
            md51 = [[NSUserDefaults standardUserDefaults] stringForKey:CACHE_SIG_KEY];
            md52 = data ? [[NSApp delegate] md5hash:data] : @"";
            if (data && [md51 isEqualToString:md52]) {
                NSArray *pCache = [NSArray arrayWithContentsOfFile:queuePath];
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
                            [self queueSong:song submit:NO]; 
                        } else {
                            ScrobLog(SCROB_LOG_ERR, @"Failed to restore song from persistent store: %@\n", data); 
                        }
                        [song release];
                    }
                }
            } else if (data) {
                ScrobLog(SCROB_LOG_WARN, @"Ignoring persistent cache: it's corrupted.");
                // This will remove the file, since the queue is 0
            #ifdef notyet
                [self syncQueue:nil];
            #endif
            }
        } else {
            ScrobLog(SCROB_LOG_ERR, @"Persistent cache disabled: could not find path.");
        }
    }
    
    return (self);
}

- (void)dealloc
{
    [queuePath release];
    [songQueue release];
}

@end
