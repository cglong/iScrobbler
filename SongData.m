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
    [self setPath:@""];

    // initialize with current time
    [self setStartTime:[NSDate date]];

    return self;
}
    
// returns a float value between 0 and 100 indicating how much of the song
// has been played as a percent
- (NSNumber *)percentPlayed
{
    NSNumber * percentage = [[NSNumber alloc] init];

    percentage = [NSNumber numberWithDouble:((-[[self startTime] timeIntervalSinceNow] / [[self duration] 	doubleValue]) *100)];

    return [percentage autorelease];
}

// returns an NSMutableDictionary object that is packaged and ready for submission.
// postDict adds URL escaped title, artist and filename, and duration and time of
// submission field.
// The receiver is still responsible for adding the username, password and version
// fields to the dict.
- (NSMutableDictionary *)postDict
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

    // URL escape relevant fields
    NSString * escapedtitle = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[self title], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString * escapedartist = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[self artist], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString * escapedfilename = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[self path],	NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    // populate the dictionary
    [dict setObject:escapedtitle forKey:@"title"];
    [dict setObject:[self duration] forKey:@"duration"];
    [dict setObject:escapedartist forKey:@"artist"];
    [dict setObject:escapedfilename forKey:@"filename"];
    [dict setObject:[[NSCalendarDate date] descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"] 	forKey:@"time"];

    // return and autorelease
    return [dict autorelease];
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

- (void)dealloc
{
    [trackIndex release];
    [playlistIndex release];
    [title release];
    [duration release];
    [position release];
    [artist release];
    [path release];
    [startTime release];
    [super dealloc];
}    

@end
