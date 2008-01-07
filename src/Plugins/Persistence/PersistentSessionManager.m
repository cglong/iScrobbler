//
//  PersistentSessionManager.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/17/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import "PersistentSessionManager.h"
#import "Persistence.h"
#import "ISThreadMessenger.h"
#import "SongData.h"

@interface SongData (PersistentAdditions)
- (NSPredicate*)matchingPredicate:(NSString**)albumTitle;
- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc;
@end

@interface PersistentProfile (Private)
+ (PersistentProfile*)sharedInstance;

- (BOOL)save:(NSManagedObjectContext*)moc withNotification:(BOOL)notify;
- (BOOL)save:(NSManagedObjectContext*)moc;
- (void)resetMain;
- (void)setImportInProgress:(BOOL)import;
- (NSManagedObjectContext*)mainMOC;
- (void)addSongPlaysDidFinish:(id)obj;
- (id)storeMetadataForKey:(NSString*)key moc:(NSManagedObjectContext*)moc;
@end

@implementation PersistentSessionManager

- (NSArray*)activeSessionsWithMOC:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (archive == NULL)", ITEM_SESSION]];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
    
    [[moc persistentStoreCoordinator] lock];
    NSArray *results = [moc executeFetchRequest:request error:&error];
    [[moc persistentStoreCoordinator] unlock];
    return (results);
}

- (NSArray*)archivedSessionsWithMOC:(NSManagedObjectContext*)moc weekLimit:(NSUInteger)limit
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    NSPredicate *predicate;
    if (limit > 0) {
        NSCalendarDate *now = [NSCalendarDate date];
        // just before midnight of the first day of the current week
        NSCalendarDate *fromDate = [now dateByAddingYears:0 months:0 days:-((limit * 7) + [now dayOfWeek])
            hours:-([now hourOfDay]) minutes:-([now minuteOfHour]) seconds:-([now secondOfMinute] - 10)];
        predicate = [NSPredicate predicateWithFormat:@"(itemType == %@) AND (archive != NULL) AND (epoch > %@)",
            ITEM_SESSION, [fromDate GMTDate]];
    } else
        predicate = [NSPredicate predicateWithFormat:@"(itemType == %@) AND (archive != NULL)", ITEM_SESSION];
    [request setPredicate:predicate];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
    
    [[moc persistentStoreCoordinator] lock];
    NSArray *results = [moc executeFetchRequest:request error:&error];
    [[moc persistentStoreCoordinator] unlock];
    return (results);
}

- (NSManagedObject*)sessionWithName:(NSString*)name moc:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType = %@) AND (name == %@)",
        ITEM_SESSION, name]];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
    
    [[moc persistentStoreCoordinator] lock];
    NSArray *result = [moc executeFetchRequest:request error:&error];
    [[moc persistentStoreCoordinator] unlock];
    if (1 != [result count]) {
        if ([result count] > 0) {
            ISASSERT(0, "multiple sessions!");
            @throw ([NSException exceptionWithName:NSInternalInconsistencyException reason:@"multiple sessions with same name!" userInfo:nil]);
        } else
            ScrobLog(SCROB_LOG_TRACE, @"persistent session '%@' not found!", name);
        return (nil);
    }
    
    return ([result objectAtIndex:0]);
}

- (NSArray*)artistsForSession:(id)session moc:(NSManagedObjectContext*)moc
{
    NSError *error;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionArtist" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@)",
            ITEM_ARTIST, [session valueForKey:@"name"]]];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
    return ([moc executeFetchRequest:request error:&error]);
}

- (NSArray*)albumsForSession:(id)session moc:(NSManagedObjectContext*)moc
{
    NSError *error;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionAlbum" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@)",
            ITEM_ALBUM, [session valueForKey:@"name"]]];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
    return ([moc executeFetchRequest:request error:&error]);
}

- (NSManagedObject*)cacheForRating:(id)rating inSession:(NSManagedObject*)session moc:(NSManagedObjectContext*)moc
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:[NSEntityDescription entityForName:@"PRatingCache" inManagedObjectContext:moc]];
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@) AND (rating == %@)",
            ITEM_RATING_CCH, [session valueForKey:@"name"], rating]];
    
    NSError *error;
    NSArray *result = [moc executeFetchRequest:request error:&error];
    if (1 == [result count]) {
        return ([result objectAtIndex:0]);
    } else if ([result count] > 0) {
        ISASSERT(0, "multiple rating caches found in session!");
        @throw ([NSException exceptionWithName:NSInternalInconsistencyException reason:@"multiple session ratings!" userInfo:nil]);
    }
    return (nil);
}

- (NSManagedObject*)cacheForHour:(id)hour inSession:(NSManagedObject*)session moc:(NSManagedObjectContext*)moc
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:[NSEntityDescription entityForName:@"PHourCache" inManagedObjectContext:moc]];
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@) AND (hour == %@)",
            ITEM_HOUR_CCH, [session valueForKey:@"name"], hour]];
    
    NSError *error;
    NSArray *result = [moc executeFetchRequest:request error:&error];
    if (1 == [result count]) {
         return ([result objectAtIndex:0]);
    } else if ([result count] > 0) {
        ISASSERT(0, "multiple hour caches found in session!");
        @throw ([NSException exceptionWithName:NSInternalInconsistencyException reason:@"multiple session hours!" userInfo:nil]);
    }
    return (nil);
}

- (void)sessionManagerThread:(id)mainProfile
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] init];
    [moc setUndoManager:nil];
    [moc setPersistentStoreCoordinator:[[mainProfile mainMOC] persistentStoreCoordinator]];
    double pri = [NSThread threadPriority];
    [NSThread setThreadPriority:pri - (pri * 0.20)];
    
    [[[NSThread currentThread] threadDictionary] setObject:moc forKey:@"moc"];
    
    thMsgr = [[ISThreadMessenger scheduledMessengerWithDelegate:self] retain];
    
    lfmUpdateTimer = sUpdateTimer = nil;
    @try {
    [self performSelector:@selector(updateLastfmSession:) withObject:nil];
    [self performSelector:@selector(updateSessions:) withObject:nil];
    [self performSelector:@selector(scrub:) withObject:nil];
    } @catch (NSException *e) {}
    
    do {
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
        @try {
        [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        
        [self performSelector:@selector(scrub:) withObject:nil];
        } @catch (id e) {
            ScrobLog(SCROB_LOG_TRACE, @"[sessionManager:] uncaught exception: %@", e);
        }
    } while (1);
    
    ISASSERT(0, "sessionManager run loop exited!");
    [thMsgr release];
    thMsgr = nil;
    [pool release];
    [NSThread exit];
}

- (void)sessionManagerUpdate
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread mainThread], "wrong thread!");
    #endif
    [self performSelector:@selector(updateLastfmSession:) withObject:nil];
    [self performSelector:@selector(updateSessions:) withObject:nil];
}

// NOTE: For V2 this is only used once during migration from v1
- (void)recreateRatingsCacheForSession:(NSManagedObject*)session songs:(NSArray*)songs moc:(NSManagedObjectContext*)moc
{
#ifdef ISDEBUG
    NSNumber *count = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    NSNumber *ptime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ScrobLog(SCROB_LOG_TRACE, @"-session '%@'- play count: %@, cache count: %@", [session valueForKey:@"name"],
        count, [session valueForKey:@"playCount"]);
    ScrobLog(SCROB_LOG_TRACE, @"-session '%@'- play time: %@, cache time: %@", [session valueForKey:@"name"],
        ptime, [session valueForKey:@"playTime"]);
        
    NSArray *refetchedSongs = [[PersistentProfile sharedInstance] songsForSession:session];
    ISASSERT([refetchedSongs count] == [songs count], "invalid session songs!");
    
    NSNumber *rfcount = [refetchedSongs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    ISASSERT([count unsignedIntValue] == [rfcount unsignedIntValue], "counts don't match!");
    
    NSNumber *rfptime = [refetchedSongs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([ptime unsignedLongLongValue] == [rfptime unsignedLongLongValue], "times don't match!");
    
    ISASSERT([count isEqualTo:[session valueForKey:@"playCount"]], "counts don't match!");
    ISASSERT([ptime isEqualTo:[session valueForKey:@"playTime"]], "times don't match!");
#endif
    
    // Pre-fetch the songs
    NSError *error = nil;
    NSEntityDescription *entity;
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", [songs valueForKeyPath:@"item.objectID"]]];
    error = nil;
    (void)[moc executeFetchRequest:request error:&error];
    
    NSEnumerator *en;
    NSManagedObject *rating;
    NSNumber *zero = [NSNumber numberWithInt:0];
    // Zero our ratings
    en = [[[PersistentProfile sharedInstance] ratingsForSession:session] objectEnumerator];
    while ((rating = [en nextObject])) {
        [rating setValue:zero forKey:@"playCount"];
        [rating setValue:zero forKey:@"playTime"];
    }
    
    en = [songs objectEnumerator];
    NSManagedObject *sessionSong;
    while ((sessionSong = [en nextObject])) {
        NSNumber *sr = [sessionSong valueForKeyPath:@"item.rating"];
        rating = [self cacheForRating:sr inSession:session moc:moc];
        ISASSERT(rating != nil, "missing rating!");
        #if IS_STORE_V2
        [sessionSong setValue:sr forKey:@"rating"];
        #endif
        [rating incrementPlayCount:[sessionSong valueForKey:@"playCount"]];
        [rating incrementPlayTime:[sessionSong valueForKey:@"playTime"]];
    }
    
#ifdef ISDEBUG
    NSArray *ratings = [[PersistentProfile sharedInstance] ratingsForSession:session];
    count = [ratings valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    ptime = [ratings valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([count isEqualTo:[session valueForKey:@"playCount"]], "rating cache counts don't match session total!");
    ISASSERT([ptime isEqualTo:[session valueForKey:@"playTime"]], "rating cache times don't match session total!");
#endif    
}

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
- (void)recreateHourCacheForSession:(NSManagedObject*)session songs:(NSArray*)songs moc:(NSManagedObjectContext*)moc
{
    NSEnumerator *en;
    NSManagedObject *hourCache;
    NSNumber *zero = [NSNumber numberWithInt:0];
    // Zero our ratings
    en = [[[PersistentProfile sharedInstance] hoursForSession:session] objectEnumerator];
    while ((hourCache = [en nextObject])) {
        [hourCache setValue:zero forKey:@"playCount"];
        [hourCache setValue:zero forKey:@"playTime"];
    }
    
    en = [songs objectEnumerator];
    NSManagedObject *sessionSong;
    while ((sessionSong = [en nextObject])) {
        NSCalendarDate *submitted = [NSCalendarDate dateWithTimeIntervalSince1970:
            [[sessionSong valueForKey:@"submitted"] timeIntervalSince1970]];
        NSNumber *hour = [NSNumber numberWithShort:[submitted hourOfDay]];
        hourCache = [self cacheForHour:hour inSession:session moc:moc];
        ISASSERT(hourCache != nil, "missing hour!");    
        [hourCache incrementPlayCount:[sessionSong valueForKey:@"playCount"]];
        [hourCache incrementPlayTime:[sessionSong valueForKey:@"playTime"]];
    }
    
#ifdef ISDEBUG
    NSArray *hours = [[PersistentProfile sharedInstance] hoursForSession:session];
    NSNumber *count = [hours valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    NSNumber *ptime = [hours valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([count isEqualTo:[session valueForKey:@"playCount"]], "hour cache counts don't match session total!");
    ISASSERT([ptime isEqualTo:[session valueForKey:@"playTime"]], "hour cache times don't match session total!");
#endif
}
#endif

- (void)destroySession:(NSManagedObject*)session archive:(BOOL)archive newEpoch:newEpoch moc:(NSManagedObjectContext*)moc
{
    NSString *sessionName = [[[session valueForKey:@"name"] retain] autorelease];
    if (archive) {
        [[moc persistentStoreCoordinator] lock];
        // Create a new session to replace the one being archived
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
        id obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc];
        [obj setValue:ITEM_SESSION forKey:@"itemType"];
        [obj setValue:sessionName forKey:@"name"];
        [obj setValue:[session valueForKey:@"epoch"] forKey:@"epoch"];
        [obj setValue:[session valueForKey:@"localizedName"] forKey:@"localizedName"];
        [obj release];
        
        // Archive the old session
        ISASSERT(nil == [session valueForKey:@"archive"], "session is already archived!");
        @try {
        
        NSString *archiveName = [sessionName stringByAppendingFormat:@"-%@", [session valueForKey:@"epoch"]];
        [session setValue:archiveName forKey:@"name"];
        NSCalendarDate *sDate = [NSCalendarDate dateWithTimeIntervalSince1970:[[session valueForKey:@"epoch"] timeIntervalSince1970]];
        archiveName = [NSString stringWithFormat:@"%@: %@ (%@)", NSLocalizedString(@"Archive", @""),
            [session valueForKey:@"localizedName"],
            [sDate descriptionWithCalendarFormat:@"%a, %Y-%m-%d"]];
        [session setValue:archiveName forKey:@"localizedName"];
        sDate = [NSCalendarDate dateWithTimeIntervalSince1970:[newEpoch timeIntervalSince1970]-1.0];
        [session setValue:sDate forKey:@"term"];
        
        } @catch (id e) {
            ScrobTrace(@"exception: %@", e);
        }
        
        entity = [NSEntityDescription entityForName:@"PSessionArchive" inManagedObjectContext:moc];
        obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc];
        [session setValue:obj forKey:@"archive"];
        [obj setValue:[NSDate date] forKey:@"created"];
        [obj release];
        [[moc persistentStoreCoordinator] unlock];
        
        // we've replaced a session object, it's important other threads and class clients are notified ASAP
        [[PersistentProfile sharedInstance] save:moc withNotification:NO];
        ISASSERT(moc != [[PersistentProfile sharedInstance] mainMOC], "invalid MOC!");
        #ifdef notyet
        [[PersistentProfile sharedInstance] performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
        #endif
        return;
    }
    
    // otherwise, just clear out everything
    NSSet *result = [session valueForKey:@"items"];
    if ([result count] > 0) {
        NSEnumerator *en = [result objectEnumerator];
        NSManagedObject *item;
        while ((item = [en nextObject]))
            [moc deleteObject:item];
        
        NSNumber *zero = [NSNumber numberWithUnsignedInt:0];
        [session setValue:zero forKey:@"playCount"];
        [session setValue:zero forKey:@"playTime"];
    }
}

- (void)removeSongs:(NSArray*)songs fromSession:(NSManagedObject*)session moc:(NSManagedObjectContext*)moc
{
    {// Pre-fetch all our relationships
        NSError *error = nil;
        NSEntityDescription *entity;
        NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
        // songs
        entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
        [request setEntity:entity];
        [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", [songs valueForKeyPath:@"item.objectID"]]];
        error = nil;
        (void)[moc executeFetchRequest:request error:&error];
        // albums
        entity = [NSEntityDescription entityForName:@"PAlbum" inManagedObjectContext:moc];
        [request setEntity:entity];
        // we can have NSNull instances in this one
        NSMutableArray *oids = [[[songs valueForKeyPath:@"item.album.objectID"] mutableCopy] autorelease];
        [oids removeObject:[NSNull null]];
        [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", oids]];
        error = nil;
        (void)[moc executeFetchRequest:request error:&error];
        // artists
        entity = [NSEntityDescription entityForName:@"PArtist" inManagedObjectContext:moc];
        [request setEntity:entity];
        [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", [songs valueForKeyPath:@"item.artist.objectID"]]];
        error = nil;
        (void)[moc executeFetchRequest:request error:&error];
    }
    
    NSEnumerator *en = [songs objectEnumerator];
    NSManagedObject *sessionSong, *mobj, *sArtist, *sAlbum;
    NSNumber *totalPlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    NSNumber *totalPlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    NSNumber *playCount, *playTime;
    
    (void)[self artistsForSession:session moc:moc]; // fault in
    (void)[self albumsForSession:session moc:moc];
    NSString *sessionName = [session valueForKey:@"name"];
    NSPredicate *filter;
    NSArray *filterResults;
    NSSet *aliases; // core data collections are sets not arrays
    while ((sessionSong = [en nextObject])) {
        playCount = [sessionSong valueForKey:@"playCount"];
        playTime = [sessionSong valueForKey:@"playTime"];
        
        ISASSERT(1 == [playCount unsignedIntValue], "invalid play count!");
        // Update all dependencies
        
        // Artist
        // since filteredArrayUsingPredicate is so SLOW, pair the number of items to search to the smallest possible
        aliases = [sessionSong valueForKeyPath:@"item.artist.sessionAliases"];
        filter = [NSPredicate predicateWithFormat:@"session.name == %@", sessionName];
        filterResults = [[aliases allObjects] filteredArrayUsingPredicate:filter];
        ISASSERT(1 == [filterResults count], "missing or mulitple artists!");
        sArtist = [filterResults objectAtIndex:0];
        ISASSERT([[sArtist valueForKeyPath:@"item.name"] isEqualTo:[sessionSong valueForKeyPath:@"item.artist.name"]], "artist names don't match!");
        [sArtist decrementPlayCount:playCount];
        [sArtist decrementPlayTime:playTime];
        
        // Album
        if ([sessionSong valueForKeyPath:@"item.album"]) {
            aliases = [sessionSong valueForKeyPath:@"item.album.sessionAliases"];
            filter = [NSPredicate predicateWithFormat:@"session.name == %@", sessionName];
            filterResults = [[aliases allObjects] filteredArrayUsingPredicate:filter];
            ISASSERT(1 == [filterResults count], "missing or mulitple albums!");
            sAlbum = [filterResults objectAtIndex:0];
            ISASSERT([[sAlbum valueForKeyPath:@"item.name"] isEqualTo:[sessionSong valueForKeyPath:@"item.album.name"]], "album names don't match!");
            ISASSERT([[sAlbum valueForKeyPath:@"item.artist.name"] isEqualTo:[sessionSong valueForKeyPath:@"item.artist.name"]], "artist names don't match!");
            if (sAlbum) {
                [sAlbum decrementPlayCount:playCount];
                [sAlbum decrementPlayTime:playTime];
            }
        } else
            sAlbum = nil;
        
        // Caches
        #if IS_STORE_V2
        mobj = [self cacheForRating:[sessionSong valueForKey:@"rating"] inSession:session moc:moc];
        if (mobj) {
            [mobj decrementPlayCount:playCount];
            [mobj decrementPlayTime:playTime];
        }
        #endif
        // XXX - don't update rating cache for v1 - see removeSongsBefore
    
        NSCalendarDate *submitted = [NSCalendarDate dateWithTimeIntervalSince1970:
            [[sessionSong valueForKey:@"submitted"] timeIntervalSince1970]];
        NSNumber *hour = [NSNumber numberWithShort:[submitted hourOfDay]];
        if ((mobj = [self cacheForHour:hour inSession:session moc:moc])) {
            [mobj decrementPlayCount:playCount];
            [mobj decrementPlayTime:playTime];
        }
        
        [moc deleteObject:sessionSong];
        if (sAlbum && 0 == [[sAlbum valueForKey:@"playCount"] unsignedIntValue])
            [moc deleteObject:sAlbum];
        if (sArtist && 0 == [[sArtist valueForKey:@"playCount"] unsignedIntValue])
            [moc deleteObject:sArtist];
    }
    
    // Update the session totals
    [session decrementPlayCount:totalPlayCount];
    [session decrementPlayTime:totalPlayTime];
    
#ifdef ISDEBUG
    // Do some validation
    songs = [[PersistentProfile sharedInstance] songsForSession:session];
    totalPlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    totalPlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([totalPlayCount isEqualTo:[session valueForKey:@"playCount"]], "song play counts don't match session total!");
    ISASSERT([totalPlayTime isEqualTo:[session valueForKey:@"playTime"]], "song play times don't match session total!");
    
    #if IS_STORE_V2
    songs = [[PersistentProfile sharedInstance] ratingsForSession:session];
    totalPlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    totalPlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([totalPlayCount isEqualTo:[session valueForKey:@"playCount"]], "rating cache counts don't match session total!");
    ISASSERT([totalPlayTime isEqualTo:[session valueForKey:@"playTime"]], "rating cache times don't match session total!");
    #endif
    
    songs = [[PersistentProfile sharedInstance] hoursForSession:session];
    totalPlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    totalPlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([totalPlayCount isEqualTo:[session valueForKey:@"playCount"]], "hour cache counts don't match session total!");
    ISASSERT([totalPlayTime isEqualTo:[session valueForKey:@"playTime"]], "hour cache times don't match session total!");
#endif
}

- (BOOL)removeSongsBefore:(NSDate*)epoch inSession:(NSString*)sessionName moc:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    
    @try {
    
    NSCalendarDate *gmtEpoch = [epoch GMTDate];
    NSManagedObject *session = [self sessionWithName:sessionName moc:moc];
    // round to avoid microsecond differences
    NSTimeInterval sepoch = floor([[[session valueForKey:@"epoch"] GMTDate] timeIntervalSince1970]);
    if (sepoch >= floor([gmtEpoch timeIntervalSince1970]))
        return (NO); // nothing to do
    
    ISASSERT(![[session valueForKey:@"name"] isEqualTo:@"all"], "attempting removal on 'all' session!");
    
    // count invalid songs
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@) AND (submitted < %@)",
            ITEM_SONG, sessionName, gmtEpoch]];
    NSArray *invalidSongs = [moc executeFetchRequest:request error:&error];
    
    if (0 == [invalidSongs count]) {
        ScrobDebug(@"::%@:: no work to do", sessionName);
        [session setValue:epoch forKey:@"epoch"];
        return (NO);
    }
    
    // count valid songs
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@) AND (submitted >= %@)",
            ITEM_SONG, sessionName, gmtEpoch]];
    NSArray *validSongs = [moc executeFetchRequest:request error:&error];
    
    if ([validSongs count] > [invalidSongs count]) {
        [self removeSongs:invalidSongs fromSession:session moc:moc];
        #if 0 == IS_STORE_V2
        // the PSong rating can change at any time, so we have to regenerate the whole cache from the remaining valid songs
        // for v2 each session song has its own rating, so this is not necessary
        [self recreateRatingsCacheForSession:session songs:validSongs moc:moc];
        #endif
        ScrobLog(SCROB_LOG_TRACE, @"removed %lu songs from session %@", [invalidSongs count], sessionName);
    } else {
        // it's more efficient to destroy everything and add the valid songs back in
        NSEnumerator *en;
        NSManagedObject *item;
        if ([validSongs count] > 0) {
            // save the objects
            NSManagedObject *tempSession = [self sessionWithName:@"temp" moc:moc];
            en = [validSongs objectEnumerator];
            while ((item = [en nextObject]))
                [item setValue:tempSession forKey:@"session"];
        }
        
        [self destroySession:session archive:[sessionName isEqualToString:@"lastfm"] newEpoch:epoch moc:moc];
        
        // refetch the session object in case it changed
        session = [self sessionWithName:sessionName moc:moc];
        
        if ([validSongs count] > 0) {
            // add the saved songs back in
            en = [validSongs objectEnumerator];
            while ((item = [en nextObject])) {
                if (![self addSessionSong:item toSession:session moc:moc]) {
                    ISASSERT(0, "failed to re-add saved song");
                    [moc deleteObject:item];
                }
            }
        }
        
        ScrobLog(SCROB_LOG_TRACE, @"recreated session %@ with %lu valid songs (%lu invalid)",
            sessionName, [validSongs count], [invalidSongs count]);
    }
    
    [session setValue:epoch forKey:@"epoch"];
    
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while updating session %@ (%@)", sessionName, e);
    }
    return (YES);
}

- (BOOL)mergeSongsInSession:(NSManagedObject*)session moc:(NSManagedObjectContext*)moc
{
    NSString *sname = [session valueForKey:@"name"];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@)",
            ITEM_SONG, sname]];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
    [request setSortDescriptors:
        [NSArray arrayWithObjects:
            [[[NSSortDescriptor alloc] initWithKey:@"item" ascending:NO] autorelease],
            [[[NSSortDescriptor alloc] initWithKey:@"submitted" ascending:NO] autorelease],
            nil]];
    NSError *error;
    NSArray *songs = [moc executeFetchRequest:request error:&error];
    #ifdef ISDEBUG
    // Validation setup
    NSNumber *preMergePlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    NSNumber *preMergePlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    #endif
    
    NSManagedObject *s, *sprev;
    NSEnumerator *en = [songs objectEnumerator];
    sprev = [en nextObject];
    NSMutableArray *rem = [NSMutableArray array];
    while ((s = [en nextObject])) {
        if ([[s valueForKey:@"item"] isEqualTo:[sprev valueForKey:@"item"]]) {
            [s incrementPlayCountWithObject:sprev];
            [s incrementPlayTimeWithObject:sprev];
            [rem addObject:sprev];
        }
        sprev = s;
    }
    
    en = [rem objectEnumerator];
    while ((s = [en nextObject])) {
        [moc deleteObject:s];
    }
    
    NSUInteger ct = [songs count];
    ScrobLog(SCROB_LOG_TRACE, @"Merged %lu song entries in session '%@' into %lu entries.", ct, sname, ct - [rem count]);
    
    #ifdef ISDEBUG
    // Do some validation
    songs = [[PersistentProfile sharedInstance] songsForSession:session];
    NSNumber *postMergePlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    NSNumber *postMergePlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([preMergePlayCount isEqualTo:postMergePlayCount], "song play counts don't match pre merge!");
    ISASSERT([preMergePlayTime isEqualTo:postMergePlayTime], "song play times don't match pre merge!");
    #endif
    
    return ([rem count] > 0);
}

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
- (BOOL)recreateCaches:(NSManagedObjectContext*)moc
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity;
    NSManagedObject *mobj;
    NSEnumerator *en;
    NSError *error;
    NSNumber *count, *ptime;
    
    // 'all' session
    // XXX: assumption that [mergeSongsInSession:] was used first
    // this fixes a bug in the 2.0 iTunes importer that would not update the session alias counts when a duplicate song was found
    NSManagedObject *session = [self sessionWithName:@"all" moc:moc];
    entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
        ITEM_SONG, session]];
    [request setReturnsObjectsAsFaults:NO];
    [request setRelationshipKeyPathsForPrefetching:[NSArray arrayWithObjects:@"item", nil]];
    NSArray *songs = [moc executeFetchRequest:request error:&error];
    en = [songs objectEnumerator];
    while ((mobj = [en nextObject])) {
        count = [mobj valueForKeyPath:@"item.playCount"];
        ptime = [mobj valueForKeyPath:@"item.playTime"];
        
        #ifdef ISDEBUG
        if ([count isNotEqualTo:[mobj valueForKey:@"playCount"]]) {
            ScrobLog(SCROB_LOG_TRACE, @"count mismatch for '%@': session: %@, actual: %@",
                [mobj valueForKeyPath:@"item.name"], [mobj valueForKey:@"playCount"], count);
        }
        if ([ptime isNotEqualTo:[mobj valueForKey:@"playTime"]]) {
            ScrobLog(SCROB_LOG_TRACE, @"time mismatch for '%@': session: %@, actual: %@",
                [mobj valueForKeyPath:@"item.name"], [mobj valueForKey:@"playTime"], ptime);
        }
        #endif
        
        [mobj setValue:count forKey:@"playCount"];
        [mobj setValue:ptime forKey:@"playTime"];
    }
    count = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    ptime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    [session setValue:count forKey:@"playCount"];
    [session setValue:ptime forKey:@"playTime"];
    
    [self recreateRatingsCacheForSession:session songs:songs moc:moc];
    [self recreateHourCacheForSession:session songs:songs moc:moc];
    
    // artists
    entity = [NSEntityDescription entityForName:@"PArtist" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@)", ITEM_ARTIST]];
    [request setReturnsObjectsAsFaults:NO];
    [request setRelationshipKeyPathsForPrefetching:[NSArray arrayWithObjects:@"songs", nil]];
    NSArray *artists = [moc executeFetchRequest:request error:&error];
    en = [artists objectEnumerator];
    while ((mobj = [en nextObject])) {
        count = [mobj valueForKeyPath:@"songs.@sum.playCount"];
        ptime = [mobj valueForKeyPath:@"songs.@sum.playTime"];
        [mobj setValue:count forKey:@"playCount"];
        [mobj setValue:ptime forKey:@"playTime"];
    }
#ifdef ISDEBUG
    count = [artists valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    ptime = [artists valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([count isEqualTo:[session valueForKey:@"playCount"]], "artist counts don't match 'all' session total!");
    ISASSERT([ptime isEqualTo:[session valueForKey:@"playTime"]], "artist counts don't match 'all' session total!");
#endif
    
    // albums
    entity = [NSEntityDescription entityForName:@"PAlbum" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@)", ITEM_ALBUM]];
    [request setReturnsObjectsAsFaults:NO];
    [request setRelationshipKeyPathsForPrefetching:[NSArray arrayWithObjects:@"songs", nil]];
#if 0
    [request setSortDescriptors:[NSArray arrayWithObjects:
        [[[NSSortDescriptor alloc] initWithKey:@"artist.name" ascending:YES] autorelease],
        [[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES] autorelease],
        nil]];
#endif
    NSArray *albums = [moc executeFetchRequest:request error:&error];
    en = [albums objectEnumerator];
    while ((mobj = [en nextObject])) {
        count = [mobj valueForKeyPath:@"songs.@sum.playCount"];
        ptime = [mobj valueForKeyPath:@"songs.@sum.playTime"];
    #if 0
        NSString *msg = [NSString stringWithFormat:@"%@ - %@ (%lu): cache: %@, actual: %@, %@\n",
            [mobj valueForKeyPath:@"artist.name"], [mobj valueForKey:@"name"], [[mobj valueForKey:@"songs"] count],
            [mobj valueForKey:@"playCount"], count,
            ([[mobj valueForKey:@"playCount"] isEqualTo:count]) ? @"" : @"*****"];
        [[PersistentProfile sharedInstance] log:msg];
    #endif
        [mobj setValue:count forKey:@"playCount"];
        [mobj setValue:ptime forKey:@"playTime"];
    }
#ifdef ISDEBUG
    u_int32_t cc = [[albums valueForKeyPath:@"playCount.@sum.unsignedIntValue"] unsignedIntValue];
    u_int64_t tt = [[albums valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"] unsignedLongLongValue];
    
    entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (album == nil)", ITEM_SONG]];
    [request setReturnsObjectsAsFaults:NO];
    songs = [moc executeFetchRequest:request error:&error];
    cc += [[songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"] unsignedIntValue];
    tt += [[songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"] unsignedIntValue];
    
    ISASSERT(cc == [[session valueForKey:@"playCount"] unsignedIntValue], "album counts don't match 'all' session total!");
    ISASSERT(tt == [[session valueForKey:@"playTime"] unsignedLongLongValue], "album counts don't match 'all' session total!");
#endif
    return (YES);
}
#endif

- (void)performScrub:(id)arg
{
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5 && defined(ISDEBUG)
    if (!moc && [NSThread isMainThread])
        moc = [[PersistentProfile sharedInstance] mainMOC];
    #endif
    ISASSERT(moc != nil, "missing moc");
    
    BOOL save;
    @try {
    save = [self mergeSongsInSession:[self sessionWithName:@"all" moc:moc] moc:moc];
    } @catch (NSException *e) {
        save = NO;
        [moc rollback];
        ScrobLog(SCROB_LOG_ERR, @"scrub: exception while merging songs: %@", e);
    }
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    if (save)
        (void)[[PersistentProfile sharedInstance] save:moc withNotification:NO];
    
    @try {
    save = [self recreateCaches:moc];
    } @catch (NSException *e) {
        save = NO;
        [moc rollback];
        ScrobLog(SCROB_LOG_ERR, @"scrub: exception while recreating caches: %@", e);
    }
    #endif
    
    // in the future we may decide to delete ancient archived sessions (> 1yr)
    
    if (save) {
        (void)[[PersistentProfile sharedInstance] save:moc];
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"DBLastScrub"];
    }
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DBNeedsScrub"];
}

- (void)scrub:(NSTimer*)t
{
    NSManagedObjectContext *moc = nil;
    #ifndef ISDEBUG
    BOOL forcedScrub;
    static NSTimeInterval nextScrub = 0.0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (YES == (forcedScrub = [[NSUserDefaults standardUserDefaults] boolForKey:@"DBNeedsScrub"])) {
        if (now < nextScrub)
            return;
        
        nextScrub = now + 900.0;
    } else {
        if (now >= nextScrub)
            nextScrub = now + 900.0;
        
        NSDate *lastScrub = [[NSUserDefaults standardUserDefaults] objectForKey:@"DBLastScrub"];
        if (!lastScrub) {
            moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
            ISASSERT(moc != nil, "missing moc");
            lastScrub = [[PersistentProfile sharedInstance] storeMetadataForKey:(NSString*)kMDItemContentCreationDate moc:moc];
        }
    
        NSCalendarDate *d = [NSCalendarDate date];
        d = [d dateByAddingYears:0 months:-1 days:0 hours:-[d hourOfDay] minutes:-[d minuteOfHour] seconds:-[d secondOfMinute]];
        if ([[lastScrub GMTDate] isGreaterThan:[d GMTDate]])
            return;
    }
    
    ScrobLog(SCROB_LOG_TRACE, @"%@ db scrub", forcedScrub ? @"Forced" : @"Scheduled");
    #else
    // stress testing
    static NSTimer *sched = nil;
    if (t)
        sched = nil;
    if (!sched)
        sched = [NSTimer scheduledTimerWithTimeInterval:3600.0 target:self selector:@selector(scrub:) userInfo:nil repeats:NO];
    if (NO == [[NSUserDefaults standardUserDefaults] boolForKey:@"DBNeedsScrub"] && !t)
        return;
    #endif
    
    [self performScrub:nil];
    if (!moc)
        moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    [moc reset]; // we walked a majority of the db, free the mem
}

- (void)setNeedsScrub:(BOOL)needsScrub // XXX: ignored
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DBNeedsScrub"];
}

- (void)updateLastfmSession:(NSTimer*)t
{
    if (!t)
        [lfmUpdateTimer invalidate];
    [lfmUpdateTimer autorelease];
    lfmUpdateTimer = nil;
    
    if ([[PersistentProfile sharedInstance] importInProgress]) {
        return; // the timer is not rescheduled, but it will be when the import is done
    }
    
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing moc");
    NSCalendarDate *epoch; // we could use [t fireDate], but it may be off by a few seconds
    NSCalendarDate *gmtNow = [NSCalendarDate calendarDate];
    [gmtNow setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    if (0 != [gmtNow dayOfWeek])
        epoch = [gmtNow dateByAddingYears:0 months:0 days:-([gmtNow dayOfWeek]) hours:0 minutes:0 seconds:0];
    else if ([gmtNow hourOfDay] < 12)
        epoch = [gmtNow dateByAddingYears:0 months:0 days:-7 hours:0 minutes:0 seconds:0];
    else
        epoch = [[gmtNow copy] autorelease];
    
    if ([gmtNow hourOfDay] >= 12)
        epoch = [epoch dateByAddingYears:0 months:0 days:0
            hours:-([gmtNow hourOfDay] - 12) minutes:-([gmtNow minuteOfHour]) seconds:-([gmtNow secondOfMinute])];
    else
        epoch = [epoch dateByAddingYears:0 months:0 days:0
            hours:(11 - [gmtNow hourOfDay]) minutes:(59 - [gmtNow minuteOfHour]) seconds:(60 - [gmtNow secondOfMinute])];
    [epoch setTimeZone:[NSTimeZone defaultTimeZone]];
    
    BOOL didRemove = [self removeSongsBefore:epoch inSession:@"lastfm" moc:moc];
    
    epoch = [epoch dateByAddingYears:0 months:0 days:7 hours:0 minutes:0 seconds:0];
    
    lfmUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:[epoch timeIntervalSinceNow]
        target:self selector:@selector(updateLastfmSession:) userInfo:nil repeats:NO] retain];
    
    (void)[[PersistentProfile sharedInstance] save:moc withNotification:NO];
    if (didRemove) {
        @try {
        [moc reset];
        } @catch (NSException *e) {
            ScrobLog(SCROB_LOG_WARN, @"updateLastfmSession: exception during reset: %@", e);
        }
        [[PersistentProfile sharedInstance] performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
    }
}

- (void)updateSessions:(NSTimer*)t
{
    if (!t)
        [sUpdateTimer invalidate];
    [sUpdateTimer autorelease];
    sUpdateTimer = nil;
    
    if ([[PersistentProfile sharedInstance] importInProgress]) {
        return; // the timer is not rescheduled, but it will be when the import is done
    }
    
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing moc");
    BOOL didRemove = NO;
    NSCalendarDate *now = [NSCalendarDate calendarDate];
    NSCalendarDate *midnight = [now dateByAddingYears:0 months:0 days:0
#ifndef REAP_DEBUG
            hours:-([now hourOfDay]) minutes:-([now minuteOfHour]) seconds:-([now secondOfMinute])];
#else
#warning "REAP_DEBUG set"
/*1 hour*/  hours:0 minutes:-([now minuteOfHour]) seconds:-([now secondOfMinute])];
#endif
    if ([self removeSongsBefore:midnight inSession:@"pastday" moc:moc])
        didRemove = YES;
    
    NSCalendarDate *lastWeek = [midnight dateByAddingYears:0 months:0 days:-7 hours:0 minutes:0 seconds:0];
    if ([self removeSongsBefore:lastWeek inSession:@"pastweek" moc:moc])
        didRemove = YES;
    
    NSCalendarDate *lastMonth = [midnight dateByAddingYears:0 months:-1 days:0 hours:0 minutes:0 seconds:0];
    if ([self removeSongsBefore:lastMonth inSession:@"pastmonth" moc:moc])
        didRemove = YES;
    
    NSCalendarDate *last3Months = [midnight dateByAddingYears:0 months:-3 days:0 hours:0 minutes:0 seconds:0];
    if ([self removeSongsBefore:last3Months inSession:@"past3months" moc:moc])
        didRemove = YES;
    
    NSCalendarDate *lastSixMonths = [midnight dateByAddingYears:0 months:-6 days:0 hours:0 minutes:0 seconds:0];
    if ([self removeSongsBefore:lastSixMonths inSession:@"pastsixmonths" moc:moc])
        didRemove = YES;
    
    NSCalendarDate *lastYear = [midnight dateByAddingYears:-1 months:0 days:0 hours:0 minutes:0 seconds:0];
    if ([self removeSongsBefore:lastYear inSession:@"pastyear" moc:moc])
        didRemove = YES;
    
#ifndef REAP_DEBUG
    midnight = [midnight dateByAddingYears:0 months:0 days:0 hours:24 minutes:0 seconds:0];
#else
    midnight = [now dateByAddingYears:0 months:0 days:0 hours:1 minutes:0 seconds:0];
#endif
    
    sUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:[midnight timeIntervalSinceNow]
        target:self selector:@selector(updateSessions:) userInfo:nil repeats:NO] retain];
    
    (void)[[PersistentProfile sharedInstance] save:moc withNotification:NO];
    if (didRemove) {
        @try {
        [moc reset];
        } @catch (NSException *e) {
            ScrobLog(SCROB_LOG_WARN, @"updateSessions: exception during reset: %@", e);
        }
        [[PersistentProfile sharedInstance] performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
    }
}

- (void)processSongPlays:(NSArray*)queue
{
    NSManagedObjectContext *moc;
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread mainThread], "wrong thread!");
    #endif
    
    moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread MOC!");
    
    [[PersistentProfile sharedInstance] setImportInProgress:YES];
    
    NSEnumerator *en;
    NSManagedObject *moSong;
    NSMutableArray *addedSongs = [NSMutableArray array];
    @try {
    
    en = [queue objectEnumerator];
    SongData *obj;
    while ((obj = [en nextObject])) {
        if ((moSong = [self addSongPlay:obj withImportedPlayCount:nil moc:moc]))
            [addedSongs addObject:moSong];
        else
            [moc rollback];
    }
    
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"processingSongPlays: exception %@", e);
    }
    
    [[PersistentProfile sharedInstance] setImportInProgress:NO];
    (void)[[PersistentProfile sharedInstance] save:moc];
    [[PersistentProfile sharedInstance] performSelectorOnMainThread:@selector(addSongPlaysDidFinish:) withObject:nil waitUntilDone:NO];
    // Turn the added songs into faults as we probably won't need them anytime soon
    // (we may need the artist/album/session objects though). This should save on some memory.
    en = [addedSongs objectEnumerator];
    while ((moSong = [en nextObject])) {
        [[moSong managedObjectContext] refreshObject:moSong mergeChanges:NO];
    }
}

- (ISThreadMessenger*)threadMessenger
{
    return (thMsgr);
}

// singleton support
+ (PersistentSessionManager*)sharedInstance
{
    static PersistentSessionManager *shared = nil;
    return (shared ? shared : (shared = [[PersistentSessionManager alloc] init]));
}

- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (NSUInteger)retainCount
{
    return (NSUIntegerMax);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end

@implementation PersistentSessionManager (SongAdditions)

- (NSManagedObject*)orphanedItems:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PItem" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"name == %@", @"-DB-Orphans-"]];
    
    NSArray *result = [moc executeFetchRequest:request error:&error];
    if (1 != [result count]) {
        ISASSERT(0, "missing orphan handler!");
        return (nil); // !!!
    }
    
    return ([result objectAtIndex:0]);
}

- (void)updateSongHistory:(NSManagedObject*)psong count:(NSNumber*)count time:(NSNumber*)secs moc:(NSManagedObjectContext*)moc
{
    // Create a last played history item
    NSDate *songLastPlayed = [psong valueForKey:@"lastPlayed"];
    NSManagedObject *lastPlayed;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSongLastPlayed" inManagedObjectContext:moc];
    lastPlayed = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
    [lastPlayed setValue:songLastPlayed forKey:@"lastPlayed"];
    [lastPlayed setValue:psong forKey:@"song"];
    
    [psong incrementPlayCount:count];
    [psong incrementPlayTime:secs];
    NSManagedObject *mobj = [psong valueForKey:@"artist"];
    [mobj incrementPlayCount:count];
    [mobj incrementPlayTime:secs];
    if ([[songLastPlayed GMTDate] isGreaterThan:[[mobj valueForKey:@"lastPlayed"] GMTDate]])
        [mobj setValue:songLastPlayed forKey:@"lastPlayed"];
    if ((mobj = [psong valueForKey:@"album"])) {
        [mobj incrementPlayCount:count];
        [mobj incrementPlayTime:secs];
        #if IS_STORE_V2
        if ([[songLastPlayed GMTDate] isGreaterThan:[[mobj valueForKey:@"lastPlayed"] GMTDate]])
            [mobj setValue:songLastPlayed forKey:@"lastPlayed"];
        #endif
    }
}

- (void)incrementSessionCountsWithSong:(NSManagedObject*)sessionSong moc:(NSManagedObjectContext*)moc
{
    NSManagedObject *orphans = [self orphanedItems:moc];
    NSManagedObject *session = [sessionSong valueForKey:@"session"];
    NSManagedObject *ratingsCache, *hoursCache;
    NSEntityDescription *entity;
    
    // Update the ratings cache
    #if IS_STORE_V2
    ratingsCache = [self cacheForRating:[sessionSong valueForKey:@"rating"] inSession:session moc:moc];
    #else
    ratingsCache = [self cacheForRating:[sessionSong valueForKeyPath:@"item.rating"] inSession:session moc:moc];
    #endif
    if (!ratingsCache) {
        entity = [NSEntityDescription entityForName:@"PRatingCache" inManagedObjectContext:moc];
        ratingsCache = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [ratingsCache setValue:ITEM_RATING_CCH forKey:@"itemType"];
        [ratingsCache setValue:session forKey:@"session"];
        [ratingsCache setValue:orphans forKey:@"item"];
        #if IS_STORE_V2
        [ratingsCache setValue:[sessionSong valueForKey:@"rating"] forKey:@"rating"];
        #else
        [ratingsCache setValue:[sessionSong valueForKeyPath:@"item.rating"] forKey:@"rating"];
        #endif
    }
    [ratingsCache incrementPlayCountWithObject:sessionSong];
    [ratingsCache incrementPlayTimeWithObject:sessionSong];
    
    // Update the hours cache
    NSCalendarDate *submitted = [NSCalendarDate dateWithTimeIntervalSince1970:
        [[sessionSong valueForKey:@"submitted"] timeIntervalSince1970]];
    NSNumber *hour = [NSNumber numberWithShort:[submitted hourOfDay]];
    hoursCache = [self cacheForHour:hour inSession:session moc:moc];
    if (!hoursCache) {
        entity = [NSEntityDescription entityForName:@"PHourCache" inManagedObjectContext:moc];
        hoursCache = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [hoursCache setValue:ITEM_HOUR_CCH forKey:@"itemType"];
        [hoursCache setValue:session forKey:@"session"];
        [hoursCache setValue:orphans forKey:@"item"];
        [hoursCache setValue:hour forKey:@"hour"];
    }
    [hoursCache incrementPlayCountWithObject:sessionSong];
    [hoursCache incrementPlayTimeWithObject:sessionSong];
    
    // Finally, update the session counts
    [session incrementPlayCountWithObject:sessionSong];
    [session incrementPlayTimeWithObject:sessionSong];
}

- (BOOL)addSessionSong:(NSManagedObject*)sessionSong toSession:(NSManagedObject*)session moc:(NSManagedObjectContext*)moc
{
    if (!session)
        return (NO);
    
    @try {
    
    ISASSERT([sessionSong valueForKey:@"submitted"] != nil, "missing submitted!");
    ISASSERT([sessionSong valueForKey:@"item"] != nil, "missing item!");
    ISASSERT([sessionSong valueForKeyPath:@"item.artist"] != nil, "missing item artist!");
    
    NSDate *sub = [[sessionSong valueForKey:@"submitted"] GMTDate];
    if ([sub isLessThan:[[session valueForKey:@"epoch"] GMTDate]]
        || ([session valueForKey:@"term"] && [sub isGreaterThan:[[session valueForKey:@"term"] GMTDate]]))
        return (NO);
    
    [sessionSong setValue:session forKey:@"session"];
    
    NSString *sessionName = [session valueForKey:@"name"];
    NSManagedObject *artist, *album;
    NSEntityDescription *entity;
    NSSet *aliases;
    // Update the Artist
    aliases = [sessionSong valueForKeyPath:@"item.artist.sessionAliases"];
    NSArray *result = [[aliases allObjects] filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"session.name == %@", sessionName]];
    if (1 == [result count]) {
        artist = [result objectAtIndex:0];
        ISASSERT([[artist valueForKeyPath:@"item.name"] isEqualTo:[sessionSong valueForKeyPath:@"item.artist.name"]], "artist names don't match!");
    } else if (0 == [result count]) {
        entity = [NSEntityDescription entityForName:@"PSessionArtist" inManagedObjectContext:moc];
        artist = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [artist setValue:ITEM_ARTIST forKey:@"itemType"];
        [artist setValue:[sessionSong valueForKeyPath:@"item.artist"] forKey:@"item"];
        [artist setValue:session forKey:@"session"];
    } else {
        ISASSERT(0, "multiple artists found in session!");
        @throw ([NSException exceptionWithName:NSInternalInconsistencyException reason:@"multiple session artists!" userInfo:nil]);
    }
    
    [artist incrementPlayCountWithObject:sessionSong];
    [artist incrementPlayTimeWithObject:sessionSong];
    
    if ([sessionSong valueForKeyPath:@"item.album"]) {
        // Update the album
        aliases = [sessionSong valueForKeyPath:@"item.album.sessionAliases"];
        result = [[aliases allObjects] filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"session.name == %@", sessionName]];
        if (1 == [result count]) {
            album = [result objectAtIndex:0];
            ISASSERT([[album valueForKeyPath:@"item.name"] isEqualTo:[sessionSong valueForKeyPath:@"item.album.name"]], "album names don't match!");
            ISASSERT([[album valueForKeyPath:@"item.artist.name"] isEqualTo:[sessionSong valueForKeyPath:@"item.artist.name"]], "artist names don't match!");
        } else if (0 == [result count]) {
            entity = [NSEntityDescription entityForName:@"PSessionAlbum" inManagedObjectContext:moc];
            album = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
            [album setValue:ITEM_ALBUM forKey:@"itemType"];
            [album setValue:[sessionSong valueForKeyPath:@"item.album"] forKey:@"item"];
            [album setValue:session forKey:@"session"];
        } else {
            ISASSERT(0, "multiple artist albums found in session!");
            @throw ([NSException exceptionWithName:NSInternalInconsistencyException reason:@"multiple session albums!" userInfo:nil]);
        }
        
        [album incrementPlayCountWithObject:sessionSong];
        [album incrementPlayTimeWithObject:sessionSong];
    }
    
    [self incrementSessionCountsWithSong:sessionSong moc:moc];
    return (YES);
    
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while adding song to session (%@)", e);
    }
    return (NO);
}

- (void)syncPersistentSong:(NSManagedObject*)psong withSong:(SongData*)song
{
    if (trackTypeFile == [song type]) {
        ISASSERT([song path] && [[song path] length] > 0, "no local path!");
        // Make sure our play count is in sync with the player's
        NSNumber *count = [song playCount];
        if ([count unsignedIntValue] > 0 && [[psong valueForKey:@"playCount"] isNotEqualTo:count]) {
            #if IS_STORE_V2
            [self setNeedsScrub:YES];
            NSNumber *nlCount = [psong valueForKey:@"nonLocalPlayCount"];
            if (nlCount) {
                u_int32_t adjCount = [count unsignedIntValue] + [nlCount unsignedIntValue];
                if (adjCount >= [count unsignedIntValue])
                    count = [NSNumber numberWithUnsignedInt:adjCount];
                #ifdef ISDEBUG
                else
                    ISASSERT(0, "count overflow!");
                #endif
            }
            #endif
            [psong setValue:count forKey:@"playCount"];
            NSNumber *pTime = [psong valueForKey:@"duration"];
            pTime = [NSNumber numberWithUnsignedLongLong:[pTime unsignedLongLongValue] * [count unsignedLongLongValue]];
            [psong setValue:pTime forKey:@"playTime"];
        }
        
        count = [song rating]; // and the rating
        if ([[psong valueForKey:@"rating"] isNotEqualTo:count]) {
            [psong setValue:count forKey:@"rating"];
        }
    }
}

- (NSManagedObject*)addSongPlay:(SongData*)song withImportedPlayCount:(NSNumber*)importCount moc:(NSManagedObjectContext*)moc
{
    ISElapsedTimeInit();
    
    ISStartTime();
    NSManagedObject *psong = [song persistentSongWithContext:moc];
    ISEndTime();
    ScrobDebug(@"[persistentSongWithContext:] returned in %.4f us", ISElapsedMicroSeconds());
    
    if (psong) {
        NSEntityDescription *entity;
        // increment counts
        NSNumber *pCount;
        NSNumber *pTime;
        if (nil == importCount) {
            pCount = [NSNumber numberWithUnsignedInt:1];
            pTime = [psong valueForKey:@"duration"];
            
            [self syncPersistentSong:psong withSong:song];
            #if IS_STORE_V2
            if (trackTypeFile != [song type]) {
                // XXX: must update after [syncPersistentSong:]
                ISASSERT(nil == [song path] || 0 == [[song path] length], "has local path!");
                u_int32_t nlCount = [[psong valueForKey:@"nonLocalPlayCount"] unsignedIntValue] + [pCount unsignedIntValue];
                [psong setValue:[NSNumber numberWithUnsignedInt:nlCount] forKey:@"nonLocalPlayCount"];
            }
            #endif
        } else {
            pCount = importCount;
            pTime = [NSNumber numberWithUnsignedLongLong:
                [[psong valueForKey:@"duration"] unsignedLongLongValue] * [pCount unsignedLongLongValue]];
            [psong setValue:importCount forKey:@"importedPlayCount"];
        }
        [self updateSongHistory:psong count:pCount time:pTime moc:moc];
        
        // add to sessions
        NSManagedObject *sessionSong, *session;
        NSArray *sessions = [[self activeSessionsWithMOC:moc] arrayByAddingObjectsFromArray:
            // we get archives in case the user played songs from an iPod and an older session needs to be updated
            // limiting to 5 will get us the past 5 weeks of the last.fm weeklies (which are currently the only sessions archived)
            [self archivedSessionsWithMOC:moc weekLimit:5]];
        NSEnumerator *en = [sessions objectEnumerator];
        entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
        NSString *sessionName;
        while ((session = [en nextObject])) {
            if ([(sessionName = [session valueForKey:@"name"]) isEqualTo:@"temp"]
                || (importCount && NO == [sessionName isEqualTo:@"all"]))
                continue;
            
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            
            sessionSong = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
            [sessionSong setValue:ITEM_SONG forKey:@"itemType"];
            [sessionSong setValue:psong forKey:@"item"];
            [sessionSong setValue:[psong valueForKey:@"submitted"] forKey:@"submitted"];
            #if IS_STORE_V2
            [sessionSong setValue:[psong valueForKey:@"rating"] forKey:@"rating"];
            #endif
            [sessionSong incrementPlayCount:pCount];
            [sessionSong incrementPlayTime:pTime];
            
            //ISStartTime();
            if (![self addSessionSong:sessionSong toSession:session moc:moc]) 
                [moc deleteObject:sessionSong];
            //ISEndTime();
            //ScrobDebug(@"[addSessionSong:] (%@) returned in %.4f us", [session valueForKey:@"name"], ISElapsedMicroSeconds());
            
            [pool release];
        }
    }
    return (psong);
}

@end

@implementation PersistentSessionManager (Editors)

- (void)editObject:(NSDictionary*)args
{
    NSError *err = nil;
    PersistentProfile *profile = [PersistentProfile sharedInstance];
    NSMutableDictionary *noteInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [args objectForKey:@"oid"], @"oid", nil];
    NSMutableDictionary *noteArgs;
    @try {
    
    SEL selector = NSSelectorFromString([args objectForKey:@"method"]);
    NSMethodSignature *sig = [self methodSignatureForSelector:selector];
    if (!sig)
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"method not found" userInfo:args]);
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:sig];
    [call setTarget:self]; // arg 0
    [call setSelector:selector]; // arg 1
    
    NSUInteger i = 0;
    NSArray *callArgs = [args objectForKey:@"args"];
    NSUInteger argCount = [callArgs count];
    id argStore[argCount];
    for (; i < argCount; ++i) {
        argStore[i] = [callArgs objectAtIndex:i];
        [call setArgument:&argStore[i] atIndex:i+2];
    }
    
    noteArgs = [NSMutableDictionary dictionary];
    [noteArgs setObject:PersistentProfileWillEditObject forKey:@"name"];
    [noteArgs setObject:[[noteInfo copy] autorelease] forKey:@"info"];
    [profile performSelectorOnMainThread:@selector(postNoteWithArgs:) withObject:noteArgs waitUntilDone:NO];
    
    [call invoke];
    [call getReturnValue:&err];
    
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"peristence: editing exception while executing '%@' (%@)", args, e);
        err = [NSError errorWithDomain:@"iScrobbler Persistence" code:EINVAL userInfo:
            [NSDictionary dictionaryWithObjectsAndKeys:[e reason], NSLocalizedDescriptionKey, nil]];
    }
    
    noteArgs = [NSMutableDictionary dictionary];
    noteInfo = [[noteInfo mutableCopy] autorelease];
    [noteArgs setObject:noteInfo forKey:@"info"];
    if (!err) {
        [noteArgs setObject:PersistentProfileDidEditObject forKey:@"name"];
        [profile performSelectorOnMainThread:@selector(postNoteWithArgs:) withObject:noteArgs waitUntilDone:NO];
    } else {
        [noteArgs setObject:PersistentProfileFailedEditObject forKey:@"name"];
        [noteInfo setObject:err forKey:NSUnderlyingErrorKey];
        [profile performSelectorOnMainThread:@selector(postNoteWithArgs:) withObject:noteArgs waitUntilDone:NO];
    }
}

- (NSError*)rename:(NSManagedObjectID*)moid to:(NSString*)newName
{
    ScrobDebug(@"");
    
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing moc");
    NSManagedObject *mobj = [moc objectWithID:moid];
    NSError *err = nil;
    
    PersistentProfile *profile = [PersistentProfile sharedInstance];
    [profile setImportInProgress:YES]; // lock the database from additions by external clients
    
    @try {
    
    NSPredicate *predicate;
    NSEntityDescription *entity;
    NSString *type = [mobj valueForKey:@"itemType"];
    if ([ITEM_SONG isEqualTo:type]) {
        SongData *song = [[[SongData alloc] init] autorelease];
        [song setTitle:newName];
        [song setTrackNumber:[mobj valueForKey:@"trackNumber"]];
        [song setArtist:[mobj valueForKeyPath:@"artist.name"]];
        [song setAlbum:[mobj valueForKeyPath:@"album.name"]];
        predicate = [song matchingPredicate:nil];
        entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    } else if ([ITEM_ARTIST isEqualTo:type]) {
        predicate = [NSPredicate predicateWithFormat:@"(itemType == %@) AND (name LIKE[cd] %@)",
            ITEM_ARTIST, [newName stringByEscapingNSPredicateReserves]];
        entity = [NSEntityDescription entityForName:@"PArtist" inManagedObjectContext:moc];
    } else if ([ITEM_ALBUM isEqualTo:type]) {
        predicate = [NSPredicate predicateWithFormat:@"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@)",
                ITEM_ALBUM, [newName stringByEscapingNSPredicateReserves],
                [[mobj valueForKeyPath:@"artist.name"] stringByEscapingNSPredicateReserves]];
        entity = [NSEntityDescription entityForName:@"PAlbum" inManagedObjectContext:moc];
    } else {
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"object rename: invalid type" userInfo:nil]);
    }
    
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:predicate];
    NSArray *result = [moc executeFetchRequest:request error:&err];
    if (0 == [result count]) {
        [mobj setValue:newName forKey:@"name"];
        [profile save:moc withNotification:NO];
        [mobj refreshSelf];
    } else {
        err = [NSError errorWithDomain:@"iScrobbler Persistence" code:EINVAL userInfo:
            [NSDictionary dictionaryWithObjectsAndKeys:
                NSLocalizedString(@"Can't rename. An object with the same name already exists.", ""), NSLocalizedDescriptionKey,
                nil]];
    }
    
    } @catch (NSException *e) {
        [profile setImportInProgress:NO];
        @throw (e);
    }
    
    [profile setImportInProgress:NO];
    return (err);
}

@end

@implementation SongData (PersistentAdditions)

- (NSPredicate*)matchingPredicate:(NSString**)albumTitle
{
    // tried optimizing this search by just searching for song titles and then limiting to artist/album in memory,
    // but it made no difference in speed
    NSPredicate *predicate;
    NSString *aTitle;
    if ((aTitle = [self album]) && [aTitle length] > 0) {
        NSNumber *trackNo = [self trackNumber];
        if ([trackNo unsignedIntValue] > 0) {
            predicate = [NSPredicate predicateWithFormat:
                @"(itemType == %@) AND (trackNumber == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@) AND (album.name LIKE[cd] %@)",
                ITEM_SONG, trackNo,
                [[self title] stringByEscapingNSPredicateReserves],
                [[self artist] stringByEscapingNSPredicateReserves],
                [aTitle stringByEscapingNSPredicateReserves]];
        } else {
            predicate = [NSPredicate predicateWithFormat:
                @"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@) AND (album.name LIKE[cd] %@)",
                ITEM_SONG,
                [[self title] stringByEscapingNSPredicateReserves],
                [[self artist] stringByEscapingNSPredicateReserves],
                [aTitle stringByEscapingNSPredicateReserves]];
        }
    } else {
        aTitle = nil;
        predicate = [NSPredicate predicateWithFormat:
            @"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@)",
            ITEM_SONG, [[self title] stringByEscapingNSPredicateReserves], [[self artist] stringByEscapingNSPredicateReserves]];
    }
    if (albumTitle)
        *albumTitle = aTitle;
    return (predicate);
}

- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
    @try {
    NSString *aTitle;
    NSPredicate *predicate = [self matchingPredicate:&aTitle];
    [request setPredicate:predicate];
    
    NSCalendarDate *myLastPlayed = [NSCalendarDate dateWithTimeIntervalSince1970:
        [[self postDate] timeIntervalSince1970] + [[self duration] unsignedIntValue]];
    NSManagedObject *moSong;
    
    NSArray *result = [moc executeFetchRequest:request error:&error];
    if ([result count] > 1) {
        #ifdef ISINTERNAL
        ISASSERT(0 == [result count], "multiple songs found in db!");
        #endif
        (void)[result valueForKeyPath:@"name"]; // make sure they are faulted in for logging
        ScrobLog(SCROB_LOG_ERR, @"Multiple songs found in database! {{%@}}", result);
        ScrobLog(SCROB_LOG_WARN, @"Using first song found.");
        result = [NSArray arrayWithObject:[result objectAtIndex:0]];
    }
    if (1 == [result count]) {
         // Update song values
        moSong = [result objectAtIndex:0];
        [moSong setValue:[self postDate] forKey:@"submitted"];
        [moSong setValue:myLastPlayed forKey:@"lastPlayed"];
         
        return (moSong);
    }
    
    // Song not found
    NSManagedObject *moArtist, *moAlbum;
    moSong = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
    [moSong setValue:ITEM_SONG forKey:@"itemType"];
    [moSong setValue:[self title] forKey:@"name"];
    [moSong setValue:[self duration] forKey:@"duration"];
    [moSong setValue:[self postDate] forKey:@"submitted"];
    [moSong setValue:myLastPlayed forKey:@"firstPlayed"];
    [moSong setValue:myLastPlayed forKey:@"lastPlayed"];
    [moSong setValue:[self rating] forKey:@"rating"];
    if ([[self trackNumber] intValue] > 0)
        [moSong setValue:[self trackNumber] forKey:@"trackNumber"];
    if ([[self mbid] length] > 0)
        [moSong setValue:[self mbid] forKey:@"mbid"];
    
    // Find/Create artist
    entity = [NSEntityDescription entityForName:@"PArtist" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (name LIKE[cd] %@)",
            ITEM_ARTIST, [[self artist] stringByEscapingNSPredicateReserves]]];
    
    result = [moc executeFetchRequest:request error:&error];
    if (1 == [result count]) {
        moArtist = [result objectAtIndex:0];
    } else if (0 == [result count]) {
        moArtist = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [moArtist setValue:ITEM_ARTIST forKey:@"itemType"];
        [moArtist setValue:[self artist] forKey:@"name"];
        #if IS_STORE_V2
        [moArtist setValue:myLastPlayed forKey:@"firstPlayed"];
        #endif
    } else {
        ScrobLog(SCROB_LOG_CRIT, @"Multiple artists found in database! {{%@}}", result);
        ISASSERT(0, "multiple artists found in db!");
        @throw ([NSException exceptionWithName:NSGenericException reason:@"multiple artists found in db!" userInfo:nil]);
    }
    [moSong setValue:moArtist forKey:@"artist"];
    
    if (aTitle) {
        // Find/Create album
        entity = [NSEntityDescription entityForName:@"PAlbum" inManagedObjectContext:moc];
        [request setEntity:entity];
        [request setPredicate:
            [NSPredicate predicateWithFormat:
                @"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@)",
                ITEM_ALBUM, [aTitle stringByEscapingNSPredicateReserves],
                [[self artist] stringByEscapingNSPredicateReserves]]];
        
        result = [moc executeFetchRequest:request error:&error];
        if (1 == [result count]) {
            moAlbum = [result objectAtIndex:0];
        } else if (0 == [result count]) {
            moAlbum = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
            [moAlbum setValue:ITEM_ALBUM forKey:@"itemType"];
            [moAlbum setValue:aTitle forKey:@"name"];
            [moAlbum setValue:moArtist forKey:@"artist"];
            #if IS_STORE_V2
            [moAlbum setValue:myLastPlayed forKey:@"firstPlayed"];
            #endif
        } else {
            ScrobLog(SCROB_LOG_CRIT, @"Multiple artists found in database! {{%@}}", result);
            ISASSERT(0, "multiple albums found in db!");
            @throw ([NSException exceptionWithName:NSGenericException reason:@"multiple albums found in db!" userInfo:nil]);
        }
        [moSong setValue:moAlbum forKey:@"album"];
    }
    
    // Set the player
    if ([self isPlayeriTunes] || [self isLastFmRadio]) {
        if ([self isPlayeriTunes]) {
            if (trackTypeShared != [self type])
                aTitle = @"iTunes";
            else
                aTitle = @"iTunes Shared Library";
        } else
            aTitle = @"Last.fm Radio";
        entity = [NSEntityDescription entityForName:@"PPlayer" inManagedObjectContext:moc];
        [request setEntity:entity];
        [request setPredicate:[NSPredicate predicateWithFormat:@"name LIKE[cd] %@",
            [aTitle stringByEscapingNSPredicateReserves]]];
        
        result = [moc executeFetchRequest:request error:&error];
        if (1 == [result count]) {
            [moSong setValue:[result objectAtIndex:0] forKey:@"player"];
        } 
#ifdef ISDEBUG
        else if (0 == [result count]) {
            ISASSERT(0, "player not found in db!");
        } else
            ISASSERT(0, "multiple players found in db!");
#endif
    }
    
    return (moSong);
    
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception creating persistent song for %@ (%@)", [self brief], e);
    }
    
    return (nil);
}

@end

@implementation NSDate (ISDateConversion)
- (NSCalendarDate*)GMTDate
{
   return ([self dateWithCalendarFormat:nil timeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]]);
}
@end

@implementation NSManagedObject (PItemMathAdditions)

- (void)incrementPlayCount:(NSNumber*)count
{
    u_int32_t playCount = [[self valueForKey:@"playCount"] unsignedIntValue] + [count unsignedIntValue];
    [self setValue:[NSNumber numberWithUnsignedInt:playCount] forKey:@"playCount"];
    
}

- (void)incrementPlayTime:(NSNumber*)count
{
    u_int64_t playTime = [[self valueForKey:@"playTime"] unsignedLongLongValue] + [count unsignedLongLongValue];
    [self setValue:[NSNumber numberWithUnsignedLongLong:playTime] forKey:@"playTime"];
}

- (void)incrementPlayCountWithObject:(NSManagedObject*)obj
{
    [self incrementPlayCount:[obj valueForKey:@"playCount"]];
}

- (void)incrementPlayTimeWithObject:(NSManagedObject*)obj
{
    [self incrementPlayTime:[obj valueForKey:@"playTime"]];
}

- (void)decrementPlayCount:(NSNumber*)count
{
    u_int32_t myCount = [[self valueForKey:@"playCount"] unsignedIntValue];
    u_int32_t playCount = [count unsignedIntValue];
    if (myCount >= playCount) {
        myCount -= playCount;
        [self setValue:[NSNumber numberWithUnsignedInt:myCount] forKey:@"playCount"];
    }
    #ifdef ISDEBUG
    else
        ISASSERT(0, "count went south!");
    #endif
}

- (void)decrementPlayTime:(NSNumber*)count
{
    u_int64_t myTime = [[self valueForKey:@"playTime"] unsignedLongLongValue];
    u_int64_t playTime = [count unsignedLongLongValue];
    if (myTime >= playTime) {
        myTime -= playTime;
        [self setValue:[NSNumber numberWithUnsignedLongLong:myTime] forKey:@"playTime"];
    }
    #ifdef ISDEBUG
    else
        ISASSERT(0, "time went south!");
    #endif
}

@end
