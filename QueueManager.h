//
//  QueueManager.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/2004.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>

@class SongData;

@interface QueueManager : NSObject {
@private
	NSString *queuePath;
    id songQueue;
}

+ (QueueManager*)sharedInstance;

// Queues a song, sets the post date, and immediately tries to submit it.
- (void)queueSong:(SongData*)song;

// If submit is false, the post date is not set.
- (void)queueSong:(SongData*)song submit:(BOOL)submit;

- (void)submit;

// If unique is true, the song id must also match
// (in addition to title, album, artist).
- (BOOL)isSongQueued:(SongData*)song unique:(BOOL)unique;

// Removes song and syncs the queue
- (void)removeSong:(SongData*)song;

- (void)removeSong:(SongData*)song sync:(BOOL)sync;

// Unsorted array of songs
- (NSArray*)songs;

- (unsigned)count;

- (BOOL)writeToFile:(NSString*)path atomically:(BOOL)atomic;
- (void)syncQueue:(id)sender;

@end
