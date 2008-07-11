//
//  PersistentSessionManager.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/17/2007.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ISThreadMessenger;
@class SongData;

// handles all additions/modifications and removals
@interface PersistentSessionManager : NSObject {
    NSTimer *lfmUpdateTimer;
    NSTimer *sUpdateTimer;
    ISThreadMessenger *thMsgr;
}

+ (PersistentSessionManager*)sharedInstance;
- (ISThreadMessenger*)threadMessenger;

- (NSArray*)activeSessionsWithMOC:(NSManagedObjectContext*)moc;
- (NSArray*)archivedSessionsWithMOC:(NSManagedObjectContext*)moc weekLimit:(NSUInteger)limit;
- (NSManagedObject*)sessionWithName:(NSString*)name moc:(NSManagedObjectContext*)moc;
- (NSArray*)artistsForSession:(id)session moc:(NSManagedObjectContext*)moc;
- (NSArray*)albumsForSession:(id)session moc:(NSManagedObjectContext*)moc;

- (void)synchronizeDatabaseWithiTunes;

@end

@interface PersistentSessionManager (SongAdditions)
- (NSManagedObject*)orphanedItems:(NSManagedObjectContext*)moc;;
- (BOOL)addSessionSong:(NSManagedObject*)sessionSong toSession:(NSManagedObject*)session moc:(NSManagedObjectContext*)moc;
// used by internally and by importer
- (void)updateSongHistory:(NSManagedObject*)psong count:(NSNumber*)count time:(NSNumber*)time moc:(NSManagedObjectContext*)moc;
- (void)incrementSessionCountsWithSong:(NSManagedObject*)sessionSong moc:(NSManagedObjectContext*)moc;
- (NSManagedObject*)addSongPlay:(SongData*)song withImportedPlayCount:(NSNumber*)importCount moc:(NSManagedObjectContext*)moc;
@end

@interface NSManagedObject (PItemMathAdditions)
- (void)incrementPlayCount:(NSNumber*)count;
- (void)incrementPlayTime:(NSNumber*)count;
- (void)incrementPlayCountWithObject:(NSManagedObject*)obj;
- (void)incrementPlayTimeWithObject:(NSManagedObject*)obj;

- (void)decrementPlayCount:(NSNumber*)count;
- (void)decrementPlayTime:(NSNumber*)count;
@end

// implemented in Persistence.m
@interface NSManagedObject (ISProfileAdditions)
- (void)refreshSelf;
@end

#define ITEM_UNKNOWN @"u"
#define ITEM_SONG @"so"
#define ITEM_ARTIST @"a"
#define ITEM_ALBUM @"al"
#define ITEM_SESSION @"s"
#define ITEM_RATING_CCH @"r"
#define ITEM_HOUR_CCH @"h"
#define ITEM_TAG @"t"
