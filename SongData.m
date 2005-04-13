//
//  SongData.m
//  iScrobbler
//
//  Created by Sam Ley on Thu Mar 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <sys/types.h>
#import <sys/sysctl.h>

#import "SongData.h"
#import "ScrobLog.h"
#import "iScrobblerController.h"
#import "KFAppleScriptHandlerAdditionsCore.h"
#import "KFASHandlerAdditions-TypeTranslation.h"

static unsigned int g_songID = 0;
static float songTimeFudge;
static const unichar noRating[6] = {0x2606,0x2606,0x2606,0x2606,0x2606,0};

@implementation SongData

+ (float)songTimeFudge
{
    return (songTimeFudge);
}

+ (void)setSongTimeFudge:(float)fudge
{
    songTimeFudge = fudge;
}

+ (NSString *)notRatedString
{
    static NSString *empty = nil;
    if (!empty)
        empty = [[NSString alloc] initWithCharacters:noRating length:5];
    return (empty);
}

- (id)init
{
    [super init];

    // set the id
    songID = g_songID;
    IncrementAtomic((SInt32*)&g_songID);
    
    // initialize some empty values
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
    SongData *copy = [[[self class] alloc] init];

    [copy setType:[self type]];
    [copy setiTunesDatabaseID:[self iTunesDatabaseID]];
    [copy setArtist:[self artist]];
    [copy setTitle:[self title]];
    [copy setAlbum:[self album]];
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
    return ([NSString stringWithFormat:@"<SongData: %p> %@ (id: %u)",
        self, [self brief], songID]);
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
    return (NSOrderedSame == [[self title] caseInsensitiveCompare:[song title]] &&
             NSOrderedSame == [[self artist] caseInsensitiveCompare:[song artist]] && 
             NSOrderedSame == [[self album] caseInsensitiveCompare:[song album]]);
}

- (NSString*)brief
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
#define SD_KEY_TYPE @"Type"
#define SD_KEY_ITUNES_DB_ID @"iTunes DB ID"
- (NSDictionary*)songData
{
    NSString *ptitle, *palbum, *partist, *ppath;
    NSNumber *pduration, *ptype, *pitunesid;
    NSDate *ppostDate, *plastPlayed, *pstartTime;
    
    ptitle = [self title];
    palbum = [self album];
    partist = [self artist];
    pduration = [self duration];
    ppath = [self path];
    ppostDate = [self postDate];
    plastPlayed = [self lastPlayed];
    pstartTime = [self startTime];
    ptype = [NSNumber numberWithInt:[self type]];
    pitunesid = [NSNumber numberWithInt:[self iTunesDatabaseID]];
    
    if (!ptitle || !partist || !pduration || !ppostDate || !IsTrackTypeValid([self type])) {
        ScrobLog(SCROB_LOG_WARN, @"Can't create peristent song data for '%@'\n", [self brief]);
        return (nil);
    }
    
    if (!pstartTime)
        pstartTime = ppostDate;
    if (!plastPlayed)
        plastPlayed = [pstartTime addTimeInterval:[pduration doubleValue]];
    
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
        SD_MAGIC, SD_KEY_MAGIC,
        ptitle, SD_KEY_TITLE,
        palbum ? palbum : @"", SD_KEY_ALBUM,
        partist, SD_KEY_ARTIST,
        pduration, SD_KEY_DURATION,
        ppath ? ppath : @"", SD_KEY_PATH,
        ppostDate, SD_KEY_POST,
        plastPlayed, SD_KEY_LASTPLAYED,
        pstartTime, SD_KEY_STARTTIME,
        ptype, SD_KEY_TYPE,
        pitunesid, SD_KEY_ITUNES_DB_ID,
        nil];
    return (d);
}

- (BOOL)setSongData:(NSDictionary*)data
{
    NSNumber *magic = [data objectForKey:SD_KEY_MAGIC];
    id obj;
    if (magic && [SD_MAGIC isEqualToNumber:magic]) {
        if ((obj = [data objectForKey:SD_KEY_TITLE]))
            [self setTitle:obj];
        if ((obj = [data objectForKey:SD_KEY_ALBUM]))
            [self setAlbum:obj];
        if ((obj = [data objectForKey:SD_KEY_ARTIST]))
            [self setArtist:obj];
        if ((obj = [data objectForKey:SD_KEY_DURATION]))
            [self setDuration:obj];
        if ((obj = [data objectForKey:SD_KEY_PATH]))
            [self setPath:obj];
        if ((obj = [data objectForKey:SD_KEY_POST]))
            [self setPostDate:obj];
        if ((obj = [data objectForKey:SD_KEY_LASTPLAYED]))
            [self setLastPlayed:obj];
        if ((obj = [data objectForKey:SD_KEY_STARTTIME]))
            [self setStartTime:obj];
        if ((obj = [data objectForKey:SD_KEY_TYPE]))
            [self setType:[obj intValue]];
        if ((obj = [data objectForKey:SD_KEY_ITUNES_DB_ID]))
            [self setiTunesDatabaseID:[obj intValue]];
        return (YES);
    }
    
    return (NO);
}

////// Accessors Galore ///////

- (int)iTunesDatabaseID
{
    return (iTunesDatabaseID);
}

- (void)setiTunesDatabaseID:(int)newID
{
    if (newID >= 0)
        iTunesDatabaseID = newID;
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
    int trackRating = [newRating intValue];
    if (trackRating < 0 || trackRating > 100)
        return;
    
    [newRating retain];
    [rating release];
    rating = newRating;
}

- (NSNumber*)scaledRating
{
    int scaled = rating ? [rating intValue] / 20 : 0;
    return  ([NSNumber numberWithInt:scaled]);
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

- (NSString*)fullStarRating
{
    NSMutableString *stars = [[SongData notRatedString] mutableCopy];
    NSString *fill = [self starRating];
    if ([fill length])
        [stars replaceCharactersInRange:NSMakeRange(0,[fill length]) withString:fill];
    
    return ([stars autorelease]);
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

- (TrackType_t)type
{
    return (trackType);
    
}

- (void)setType:(TrackType_t)newType
{
    if (IsTrackTypeValid(newType))
        trackType = newType;
    else
        trackType = trackTypeUnknown;
}

- (NSNumber*)playlistID
{
    return (playlistID);
}

- (void)setPlaylistID:(NSNumber*)newPlaylistID
{
    if (newPlaylistID != playlistID) {
        (void)[newPlaylistID retain];
        [playlistID release];
        playlistID = newPlaylistID;
    }
}

- (NSString*)sourceName
{
    return (sourceName);
}

- (void)setSourceName:(NSString*)newSourceName
{
    if (newSourceName != sourceName) {
        (void)[newSourceName retain];
        [sourceName release];
        sourceName = newSourceName;
    }
}

#define CXXVIII_MB 0x8000000ULL
- (NSImage*)artwork
{
    static NSMutableDictionary *artworkCache = nil;
    static NSMutableArray *artworkCacheFifo = nil;
    static NSAppleScript *iTunesArtworkScript = nil;
    static unsigned artworkCacheMax = 8;
    static float artworkCacheLookups = 0.0, artworkCacheHits = 0.0;
    
    if (!artworkCache) {
        u_int64_t mem = 0;
        int mib[2] = {CTL_HW, HW_MEMSIZE};
        size_t len = sizeof(mem);
        (void)sysctl(mib, 2, &mem, &len, NULL, 0);
        if (mem > CXXVIII_MB)
            artworkCacheMax *= (unsigned)(mem / CXXVIII_MB);
        
        artworkCache = [[NSMutableDictionary alloc] initWithCapacity:artworkCacheMax];
        artworkCacheFifo = [[NSMutableArray alloc] initWithCapacity:artworkCacheMax];
    }
    
    if (!iTunesArtworkScript) {
        NSURL *url = [NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                    stringByAppendingPathComponent:@"Scripts/iTunesGetArtworkForTrack.scpt"]];
        iTunesArtworkScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:nil];
        if (!iTunesArtworkScript) {
            ScrobLog(SCROB_LOG_CRIT, @"Could not load iTunesGetArtworkForTrack.scpt!\n");
            [[NSApp delegate] showApplicationIsDamagedDialog];
            return (nil);
        }
    }
	
    if (![self playlistID] || ![self sourceName]) {
        ScrobLog(SCROB_LOG_WARN, @"Can't get track artwork '%@' -- missing iTunes library info.", [self brief]);
        return (nil);
    }
    
    NSString *key = [[NSString stringWithFormat:@"%@_%@", [self artist], [self album]] lowercaseString];
    NSImage *image = [artworkCache objectForKey:key];
    artworkCacheLookups += 1.0;
    if (image) {
        artworkCacheHits += 1.0;
        ScrobLog(SCROB_LOG_TRACE, @"Track artwork cache hit. Lookups: %.0f, Hits: %.0f (%.02f%%)",
            artworkCacheLookups, artworkCacheHits, (artworkCacheHits / artworkCacheLookups) * 100.0);
        return (image);
    }
    
    BOOL cache = YES;
    @try {
        image = [iTunesArtworkScript executeHandler:@"GetArtwork" withParameters:[self sourceName],
            [self playlistID], [NSNumber numberWithInt:[self iTunesDatabaseID]], nil];
        (void)[image isValid];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Can't get artwork for '%@' -- script error: %@.", [self brief], exception);
        static NSImage *genericImage = nil;
        if (!genericImage) {
            genericImage = [[NSImage alloc] initWithContentsOfFile:
                [[NSBundle mainBundle] pathForResource:@"CD" ofType:@"png"]];
            [genericImage setName:@"generic"];
        }
        image = genericImage;
        cache = NO; // Don't cache because the user could update the image later.
    }
    
    if (!image)
        return (nil);
    
    if (cache) {
        float misses = artworkCacheLookups - artworkCacheHits;
        ScrobLog(SCROB_LOG_TRACE, @"Track artwork cache miss. Lookups: %.0f, Misses: %.0f (%.02f%%)",
            artworkCacheLookups, misses, (misses / artworkCacheLookups) * 100.0);
        
        // Add to cache
        unsigned count = [artworkCacheFifo count];
        if (count == artworkCacheMax) {
            // Remove oldest entry
            NSString *entry = [artworkCacheFifo peek];
            [artworkCache removeObjectForKey:entry];
            [artworkCacheFifo pop];
        }
        
        [artworkCache setObject:image forKey:key];
        [artworkCacheFifo push:key];
    }
    return (image);
}

- (void)dealloc
{
    [title release];
    [duration release];
    [position release];
    [artist release];
    [album release];
    [path release];
    [startTime release];
    [pausedTime release];
    [postDate release];
    [lastPlayed release];
    [rating release];
    [playlistID release];
    [sourceName release];
    [super dealloc];
}    

@end

@implementation SongData (SongDataComparisons)

- (BOOL)hasPlayedAgain:(SongData*)song
{
    return ( [self isEqualToSong:song] &&
             // And make sure the duration is valid
             [[song startTime] timeIntervalSince1970] >
             ([[self startTime] timeIntervalSince1970] + [[song duration] doubleValue]) );
}

@end
