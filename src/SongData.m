//
//  SongData.m
//  iScrobbler
//
//  Created by Sam Ley on Thu Mar 20 2003.
//  Major re-write in 2005 by Brian Bergstrand.
//  Copyright (c) 2005-2008 Brian Bergstrand. All rights reserved.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <sys/types.h>
#import <sys/sysctl.h>

#import "SongData.h"
#import "ScrobLog.h"
#import "iScrobblerController.h"
#import "KFAppleScriptHandlerAdditionsCore.h"
#import "KFASHandlerAdditions-TypeTranslation.h"
#import "MBID.h"
#import "ProtocolManager.h"

static unsigned int g_songID = 0;
static float songTimeFudge;
static const unichar noRating[6] = {0x2606,0x2606,0x2606,0x2606,0x2606,0};
static NSMutableDictionary *artworkCache = nil;
static float artworkCacheLookups = 0.0f, artworkCacheHits = 0.0f;

@interface NSMutableDictionary (SongDataAdditions)
- (NSComparisonResult)compareLastHitDate:(NSMutableDictionary*)entry;
@end

#define SCOREBOARD_ALBUMART_CACHE
#ifdef SCOREBOARD_ALBUMART_CACHE
static NSUInteger artScorePerHit = 12; // For 1 play of an album, this will give a TTL of almost 4hrs
#define SCORBOARD_NET_BOOST 10
#endif

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

+ (void)drainArtworkCache
{
    [artworkCache removeAllObjects];
    artworkCacheLookups = artworkCacheHits = 0.0f;
    ScrobLog(SCROB_LOG_TRACE, @"Artwork cache drained.");
}

- (id)init
{
    [super init];

    iTunes = YES;
    // set the id
    songID = g_songID;
    IncrementAtomic((SInt32*)&g_songID);
    
    // initialize some empty values
    [self setTitle:@""];
    [self setDuration:[NSNumber numberWithInt:0]];
    [self setPosition:[NSNumber numberWithInt:0]];
    [self setArtist:@""];
    [self setAlbum:@""];
    [self setPath:@""];
    [self setPostDate:[NSCalendarDate date]];
    [self setHasQueued:NO];
    [self setPlayCount:[NSNumber numberWithInt:0]];
    [self setRating:[NSNumber numberWithInt:0]];
    [self setPlayerUUID:@""];
    [self setLastFmAuthCode:@""];

    // initialize with current time
    [self setStartTime:[NSDate date]];
    [self setLastPlayed:[NSDate date]];
    [self setPausedTime:[NSNumber numberWithInt:0]];

    return self;
}

// Override copyWithZone so we can return copies of the object.
- (id)copyWithZone: (NSZone *)zone
{
    SongData *copy = [[[self class] allocWithZone:zone] init];

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
    [copy setLoved:(BOOL)loved];
    [copy setBanned:(BOOL)banned];
    [copy setTrackNumber:[self trackNumber]];
    [copy setPlayCount:[self playCount]];
    [copy setYear:[self year]];
    [copy setPlayerUUID:[self playerUUID]];
    [copy setLastFmAuthCode:[self lastFmAuthCode]];
    
    copy->persistentID = [persistentID retain];
    
    copy->iTunes = self->iTunes;
    copy->isLastFmRadio = self->isLastFmRadio;

    return (copy);
}

- (NSString*)description
{
    return ([NSString stringWithFormat:@"<SongData: %p> %@ (id: %u, start=%@, dur=%@, last=%@)",
        self, [self brief], songID, [self startTime], [self duration], [self lastPlayed]]);
}

// returns a float value between 0 and 100 indicating how much of the song
// has been played as a percent
- (NSNumber *)percentPlayed
{
    //ScrobLog(SCROB_LOG_VERBOSE, @"duration played: %f", -[[self startTime] timeIntervalSinceNow] + 10 );

    // The amount of time passed since the song started, divided by the duration of the song
    // times 100 to generate a percentage.
    NSNumber * percentage = [NSNumber numberWithDouble:(([[self elapsedTime] doubleValue] / [[self duration] doubleValue]) * 100)];

    return percentage;
}

// returns the amount of time, in seconds, that the song has been playing.
- (NSNumber *)timePlayed
{
    // The amount of time passed since the beginning of the track, made
    // into a positive number, and plus 5 to account for Timer error.
    // Due to timer firing discrepencies, this should not be considered an 'exact' time.
    NSNumber *delta = [NSNumber numberWithDouble:(-[[self startTime]
        timeIntervalSinceNow] + 5)];
    return (delta);
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

- (NSComparisonResult)compareSongLastPlayedDate:(SongData*)song
{
    return ([[self lastPlayed] compare:[song lastPlayed]]);
}

// This is a dump of /dev/urandom
#define SD_MAGIC 0xae0da1b7
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
#define SD_KEY_MBID @"MBID"
#define SD_KEY_TRACKNUM @"Track Number"
#define SD_KEY_LFMRADIO @"LastFM Radio"
#define SD_KEY_LFMAUTH @"LastFM Auth"
#define SD_KEY_LOVED @"Loved"
#define SD_KEY_SKIPPED @"Skipped"
#define SD_KEY_BANNED @"Banned"
- (NSDictionary*)songData
{
    NSString *ptitle, *palbum, *partist, *ppath, *pmbid;
    NSNumber *pduration, *ptype, *pitunesid, *ptrackNumber;
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
    pitunesid = [NSNumber numberWithUnsignedLongLong:[self iTunesDatabaseID]];
    ptrackNumber = [self trackNumber];
    @try {
        if ((pmbid = [self mbid]) && [pmbid length] == 0)
            pmbid = nil;
    } @catch (NSException *e) {
        pmbid = nil;
    }
    
    if (!ptitle || !partist || !pduration || !ppostDate || !IsTrackTypeValid([self type])) {
        ScrobLog(SCROB_LOG_WARN, @"Can't create peristent song data for '%@'\n", [self brief]);
        return (nil);
    }
    
    if (!pstartTime)
        pstartTime = ppostDate;
    if (!plastPlayed) {
        #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
        plastPlayed = [pstartTime dateByAddingTimeInterval:[pduration doubleValue]];
        #else
        plastPlayed = [pstartTime addTimeInterval:[pduration doubleValue]];
        #endif
    }
    
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithUnsignedInt:SD_MAGIC], SD_KEY_MAGIC,
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
        [NSNumber numberWithBool:[self isLastFmRadio]], SD_KEY_LFMRADIO,
        [NSNumber numberWithBool:[self loved]], SD_KEY_LOVED,
        [NSNumber numberWithBool:[self skipped]], SD_KEY_SKIPPED,
        [NSNumber numberWithBool:[self banned]], SD_KEY_BANNED,
        [self lastFmAuthCode], SD_KEY_LFMAUTH,
        ptrackNumber, SD_KEY_TRACKNUM,
        pmbid, SD_KEY_MBID,
        nil];
    return (d);
}

- (BOOL)setSongData:(NSDictionary*)data
{
    NSNumber *magic = [data objectForKey:SD_KEY_MAGIC];
    id obj;
    if (magic && SD_MAGIC == [magic unsignedIntValue]) {
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
        else
            [self setType:trackTypeFile]; // If missing, then we are upgrading from a pre-1.1 version
        if ((obj = [data objectForKey:SD_KEY_ITUNES_DB_ID]))
            [self setiTunesDatabaseID:[obj unsignedLongLongValue]];
        if ((obj = [data objectForKey:SD_KEY_MBID]))
            [self setMbid:obj];
        if ((obj = [data objectForKey:SD_KEY_TRACKNUM]))
            [self setTrackNumber:obj];
        // 2.0 radio support
        if ((obj = [data objectForKey:SD_KEY_LFMRADIO]))
            isLastFmRadio = [obj boolValue];
        if ((obj = [data objectForKey:SD_KEY_LOVED]))
            [self setLoved:[obj boolValue]];
        if ((obj = [data objectForKey:SD_KEY_SKIPPED]))
            [self setSkipped:[obj boolValue]];
        if ((obj = [data objectForKey:SD_KEY_BANNED]))
            [self setBanned:[obj boolValue]];
        if ((obj = [data objectForKey:SD_KEY_LFMAUTH]))
            [self setLastFmAuthCode:obj];
        reconstituted = YES;
        return (YES);
    }
    
    return (NO);
}

////// Accessors Galore ///////

- (BOOL)isPlayeriTunes
{
    return (iTunes);
}

- (void)setIsPlayeriTunes:(BOOL)val
{
    iTunes = val;
}

- (u_int64_t)iTunesDatabaseID
{
    return (iTunesDatabaseID);
}

- (void)setiTunesDatabaseID:(u_int64_t)newID
{
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

- (void)didPause
{
    [self setLastPlayed:[NSDate date]];
    isPaused = 1;
}

- (BOOL)isPaused
{
    return (isPaused);
}

- (void)didResumeFromPause
{
    NSTimeInterval elapsed = [[self lastPlayed] timeIntervalSinceNow];
    if (elapsed < 0.0) { // should never have a future time
        elapsed = floor(fabs(elapsed)) + [[self pausedTime] floatValue];
        [self setPausedTime:[NSNumber numberWithDouble:elapsed]];
    }
    isPaused = 0;
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
    int r = [[self rating] intValue];
    int partial = r % 20;
    r /= 20;
    NSMutableString *stars = [NSMutableString string];
    
    int i;
    for (i = 0; i < r; ++i) {
        [stars appendFormat:@"%C", 0x2605 /* unicode star */];
    }
    if (10 == partial)
        [stars appendFormat:@"%C", 0x00bd /* unicode 1/2 */];
    
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

- (BOOL)reconstituted
{
    return (reconstituted);
}

- (void)setReconstituted:(BOOL)newValue
{
    reconstituted = newValue;
}

- (NSString*)genre
{
    return (genre);
}

- (void)setGenre:(NSString*)newGenre
{
    if (newGenre != genre) {
        (void)[newGenre retain];
        [genre release];
        genre = newGenre;
    }
}

- (NSNumber*)elapsedTime
{    
    NSNumber *zero = [NSNumber numberWithDouble:0.0];
    NSTimeInterval elapsed = [[self startTime] timeIntervalSinceNow];
    if (elapsed > 0.0) // We should never have a future value
        return (zero);
    NSNumber *n = [NSNumber numberWithDouble:floor(fabs(elapsed)) - [[self pausedTime] floatValue]];
    
    if ([n floatValue] < 0.0) {
        // This can happen if the song is scrubbed back to the beginning and the pause time is > 0
        [self setPausedTime:zero];
        n = zero;
    } else {
        NSNumber *myDuration = [self duration];
        if ([n isGreaterThan:myDuration])
            n = myDuration;
    }
    return (n);
}

#define KEY_LAST_HIT @"last hit"
#define KEY_IMAGE @"image"
#define MakeAlbumCacheKey() ([[NSString stringWithFormat:@"%@_%@", [self artist], [self album]] lowercaseString])
#ifdef SCOREBOARD_ALBUMART_CACHE
+ (void)scanArtworkCache
{
    NSMutableArray *rem = [NSMutableArray array];
    
    NSMutableDictionary *d;
    NSString *key;
    NSEnumerator *en = [artworkCache keyEnumerator];
    int score;
    NSNull *null = [NSNull null];
    while ((key = [en nextObject])) {
        if ([(d = [artworkCache objectForKey:key]) isEqualTo:null])
            continue;
        
        score = [[d objectForKey:@"score"] unsignedIntValue];
        if (!score) {
            [rem addObject:key];
            ScrobLog(SCROB_LOG_TRACE,
                #ifndef ISDEBUG
                @"Scoreboard cache: Removed %@. Last hit was %@.",
                #else
                @"Scoreboard cache: Removed %@ which entered at %@. Last hit was %@.",
                #endif
                key,
                #ifdef ISDEBUG
                [d objectForKey:@"entryDate"],
                #endif
                [d objectForKey:KEY_LAST_HIT]);
            continue;
        }
        
        [d setObject:[NSNumber numberWithUnsignedInt:score-1] forKey:@"score"];
    }
    
    [artworkCache removeObjectsForKeys:rem];
}
#endif

- (void)cacheArtwork:(NSImage*)art withScore:(NSInteger)score
{
    float misses = artworkCacheLookups - artworkCacheHits;
    ScrobLog(SCROB_LOG_TRACE, @"Artwork cache miss. Lookups: %.0f, Misses: %.0f (%.02f%%)",
        artworkCacheLookups, misses, (misses / artworkCacheLookups) * 100.0);
    
    // Add to cache
#ifndef SCOREBOARD_ALBUMART_CACHE
    unsigned count = [artworkCache count];
    if (count == artworkCacheMax) {
        // Remove oldest entry
        NSString *remKey = [[artworkCache keysSortedByValueUsingSelector:@selector(compareLastHitDate:)]
            objectAtIndex:0];
        [artworkCache removeObjectForKey:remKey];
        ScrobLog(SCROB_LOG_TRACE, @"Artwork '%@' removed from cache.", remKey);
    }
#endif
    
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        art, KEY_IMAGE,
        [NSDate date], KEY_LAST_HIT,
#ifdef SCOREBOARD_ALBUMART_CACHE
        [NSNumber numberWithLongLong:score], @"score",
        #ifdef ISDEBUG
        [NSDate date], @"entryDate",
        #endif
#endif
        nil];
    [artworkCache setObject:entry forKey:MakeAlbumCacheKey()];
}

- (NSImage*)artwork
{
    static NSAppleScript *iTunesArtworkScript = nil;
    static NSInteger artworkCacheMax;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IgnoreArtwork"])
        return (nil);
    
    if (!artworkCache) {
#ifdef SCOREBOARD_ALBUMART_CACHE
        artworkCache = [[NSMutableDictionary alloc] init];
        artworkCacheMax = [[NSUserDefaults standardUserDefaults] integerForKey:@"AlbumArtCacheScore"];
        if (artworkCacheMax > 1 && artworkCacheMax < 50)
            artScorePerHit = artworkCacheMax;
        artworkCacheMax = INT_MAX;
        [NSTimer scheduledTimerWithTimeInterval:(float)artScorePerHit * 1.5f * 60
            target:[SongData class] selector:@selector(scanArtworkCache) userInfo:nil repeats:YES];
#else
        if ((artworkCacheMax = [[NSUserDefaults standardUserDefaults] integerForKey:@"Artwork Cache Size"]) < 8) {
            u_int64_t mem = 0;
            int mib[2] = {CTL_HW, HW_MEMSIZE};
            size_t len = sizeof(mem);
            (void)sysctl(mib, 2, &mem, &len, NULL, 0);
            artworkCacheMax = 8;
            if (mem > 0x8000000ULL /*128 MB*/) {
                if (mem > 0xc0000000ULL /*3 GB or 168 cache slots */)
                    mem = 0xc0000000ULL;
                artworkCacheMax *= (unsigned)(mem / 0x8000000ULL);
            }
        }
        
        artworkCache = [[NSMutableDictionary alloc] initWithCapacity:artworkCacheMax];
#endif        
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
    
    NSString* const key = MakeAlbumCacheKey();
    NSMutableDictionary *entry = [artworkCache objectForKey:key];
    NSImage *image;
    artworkCacheLookups += 1.0f;
    if (entry && [entry isNotEqualTo:[NSNull null]]) {
        artworkCacheHits += 1.0f;
        image = [entry objectForKey:KEY_IMAGE];
        [entry setObject:[NSDate date] forKey:KEY_LAST_HIT];
#ifdef SCOREBOARD_ALBUMART_CACHE
        unsigned score = [[entry objectForKey:@"score"] unsignedIntValue] + (unsigned)artScorePerHit;
        [entry setObject:[NSNumber numberWithUnsignedInt:score] forKey:@"score"];
#endif
        ScrobLog(SCROB_LOG_TRACE, @"Artwork cache hit. Lookups: %.0f (%lu/%ld), Hits: %.0f (%.02f%%)",
            artworkCacheLookups, [artworkCache count], artworkCacheMax, artworkCacheHits,
            (artworkCacheHits / artworkCacheLookups) * 100.0);
        return (image);
    }
    
    BOOL cache = YES;
    static NSImage *genericImage = nil;
    if (!genericImage) {
        genericImage = [[NSImage imageNamed:@"no_album"] retain];
        [genericImage setName:@"generic"];
    }
    @try {
        image = genericImage;
        cache = NO; // Don't cache the generic image because the user could update the image later.
        if (trackTypeFile == [self type] || trackTypeShared == [self type]) {
            // shared library artwork is supported for the currently playing track only
            NSString *source = [self sourceName];
            if (!source)
                source = @"";
            image = [iTunesArtworkScript executeHandler:@"GetArtwork" withParameters:source,
                [self artist], [self album], nil];
            if (image && !([image isEqual:[NSNull null]])) {
                if ([image isValid])
                    cache = YES;
            } else
                image = genericImage;
        }
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Can't get artwork for '%@' -- script error: %@.",
            [self brief], exception);
        image = genericImage;
        cache = NO;
    }
    
    if (!image)
        return (nil);
    
    if (cache) {
        [self cacheArtwork:image withScore:
            (trackTypeShared != [self type]) ? artScorePerHit : artScorePerHit * (SCORBOARD_NET_BOOST/2)];
    }
    return (image);
}

- (BOOL)isPodcast
{
    return (isPodcast);
}

- (void)setIsPodcast:(BOOL)podcast
{
    isPodcast = podcast;
}

- (NSString*)comment
{
    return (comment);
}

- (void)setComment:(NSString*)commentArg
{
    if (commentArg != comment) {
        [comment release];
        comment = [commentArg retain];
    }
}

- (NSString*)mbid
{
    if (!mbid) {
        // Since there is no OS X MB tagger that alters the file, search comments for our own MBID format
        NSString *str = [self comment];
        if (str) {
            NSRange start = [str rangeOfString:@"[MBID]" options:NSCaseInsensitiveSearch]; 
            NSRange end = [str rangeOfString:@"[/MBID]" options:NSCaseInsensitiveSearch];
            if (NSNotFound != start.location && NSNotFound != end.location) {
                start.location += 6; // length of [MBID]
                if (36 == (start.length = end.location - start.location)
                    && (mbid = [[str substringWithRange:start] retain])) {
                    [self setComment:nil]; // we no longer need the comment
                } else
                    ScrobLog(SCROB_LOG_WARN, @"Comment '%@' for '%@' contains an invalid MBID defintion of length %lu.",
                        str, [self brief], start.length);
            }
        }
        
        NSString *fpath = [self path];
        if (fpath && [fpath length] > 0 && !mbid
            && [[NSUserDefaults standardUserDefaults] boolForKey:@"CheckForFileMBIDs"]) {
            char data[MBID_BUFFER_SIZE];
            if (0 == getMBID([fpath fileSystemRepresentation], data)) {
                mbid = [[NSString alloc] initWithUTF8String:data];
            }
        }
        
        if (mbid)
            ScrobLog(SCROB_LOG_TRACE, @"MBID <%@> found for %@.\n", mbid, [self brief]);
        
    }
    return (mbid ? mbid : @"");
}

- (void)setMbid:(NSString*)newMBID
{
    if (newMBID != mbid && 36 == [newMBID length]) {
        [mbid release];
        mbid = [newMBID retain];
    }
}

- (NSNumber*)playCount
{
    return (playCount);
}

- (void)setPlayCount:(NSNumber*)count
{
    if (count && playCount != count) {
        [playCount release];
        playCount = [count retain];
    }
}

- (NSString*)playerUUID
{
    return (playerUUID);
}

- (void)setPlayerUUID:(NSString*)uuid
{
    if (uuid && uuid != playerUUID) {
        [playerUUID release];
        playerUUID = [uuid retain];
    }
}

- (BOOL)ignore
{
    static NSSet *filters = nil;
    static BOOL load = YES;
    
    if (passedFilters)
        return (NO);
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IgnorePodcasts"] &&
            [self isPodcast]) {
        return (YES);
    }
    
    if (!filters && load) {
        filters = [[NSSet alloc] initWithArray:
            [[NSUserDefaults standardUserDefaults] arrayForKey:@"Track Filters"]];
        load = NO;
    }
    
    BOOL ignoreMe = NO;
    if (filters) {
        NSString *tmp = [self genre], *match;
        if ((match = [filters member:[self artist]]) || (tmp && [tmp length] && (match = [filters member:tmp]))) {
            ignoreMe = YES;
        } else if ((tmp = [self path]) && [tmp length] && '/' == [tmp characterAtIndex:0]) {
            // Path matching
            do {
                if ((match = [filters member:tmp])) {
                    ignoreMe = YES;
                    break;
                }
                // Get the parent dir and try again
                tmp = [tmp stringByDeletingLastPathComponent];
            } while (![tmp isEqualToString:@"/"]);
        }
        
        if (!ignoreMe)
            passedFilters = YES; // No need to test again if this song passes once.
        else
            ScrobLog(SCROB_LOG_TRACE, @"Song '%@' matched filter '%@'.\n", [self brief], match);
    }
    
    return (ignoreMe);
}

- (NSString*)uuid
{
    if (![self isLastFmRadio]) {
        NSString *puuid = [[NSApp delegate] playerLibraryUUID];
        NSString *suuid = [self playerUUID];
        if (puuid && [suuid length] > 0) {
            return ([puuid stringByAppendingString:suuid]);
        }
    }
    
    return (nil);
}

- (BOOL)loved
{
    return (loved);
}

- (void)setLoved:(BOOL)isLoved
{
    loved = isLoved;
    
    if (banned && isLoved) {
        NSString *uuid;
        banned = NO;
        if ((uuid = [self uuid])) {
            NSMutableDictionary *d;
            d = [[[[NSUserDefaults standardUserDefaults] objectForKey:@"BannedSongs"] mutableCopy] autorelease];
            [d removeObjectForKey:uuid];
            [[NSUserDefaults standardUserDefaults] setObject:d forKey:@"BannedSongs"];
            ScrobLog(SCROB_LOG_TRACE, @"Song '%@' has been un-banned (uuid: %@)", [self brief], uuid);
        }
    }
}

- (BOOL)banned
{
    NSString *uuid;
    if (!banned && (uuid = [self uuid])) {
        banned = (nil != [[[NSUserDefaults standardUserDefaults] objectForKey:@"BannedSongs"] objectForKey:uuid]);
    }
    return (banned);
}

- (void)setBanned:(BOOL)isBanned
{
    if (banned != isBanned) {
        NSString *uuid;
        if ((uuid = [self uuid])) {
            NSMutableDictionary *d;
            d = [[[[NSUserDefaults standardUserDefaults] objectForKey:@"BannedSongs"] mutableCopy] autorelease];
            if (isBanned && nil == [d objectForKey:uuid]) {
                [d setObject:[self brief] forKey:uuid];
                [[NSUserDefaults standardUserDefaults] setObject:d forKey:@"BannedSongs"];
                ScrobLog(SCROB_LOG_TRACE, @"Song '%@' has been banned (uuid: %@)", [self brief], uuid);
            } else if (!isBanned) {
                [d removeObjectForKey:uuid];
                [[NSUserDefaults standardUserDefaults] setObject:d forKey:@"BannedSongs"];
                ScrobLog(SCROB_LOG_TRACE, @"Song '%@' has been un-banned (uuid: %@)", [self brief], uuid);
            }
        }
        banned = isBanned;
    }
}

- (BOOL)skipped
{
    return (skipped);
}

- (void)setSkipped:(BOOL)isSkipped
{
    skipped = isSkipped;
}

- (BOOL)isLastFmRadio
{
    return (isLastFmRadio);
}

- (NSString*)lastFmAuthCode
{
    return (lastFmAuthCode);
}

- (void)setLastFmAuthCode:(NSString*)code
{
    if (!code)
        code = @"";
    (void)[code retain];
    [lastFmAuthCode release];
    lastFmAuthCode = code;
}

- (NSNumber*)trackNumber
{
    return ([NSNumber numberWithUnsignedInt:trackNumber]);
}

- (void)setTrackNumber:(NSNumber*)number
{
    trackNumber = [number unsignedIntValue];
}

- (NSNumber*)year
{
    return (year);
}

- (void)setYear:(NSNumber*)newYear
{
    (void)[newYear retain];
    [year release];
    year = newYear;
}

- (void)loadAlbumArtFromURL:(NSURL*)url
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IgnoreArtwork"] || [artworkCache objectForKey:MakeAlbumCacheKey()])
        return;
    
    ISASSERT(conn == nil, "conn is still active!");
    // set a placeholder so no other object attempts to download the image
    [artworkCache setObject:[NSNull null] forKey:MakeAlbumCacheKey()];
    
     NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    conn = [[NSURLConnection connectionWithRequest:req delegate:self] retain];
    ScrobDebug(@"loading", MakeAlbumCacheKey());
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (!albumArtData) {
        albumArtData = [[NSMutableData alloc] initWithData:data];
    } else {
        [albumArtData appendData:data];
    }
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)reason
{
    ScrobLog(SCROB_LOG_TRACE, @"Connection failure: %@\n", reason);
    [artworkCache removeObjectForKey:MakeAlbumCacheKey()]; // remove the placeholder
    [albumArtData release];
    albumArtData = nil;
    [conn autorelease];
    conn = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [conn autorelease];
    conn = nil;
    NSImage *img = [[[NSImage alloc] initWithData:albumArtData] autorelease];
    if (img) {
        ScrobDebug(@"loaded", MakeAlbumCacheKey());
        [self cacheArtwork:img withScore:artScorePerHit*SCORBOARD_NET_BOOST /*since it's from the net, give it a cache boost*/];
    } else
        [artworkCache removeObjectForKey:MakeAlbumCacheKey()]; // remove the placeholder
}

- (void)dealloc
{
    if (conn) {
        [conn cancel];
        [conn release];
        conn = nil;
        [artworkCache removeObjectForKey:MakeAlbumCacheKey()]; // remove the placeholder
    }
    [albumArtData release];
    
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
    [genre release];
    [comment release];
    [mbid release];
    [playCount release];
    [playerUUID release];
    [year release];
    [lastFmAuthCode release];
    [persistentID release];
    [super dealloc];
}    

@end

@implementation SongData (SongDataComparisons)

- (BOOL)hasPlayedAgain:(SongData*)song
{
    NSTimeInterval songStart = [[song startTime] timeIntervalSince1970];
    NSTimeInterval myStart = [[self startTime] timeIntervalSince1970];
    return ( [self isEqualToSong:song]
             && (fabs(songStart - myStart) >= [SongData songTimeFudge])
             // And make sure the duration is valid
             && (songStart >= (myStart + [[song duration] doubleValue]))
             || (songStart <= (myStart - [[song duration] doubleValue])) );
}

@end

@implementation NSMutableDictionary (SongDataAdditions)

- (NSComparisonResult)compareLastHitDate:(NSMutableDictionary*)entry
{
    return ( [(NSDate*)[self objectForKey:KEY_LAST_HIT] compare:(NSDate*)[entry objectForKey:KEY_LAST_HIT]] );
}

@end
