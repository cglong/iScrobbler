//
//  SongData.h
//  iScrobbler
//
//  Created by Sam Ley on Thu Mar 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    trackTypeUnknown = 0,
    trackTypeFile = 1,
    trackTypeShared = 2,
    trackTypeRadio = 3,
} TrackType_t;
static __inline__ BOOL IsTrackTypeValid (TrackType_t myType)
{
    return ( trackTypeFile == myType || trackTypeShared == myType );
}

@interface SongData : NSObject <NSCopying> {
    unsigned int songID; // Internal id #
    int iTunesDatabaseID; // iTunes track id
    NSString * title;
    NSNumber * duration;
    NSNumber * position;
    NSString * artist;
    NSString * album;
    NSString * path;
    NSDate * startTime;
    NSNumber * pausedTime;
    NSDate * postDate;
    NSDate * lastPlayed;
    NSNumber *rating;
    TrackType_t trackType;
    BOOL hasQueued;
    BOOL hasSeeked;
}

// Value to pad time calculations with
+ (float)songTimeFudge;
+ (void)setSongTimeFudge:(float)fudge;

// returns a float value between 0 and 100 indicating how much of the song
// has been played as a percent
- (NSNumber *)percentPlayed;

// returns the amount of time, in seconds, that the song has been playing.
- (NSNumber *)timePlayed;

- (BOOL)isEqualToSong:(SongData*)song;

- (NSString*)brief;

- (NSComparisonResult) compareSongPostDate:(SongData*)song;

////// Accessors Galore ///////

- (int)iTunesDatabaseID;
- (void)setiTunesDatabaseID:(int)newID;

// title is the title of the song
- (NSString *)title;
- (void)setTitle:(NSString *)newTitle;

// duration is the length of the song in seconds
- (NSNumber *)duration;
- (void)setDuration:(NSNumber *)newDuration;

// position is the current track position (in seconds) within the song
- (NSNumber *)position;
- (void)setPosition:(NSNumber *)newPosition;

// artist is the artist of the track
- (NSString *)artist;
- (void)setArtist:(NSString *)newArtist;

// album is the album of the track
- (NSString *)album;
- (void)setAlbum:(NSString *)newAlbum;

// path is the filesystem path of the track
- (NSString *)path;
- (void)setPath:(NSString *)newPath;

// startTime is the system time at which the track began playing
- (NSDate *)startTime;
- (void)setStartTime:(NSDate *)newStartTime;

// hasQueued is a bool value indicating whether the song has been queued or not
- (BOOL)hasQueued;
- (void)setHasQueued:(BOOL)newHasQueued;

// pausedTime is the total length of time the song has been paused for
- (NSNumber *)pausedTime;
- (void)setPausedTime:(NSNumber *)newPausedTime;

// postDate is the moment in which the initial submission was attempted
- (NSDate *)postDate;
- (void)setPostDate:(NSDate *)newPostDate;

// lastPlayed is the last time iTunes played the song
- (NSDate *)lastPlayed;
- (void)setLastPlayed:(NSDate *)date;

// Rating on a scale of 0 to 100
- (NSNumber*)rating;
- (void)setRating:(NSNumber*)newRating;
// Scales rating to between 0 and 5 (as iTunes presents it to the user)
- (NSNumber*)scaledRating;
// String of stars representing the scaled rating
- (NSString*)starRating;

- (NSNumber*)songID;

- (BOOL)hasSeeked;
- (void)setHasSeeked;

// Used for persistent cache storage
- (NSDictionary*)songData;
- (BOOL)setSongData:(NSDictionary*)data;

- (TrackType_t)type;
- (void)setType:(TrackType_t)newType;

@end

@interface SongData (SongDataComparisons)

- (BOOL)hasPlayedAgain:(SongData*)song;

@end
