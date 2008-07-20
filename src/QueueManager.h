//
//  QueueManager.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/2004.
//  Copyright 2004,2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class SongData;
@class ISThreadMessenger;

enum {kqSuccess, kqIsQueued, kqFailed};
typedef NSInteger QueueResult_t;

@interface QueueManager : NSObject {
@private
	NSString *queuePath;
    SongData *lastSongQueued;
    ISThreadMessenger *qThread;
    id songQueue;
    unsigned totalSubmissions;
    unsigned totalSubmissionSeconds;
}

+ (QueueManager*)sharedInstance;

// Queues a song, sets the post date, and immediately tries to submit it.
- (QueueResult_t)queueSong:(SongData*)song;

// If submit is false, the post date is not set.
- (QueueResult_t)queueSong:(SongData*)song submit:(BOOL)submit;

- (void)submit;

// If unique is true, the song id must also match
// (in addition to title, album, artist).
- (BOOL)isSongQueued:(SongData*)song unique:(BOOL)unique;

// Removes song and syncs the queue
- (void)removeSong:(SongData*)song;

- (void)removeSong:(SongData*)song sync:(BOOL)sync;

// Unsorted array of songs
- (NSArray*)songs;

- (NSUInteger)count;

- (unsigned)totalSubmissionsCount;
- (NSNumber*)totalSubmissionsPlayTimeInSeconds;

// Aliases for Protocol Manager methods
- (unsigned)submissionAttemptsCount;
- (unsigned)successfulSubmissionsCount;

- (void)syncQueue:(id)sender;

- (SongData*)lastSongQueued;

@end

#define QM_NOTIFICATION_SONG_QUEUED @"QMNotificationSongQueued"
#define QM_NOTIFICATION_SONG_DEQUEUED @"QMNotificationSongDeQueued"

#define QM_NOTIFICATION_USERINFO_KEY_SONG @"Song"
