//
//  SongData.h
//  iScrobbler
//
//  Created by Sam Ley on Thu Mar 20 2003.
//  Copyright (c) 2003 Sam Ley. All rights reserved.
//  Copyright 2004-2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Cocoa/Cocoa.h>

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
    u_int64_t iTunesDatabaseID; // iTunes track id
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
    NSNumber *playlistID;
    NSString *sourceName;
    NSString *genre;
    NSString *comment;
    NSString *mbid;
    TrackType_t trackType;
    unsigned trackNumber;
    unsigned isPodcast : 1;
    unsigned hasQueued : 1;
    unsigned hasSeeked : 1;
    unsigned reconstituted : 1;
    unsigned passedFilters : 1;
    unsigned loved : 1;
    unsigned banned : 1;
    unsigned iTunes : 1;
    unsigned isPaused : 1;
    unsigned isLastFmRadio: 1;
}

// Value to pad time calculations with
+ (float)songTimeFudge;
+ (void)setSongTimeFudge:(float)fudge;
+ (NSString *)notRatedString;
+ (void)drainArtworkCache;

// returns a float value between 0 and 100 indicating how much of the song
// has been played as a percent
- (NSNumber *)percentPlayed;

// returns the amount of time, in seconds, that the song has been playing.
- (NSNumber *)timePlayed;

- (BOOL)isEqualToSong:(SongData*)song;

- (NSString*)brief;

- (NSComparisonResult) compareSongPostDate:(SongData*)song;

- (NSComparisonResult)compareSongLastPlayedDate:(SongData*)song;

////// Accessors Galore ///////

- (BOOL)isPlayeriTunes;
- (void)setIsPlayeriTunes:(BOOL)val;

- (u_int64_t)iTunesDatabaseID;
- (void)setiTunesDatabaseID:(u_int64_t)newID;

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

- (void)didPause;
- (BOOL)isPaused;
- (void)didResumeFromPause;

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
// Same as starRating, but empty stars are provide for ratings less than 5
- (NSString*)fullStarRating;

- (NSNumber*)songID;

- (BOOL)hasSeeked;
- (void)setHasSeeked;

// Used for persistent cache storage
- (NSDictionary*)songData;
- (BOOL)setSongData:(NSDictionary*)data;

- (TrackType_t)type;
- (void)setType:(TrackType_t)newType;

- (NSNumber*)playlistID;
- (void)setPlaylistID:(NSNumber*)newPlaylistID;

- (NSString*)sourceName;
- (void)setSourceName:(NSString*)newSourceName;

- (BOOL)reconstituted;
- (void)setReconstituted:(BOOL)newValue;

- (NSString*)genre;
- (void)setGenre:(NSString*)newGenre;

- (NSNumber*)elapsedTime;

- (NSImage*)artwork;

- (BOOL)isPodcast;
- (void)setIsPodcast:(BOOL)podcast;

- (NSString*)comment;
- (void)setComment:(NSString*)comment;

- (NSString*)mbid;
- (void)setMbid:(NSString*)newMBID;

- (BOOL)ignore;

- (BOOL)loved;
- (void)setLoved:(BOOL)isLoved;

- (BOOL)banned;
- (void)setBanned:(BOOL)isBanned;

- (BOOL)isLastFmRadio;

- (NSNumber*)trackNumber;
- (void)setTrackNumber:(NSNumber*)number;

@end

@interface SongData (SongDataComparisons)

- (BOOL)hasPlayedAgain:(SongData*)song;

@end
