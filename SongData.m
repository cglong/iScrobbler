//
//  SongData.m
//  iScrobbler
//
//  Created by Sam Ley on Thu Mar 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "SongData.h"

@implementation SongData

- (id)init
{
    [super init];

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
    return ([NSString stringWithFormat:@"<SongData: %p> %@, %@, %@",
        self, [self title], [self album], [self artist]]);
}

// returns a float value between 0 and 100 indicating how much of the song
// has been played as a percent
- (NSNumber *)percentPlayed
{
    //NSLog(@"duration played: %f", -[[self startTime] timeIntervalSinceNow] + 10 );

    // The amount of time passed since the song started, divided by the duration of the song
    // times 100 to generate a percentage.
    NSNumber * percentage = [NSNumber numberWithDouble:(([[self timePlayed] doubleValue] / [[self duration] doubleValue]) * 100)];

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

// returns an NSMutableDictionary object that is packaged and ready for submission.
// postDict adds URL escaped title, artist and filename, and duration and time of
// submission field.
// The receiver is still responsible for adding the username, password and version
// fields to the dict.
- (NSMutableDictionary *)postDict: (int)submissionNumber
{
    //NSLog(@"preparing postDict");
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

    // URL escape relevant fields
	NSString * escapedtitle = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[self title], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString * escapedartist = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[self artist], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString * escapedalbum = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[self album], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];
		
    // If the file isn't already in the queue, then assume this is the first real
    // post generation, and create a new postDate. Otherwise, assume we are already
    // in the queue, and that a new postDate isn't necessary.
    if(![self hasQueued]) {
        [self setPostDate:[NSCalendarDate date]];
    }

/*    NSString * escapeddate = [(NSString*) CFURLCreateStringByAddingPercentEscapes(NULL, 	(CFStringRef)[[self postDate] dateWithCalendarFormat:@"%Y-%m-%d %H:%M:%S" 	timeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]], NULL, (CFStringRef)@"&+", 	kCFStringEncodingUTF8) autorelease]; */
    
    // populate the dictionary
    [dict setObject:escapedtitle forKey:[NSString stringWithFormat:@"t[%i]", submissionNumber]];
    [dict setObject:[self duration] forKey:[NSString stringWithFormat:@"l[%i]", submissionNumber]];
    [dict setObject:escapedartist forKey:[NSString stringWithFormat:@"a[%i]", submissionNumber]];
    [dict setObject:escapedalbum forKey:[NSString stringWithFormat:@"b[%i]", submissionNumber]];
    [dict setObject:@"" forKey:[NSString stringWithFormat:@"m[%i]", submissionNumber]];
    [dict setObject:[[self postDate] dateWithCalendarFormat:@"%Y-%m-%d %H:%M:%S" 	timeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]] forKey:[NSString stringWithFormat:@"i[%i]", submissionNumber]];

    // return and autorelease
    //NSLog(@"postDict done");
    return [dict autorelease];
}

- (BOOL)isEqualToSong:(SongData*)song
{
    return ([[self title] isEqualToString:[song title]] &&
             [[self artist] isEqualToString:[song artist]] && 
             [[self album] isEqualToString:[song album]]);
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
    [position release];
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
    [date retain];
    [lastPlayed release];
    lastPlayed = date;
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
