//
//  SongData.m
//  iScrobbler
//
//  Created by Sam Ley on Thu Mar 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "SongData.h"

static unsigned int g_songID = 0;
static float songTimeFudge;

@implementation SongData

+ (float)songTimeFudge
{
    return (songTimeFudge);
}

+ (void)setSongTimeFudge:(float)fudge
{
    songTimeFudge = fudge;
}

- (id)init
{
    [super init];

    // set the id
    songID = g_songID;
    IncrementAtomic((SInt32*)&g_songID);
    
    // initialize some empty values
    [self setTrackIndex:[NSNumber numberWithFloat:0.0]];
    [self setPlaylistIndex:[NSNumber numberWithFloat:0.0]];
    [self setTitle:@""];
    [self setDuration:[NSNumber numberWithFloat:0.0]];
    [self setPosition:[NSNumber numberWithFloat:0.0]];
    [self setArtist:@""];
    [self setAlbum:@""];
    [self setPath:@""];
    [self setPostDate:[NSCalendarDate date]];
    [self setHasQueued:NO];

    // initialize with current time
    [self setStartTime:[NSDate date]];
    [self setLastPlayed:[NSDate date]];

    return self;
}

// Override copyWithZone so we can return copies of the object.
- (id)copyWithZone: (NSZone *)zone
{
    id copy = [[[self class] alloc] init];

    [copy setArtist:[self artist]];
    [copy setTrackIndex:[self trackIndex]];
    [copy setTitle:[self title]];
    [copy setAlbum:[self album]];
    [copy setPlaylistIndex:[self playlistIndex]];
    [copy setPosition:[self position]];
    [copy setDuration:[self duration]];
    [copy setPath:[self path]];
    [copy setStartTime:[self startTime]];
    [copy setHasQueued:[self hasQueued]];
    [copy setPausedTime:[self pausedTime]];
    [copy setPostDate:[self postDate]];
    [copy setLastPlayed:[self lastPlayed]];

    return (copy);
}

- (NSString*)description
{
    return ([NSString stringWithFormat:@"<SongData: %p> %@",
        self, [self breif]]);
}

// returns a float value between 0 and 100 indicating how much of the song
// has been played as a percent
- (NSNumber *)percentPlayed
{
    //ScrobLog(SCROB_LOG_VERBOSE, @"duration played: %f", -[[self startTime] timeIntervalSinceNow] + 10 );

    // The amount of time passed since the song started, divided by the duration of the song
    // times 100 to generate a percentage.
    NSNumber * percentage = [NSNumber numberWithDouble:(([[self position] doubleValue] / [[self duration] doubleValue]) * 100)];

    return percentage;
}

// returns the amount of time, in seconds, that the song has been playing.
- (NSNumber *)timePlayed
{
    // The amount of time passed since the beginning of the track, made
    // into a positive number, and plus 5 to account for Timer error.
    // Due to timer firing discrepencies, this should not be considered an 'exact' time.
    NSNumber * time = [NSNumber numberWithDouble:(-[[self startTime]
        timeIntervalSinceNow] + 5)];
    return time;
}

- (BOOL)isEqualToSong:(SongData*)song
{
    return ([[self title] isEqualToString:[song title]] &&
             [[self artist] isEqualToString:[song artist]] && 
             [[self album] isEqualToString:[song album]]);
}

- (NSString*)breif
{
    return ([NSString stringWithFormat:@"%@, %@, %@",
        [self title], [self album], [self artist]]);
}

- (NSComparisonResult) compareSongPostDate:(SongData*)song
{
    return ([[self postDate] compare:[song postDate]]);
}

// This is a dump of /dev/urandom
#define SD_MAGIC [NSNumber numberWithUnsignedInt:0xae0da1b7]
#define SD_KEY_MAGIC @"SDM"
#define SD_KEY_TITLE @"Title"
#define SD_KEY_ALBUM @"Ablum"
#define SD_KEY_ARTIST @"Artist"
#define SD_KEY_INDEX @"Track Index"
#define SD_KEY_PLAYLIST @"Playlist ID"
#define SD_KEY_DURATION @"Duration"
#define SD_KEY_PATH @"Path"
#define SD_KEY_POST @"Post Time"
#define SD_KEY_LASTPLAYED @"Last Played"
#define SD_KEY_STARTTIME @"Start Time"
- (NSDictionary*)songData
{
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
        [self title], SD_KEY_TITLE,
        [self album], SD_KEY_ALBUM,
        [self artist], SD_KEY_ARTIST,
        [self trackIndex], SD_KEY_INDEX,
        [self playlistIndex], SD_KEY_PLAYLIST,
        [self duration], SD_KEY_DURATION,
        [self path], SD_KEY_PATH,
        [self postDate], SD_KEY_POST,
        [self lastPlayed], SD_KEY_LASTPLAYED,
        [self startTime], SD_KEY_STARTTIME,
        SD_MAGIC, SD_KEY_MAGIC,
        nil];
    return (d);
}

- (BOOL)setSongData:(NSDictionary*)data
{
    if ([SD_MAGIC isEqualToNumber:[data objectForKey:SD_KEY_MAGIC]]) {
        [self setTitle:[data objectForKey:SD_KEY_TITLE]];
        [self setAlbum:[data objectForKey:SD_KEY_ALBUM]];
        [self setArtist:[data objectForKey:SD_KEY_ARTIST]];
        [self setTrackIndex:[data objectForKey:SD_KEY_INDEX]];
        [self setPlaylistIndex:[data objectForKey:SD_KEY_PLAYLIST]];
        [self setDuration:[data objectForKey:SD_KEY_DURATION]];
        [self setPath:[data objectForKey:SD_KEY_PATH]];
        [self setPostDate:[data objectForKey:SD_KEY_POST]];
        [self setLastPlayed:[data objectForKey:SD_KEY_LASTPLAYED]];
        if ([data objectForKey:SD_KEY_STARTTIME])
            [self setStartTime:[data objectForKey:SD_KEY_STARTTIME]];
        return (YES);
    }
    
    return (NO);
}

////// Accessors Galore ///////

// trackIndex is the number corresponding to the track within the playlist
- (NSNumber *)trackIndex
{
    return trackIndex;
}

- (void)setTrackIndex:(NSNumber *)newTrackIndex
{
    [newTrackIndex retain];
    [trackIndex release];
    trackIndex = newTrackIndex;
}

// playlistIndex is the number corresponding to the playlist the track is in
- (NSNumber *)playlistIndex
{
    return playlistIndex;
}

- (void)setPlaylistIndex:(NSNumber *)newPlaylistIndex
{
    [newPlaylistIndex retain];
    [playlistIndex release];
    playlistIndex = newPlaylistIndex;
}

// title is the title of the song
- (NSString *)title
{
    return title;
}

- (void)setTitle:(NSString *)newTitle
{
    [newTitle retain];
    [title release];
    title = newTitle;
}

// duration is the length of the song in seconds
- (NSNumber *)duration
{
    return duration;
}

- (void)setDuration:(NSNumber *)newDuration
{
    [newDuration retain];
    [duration release];
    duration = newDuration;
}

// position is the current track position within the song
- (NSNumber *)position
{
    return position;
}

- (void)setPosition:(NSNumber *)newPosition
{
    [newPosition retain];
    position = newPosition;
}

// artist is the artist of the track
- (NSString *)artist
{
    return artist;
}

- (void)setArtist:(NSString *)newArtist
{
    [newArtist retain];
    [artist release];
    artist = newArtist;
}

// album is the album of the track
- (NSString *)album
{
    return album;
}

- (void)setAlbum:(NSString *)newAlbum
{
    [newAlbum retain];
    [album release];
    album = newAlbum;
}

// path is the filesystem path of the track
- (NSString *)path
{
    return path;
}

- (void)setPath:(NSString *)newPath
{
    [newPath retain];
    [path release];
    path = newPath;
}

// startTime is the system time at which the track began playing
- (NSDate *)startTime
{
    return startTime;
}

- (void)setStartTime:(NSDate *)newStartTime
{
    [newStartTime retain];
    [startTime release];
    startTime = newStartTime;
}

// hasQueued is a bool value indicating whether the song has been queued or not
- (BOOL)hasQueued
{
    return hasQueued;
}

- (void)setHasQueued:(BOOL)newHasQueued
{
    if(newHasQueued)
        hasQueued = YES;
    else
        hasQueued = NO;
}

// pausedTime is the total length of time the song has been paused for
- (NSNumber *)pausedTime
{
    return pausedTime;
}

- (void)setPausedTime:(NSNumber *)newPausedTime
{
    [newPausedTime retain];
    [pausedTime release];
    pausedTime = newPausedTime;
}

// postDate is the moment in which the initial submission was attempted
- (NSDate *)postDate
{
    return postDate;
}

- (void)setPostDate:(NSDate *)newPostDate
{
    [newPostDate retain];
    [postDate release];
    postDate = newPostDate;
}

- (NSDate *)lastPlayed
{
    return lastPlayed;
}

- (void)setLastPlayed:(NSDate *)date
{
    if (date) {
        [date retain];
        [lastPlayed release];
        lastPlayed = date;
    }
}

- (NSNumber*)rating
{
    return (rating);
}

- (void)setRating:(NSNumber*)newRating
{
    [newRating retain];
    [rating release];
    rating = newRating;
}

- (NSNumber*)scaledRating
{
    return  ([NSNumber numberWithInt:[rating intValue] / 20]);
}

- (NSString*)starRating
{
    int r = [[self scaledRating] intValue];
    NSMutableString *stars = [NSMutableString string];
    
    int i;
    for (i = 0; i < r; ++i) {
        [stars appendFormat:@"%C", 0x2605 /* unicode star */];
    }
    
    return (stars);
}

- (NSNumber*)songID
{
    return ([NSNumber numberWithUnsignedInt:songID]);
}

- (BOOL)hasSeeked
{
    return (hasSeeked);
}

- (void)setHasSeeked
{
// This is broken by pausing the song -- need to work something out
#if 0
    float pos = [position floatValue];
    //NSDate *now = [NSDate date];
    double delta = round([lastPlayed timeIntervalSince1970] - [startTime timeIntervalSince1970]);
    
    if (!hasSeeked && startTime && (pos < delta || pos > (delta + songTimeFudge)))
        hasSeeked = YES;
#endif
}

- (void)dealloc
{
    [trackIndex release];
    [playlistIndex release];
    [title release];
    [duration release];
    [position release];
    [artist release];
    [album release];
    [path release];
    [startTime release];
    [postDate release];
    [lastPlayed release];
    [super dealloc];
}    

@end

@implementation SongData (SongDataComparisons)

- (BOOL)hasPlayedAgain:(SongData*)song
{
    return ( [self isEqualToSong:song] &&
             // And make sure the duration is valid
             [[song lastPlayed] timeIntervalSince1970] >
             ([[self lastPlayed] timeIntervalSince1970] + [[song duration] doubleValue]) );
}

@end
