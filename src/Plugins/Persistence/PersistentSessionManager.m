//
//  PersistentSessionManager.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/17/2007.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import "PersistentSessionManager.h"
#import "Persistence.h"
#import "PersistenceImport.h"
#import "ISThreadMessenger.h"
#import "SongData.h"

@interface SongData (PersistentAdditions)
- (NSPredicate*)matchingPredicateWithTrackNum:(BOOL)includeTrackNum;
- (NSManagedObject*)createPersistentSongWithContext:(NSManagedObjectContext*)moc;
@end

@interface PersistentProfile (Private)
+ (PersistentProfile*)sharedInstance;

- (BOOL)save:(NSManagedObjectContext*)moc withNotification:(BOOL)notify error:(NSError**)error;
- (BOOL)save:(NSManagedObjectContext*)moc withNotification:(BOOL)notify;
- (BOOL)save:(NSManagedObjectContext*)moc;
- (void)backupDatabase;
- (void)resetMain;
- (void)setImportInProgress:(BOOL)import;
- (NSManagedObjectContext*)mainMOC;
- (void)addSongPlaysDidFinish:(id)obj;
- (id)storeMetadataForKey:(NSString*)key moc:(NSManagedObjectContext*)moc;
- (void)setStoreMetadata:(id)object forKey:(NSString*)key moc:(NSManagedObjectContext*)moc;
@end

@interface PersistentSessionManager (Private)
- (BOOL)removeSongsBefore:(NSDate*)epoch inSession:(NSString*)sessionName moc:(NSManagedObjectContext*)moc;
- (void)recreateHourCacheForSession:(NSManagedObject*)session songs:(NSArray*)songs moc:(NSManagedObjectContext*)moc;
- (void)setNeedsScrub:(BOOL)needsScrub;
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
            hours:-([now hourOfDay]) minutes:-([now minuteOfHour]) seconds:-(ABS([now secondOfMinute] - 2))];
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
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
            ITEM_ARTIST, session]];
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
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
            ITEM_ALBUM, session]];
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
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@) AND (rating == %@)",
            ITEM_RATING_CCH, session, rating]];
    
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
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@) AND (hour == %@)",
            ITEM_HOUR_CCH, session, hour]];
    
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

- (void)updateDBTimeZone:(NSNumber*)updateSessions
{
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    @try {
    
    // The hour caches are based on local time, if the TZ changes, they have to be recalculated so that
    // removal of session songs updates the correct hour cache. Since archives won't have any songs removed, we ignore them.
    PersistentProfile *pp = [PersistentProfile sharedInstance];
    NSNumber *lastTZOffset = [pp storeMetadataForKey:@"ISTZOffset" moc:moc];
    NSInteger tzOffset = [[NSTimeZone defaultTimeZone] secondsFromGMT];
    if (!lastTZOffset || (tzOffset != (NSInteger)[lastTZOffset longLongValue])) {
        ScrobLog(SCROB_LOG_VERBOSE, @"Time Zone has changed, updating local chart caches...");
        NSArray *sessions = [self activeSessionsWithMOC:moc];
        NSEnumerator *en = [sessions objectEnumerator];
        NSManagedObject *s;
        while ((s = [en nextObject])) {
            [self recreateHourCacheForSession:s songs:[pp songsForSession:s] moc:moc];
            ScrobLog(SCROB_LOG_VERBOSE, @"'%@' session updated for time zone change.", [s valueForKey:@"name"]);
        }
        
        [pp setStoreMetadata:[NSNumber numberWithLongLong:tzOffset] forKey:@"ISTZOffset" moc:moc];
        [pp save:moc withNotification:NO];
        
        if (updateSessions && [updateSessions intValue] > 0)
            [self performSelector:@selector(sessionManagerUpdate) withObject:nil];
    }
    
    } @catch (NSException *e) {
        [moc rollback];
        ScrobLog(SCROB_LOG_TRACE, @"uncaught exception during TZ change handler: %@", e);
    }
}

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
- (void)timeZoneDidChange:(NSNotification*)note
{
    ScrobDebug(@"mainThread: %d", [NSThread isMainThread]);
    [ISThreadMessenger makeTarget:[self threadMessenger] performSelector:@selector(updateDBTimeZone:)
        withObject:[NSNumber numberWithBool:YES]];
}
#endif

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
    
    [self updateDBTimeZone:nil];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    // XXX: NSSystemTimeZoneDidChangeNotification is supposed to be sent, but it does not seem to work
    // with the app or distributed center
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(timeZoneDidChange:)
        name:@"NSSystemTimeZoneDidChangeDistributedNotification" object:nil];
    #endif
    
    lfmUpdateTimer = sUpdateTimer = nil;
    @try {
    [self performSelector:@selector(updateLastfmSession:) withObject:nil];
    [self performSelector:@selector(updateSessions:) withObject:nil];
    [self performSelector:@selector(scrub:) withObject:nil];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_TRACE, @"[sessionManager:] uncaught exception during init: %@", e);
    }
    
    [pool release];
    pool = [[NSAutoreleasePool alloc] init];
    do {
        @try {
        [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        
        [self performSelector:@selector(scrub:) withObject:nil];
        } @catch (NSException *e) {
            ScrobLog(SCROB_LOG_TRACE, @"[sessionManager:] uncaught exception: %@", e);
        }
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
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
    
    NSManagedObject *orphans = [self orphanedItems:moc];
    en = [songs objectEnumerator];
    NSManagedObject *sessionSong;
    while ((sessionSong = [en nextObject])) {
        NSCalendarDate *submitted = [NSCalendarDate dateWithTimeIntervalSince1970:
            [[sessionSong valueForKey:@"submitted"] timeIntervalSince1970]];
        NSNumber *hour = [NSNumber numberWithShort:[submitted hourOfDay]];
        if (!(hourCache = [self cacheForHour:hour inSession:session moc:moc])) {
            // this should only occur when switching time zones
            NSEntityDescription *entity = [NSEntityDescription entityForName:@"PHourCache" inManagedObjectContext:moc];
            hourCache = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
            [hourCache setValue:ITEM_HOUR_CCH forKey:@"itemType"];
            [hourCache setValue:session forKey:@"session"];
            [hourCache setValue:hour forKey:@"hour"];
            // this is a required value; since it has no meaning for the caches we just set it to the orphan session
            [hourCache setValue:orphans forKey:@"item"];
        }
        
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

- (BOOL)archiveDailySessionWithEpoch:(NSCalendarDate*)newEpoch moc:(NSManagedObjectContext*)moc
{
    BOOL updated = NO;;
    
    @try {
    
    NSCalendarDate *yesterday = [newEpoch dateByAddingYears:0 months:0 days:0 hours:-24 minutes:0 seconds:0];
    NSManagedObject *sYesterday = [self sessionWithName:@"yesterday" moc:moc];
    NSManagedObject *sToday = [self sessionWithName:@"pastday" moc:moc];
    NSEntityDescription *entity;
    if (!sYesterday) {
        entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
        sYesterday = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [sYesterday setValue:ITEM_SESSION forKey:@"itemType"];
        [sYesterday setValue:@"yesterday" forKey:@"name"];
        [sYesterday setValue:NSLocalizedString(@"Yesterday", "") forKey:@"localizedName"];
        [sYesterday setValue:yesterday forKey:@"epoch"];
    } else {
        updated = [self removeSongsBefore:yesterday inSession:@"yesterday" moc:moc];
    }
    
    NSDate *term = [NSCalendarDate dateWithTimeIntervalSince1970:[newEpoch timeIntervalSince1970]-1.0];
    [sYesterday setValue:term forKey:@"term"];
    
    entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@) AND (submitted >= %@) AND (submitted <= %@)",
            ITEM_SONG, sToday, [yesterday GMTDate], [[sYesterday valueForKey:@"term"] GMTDate]]];
    NSError *error = nil;
    NSArray *songsToArchive = [moc executeFetchRequest:request error:&error];
    
    NSManagedObject *song, *newSong;
    NSEnumerator *en = [songsToArchive objectEnumerator];
    while ((song = [en nextObject])) {
        newSong = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [newSong setValue:ITEM_SONG forKey:@"itemType"];
        [newSong setValue:[song valueForKey:@"playCount"] forKey:@"playCount"];
        [newSong setValue:[song valueForKey:@"playTime"] forKey:@"playTime"];
        [newSong setValue:[song valueForKey:@"item"] forKey:@"item"];
        #if IS_STORE_V2
        [newSong setValue:[song valueForKey:@"rating"] forKey:@"rating"];
        #endif
        [newSong setValue:[song valueForKey:@"submitted"] forKey:@"submitted"];
        [self addSessionSong:newSong toSession:sYesterday moc:moc];
    }
    if (!updated)
        updated = [songsToArchive count] > 0;
    
    #ifdef ISDEBUG
    @try {
    
    entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@) AND (submitted > %@)",
            ITEM_SONG, sYesterday, [[sYesterday valueForKey:@"term"] GMTDate]]];
    ISASSERT([[moc executeFetchRequest:request error:&error] count] == 0, "invalid session songs!");
    
    } @catch (NSException *de) {}
    
    #endif
    
    } @catch (NSException *e) {
        ScrobTrace(@"exception: %@", e);
        updated = NO;
        [moc rollback];
    }
    
    return (updated);
}

- (void)destroySession:(NSManagedObject*)session archive:(BOOL)archive newEpoch:(NSDate*)newEpoch moc:(NSManagedObjectContext*)moc
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

- (NSManagedObject*)sessionAlbumForSessionSong:(NSManagedObject*)sessionSong
{
    NSSet *aliases = [sessionSong valueForKeyPath:@"item.album.sessionAliases"];
    NSPredicate *filter = [NSPredicate predicateWithFormat:@"session.name == %@", [sessionSong valueForKeyPath:@"session.name"]];
    NSArray *filterResults = [[aliases allObjects] filteredArrayUsingPredicate:filter];
    ISASSERT([filterResults count] <= 1, "mulitple session albums!");
    NSManagedObject *sAlbum;
    if ([filterResults count] > 0) {
        sAlbum = [filterResults objectAtIndex:0];
        ISASSERT([[sAlbum valueForKeyPath:@"item.name"] isEqualTo:[sessionSong valueForKeyPath:@"item.album.name"]], "album names don't match!");
        ISASSERT([[sAlbum valueForKeyPath:@"item.artist.name"] isEqualTo:[sessionSong valueForKeyPath:@"item.artist.name"]], "artist names don't match!");
        return (sAlbum);
    }
    
    return (nil);
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
        // since filteredArrayUsingPredicate is so SLOW, pare the number of items to search to the smallest possible
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
            sAlbum = [self sessionAlbumForSessionSong:sessionSong];
            ISASSERT(sAlbum != nil, "missing session album!");
            [sAlbum decrementPlayCount:playCount];
            [sAlbum decrementPlayTime:playTime];
        } else
            sAlbum = nil;
        
        // Caches
        #if IS_STORE_V2
        mobj = [self cacheForRating:[sessionSong valueForKey:@"rating"] inSession:session moc:moc];
        if (mobj) {
            [mobj decrementPlayCount:playCount];
            [mobj decrementPlayTime:playTime];
        }
        #ifdef DEBUG
        else
            ISASSERT(0, "missing ratings cache!");
        #endif
        #endif
        // XXX - don't update rating cache for v1 - see removeSongsBefore
    
        NSCalendarDate *submitted = [NSCalendarDate dateWithTimeIntervalSince1970:
            [[sessionSong valueForKey:@"submitted"] timeIntervalSince1970]];
        NSNumber *hour = [NSNumber numberWithShort:[submitted hourOfDay]];
        if ((mobj = [self cacheForHour:hour inSession:session moc:moc])) {
            [mobj decrementPlayCount:playCount];
            [mobj decrementPlayTime:playTime];
        }
        #ifdef DEBUG
        else
            ISASSERT(0, "missing hour cache!");
        #endif
        
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
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@) AND (submitted < %@)",
            ITEM_SONG, session, gmtEpoch]];
    NSArray *invalidSongs = [moc executeFetchRequest:request error:&error];
    
    if (0 == [invalidSongs count]) {
        ScrobDebug(@"::%@:: no work to do", sessionName);
        [session setValue:epoch forKey:@"epoch"];
        return (NO);
    }
    
    // count valid songs
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@) AND (submitted >= %@)",
            ITEM_SONG, session, gmtEpoch]];
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
    ScrobLog(SCROB_LOG_VERBOSE, @"scrub: merging song plays");
    
    NSString *sname = [session valueForKey:@"name"];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
            ITEM_SONG, session]];
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
// This is not a general use method as we don't know for sure which play history events are valid
// I wrote it to clean up my personal db
#ifdef ISDEBUG
- (void)validatePlayHistory:(NSManagedObject*)song
{
    NSUInteger songCount = [[song valueForKey:@"playCount"] unsignedIntValue];
    NSUInteger histCount = [[song valueForKey:@"playHistory"] count];
    if (songCount < histCount) {
        NSArray *hist = [[[song valueForKey:@"playHistory"] allObjects] sortedArrayUsingDescriptors:
            [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"lastPlayed" ascending:YES] autorelease]]];
        ScrobLog(SCROB_LOG_TRACE, @"invalid playHistory for '%@': count: %lu, history count: %lu",
            [song valueForKey:@"name"], songCount, histCount);
        
        NSManagedObject *histEntry;
        NSRange r;
        r = NSMakeRange(0, histCount - songCount);
        NSEnumerator *histEn = [[hist subarrayWithRange:r] objectEnumerator];
        while ((histEntry = [histEn nextObject])) {
            NSDate *histPlayed = [histEntry valueForKey:@"lastPlayed"];
            ScrobLog(SCROB_LOG_TRACE, @"removing play history '%@' for '%@. %@'",
                histPlayed, [song valueForKeyPath:@"trackNumber"], [song valueForKey:@"name"]);
            
            //[[song managedObjectContext] deleteObject:histEntry];
        }
    }
}
#endif

- (BOOL)recreateCaches:(NSManagedObjectContext*)moc
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity;
    NSManagedObject *mobj, *rootObj;
    NSEnumerator *en;
    NSError *error;
    NSNumber *count, *ptime;
    NSNumber *zero = [NSNumber numberWithUnsignedInt:0];
    
    // 'all' session
    // XXX: assumption that [mergeSongsInSession:] was used first
    // this fixes a bug in the 2.0 iTunes importer that would not update the session alias counts when a duplicate song was found
    NSManagedObject *session = [self sessionWithName:@"all" moc:moc];
    ScrobLog(SCROB_LOG_VERBOSE, @"scrub: recreating song play cache");
    entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
        ITEM_SONG, session]];
    [request setReturnsObjectsAsFaults:NO];
    [request setRelationshipKeyPathsForPrefetching:[NSArray arrayWithObjects:@"item", nil]];
    BOOL refetch = NO;
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
        [self validatePlayHistory:[mobj valueForKey:@"item"]];
        #endif
        
        if ([count unsignedIntValue] > 0) {        
            [mobj setValue:count forKey:@"playCount"];
            [mobj setValue:ptime forKey:@"playTime"];
        } else {
            [mobj setValue:zero forKey:@"playTime"];
            [moc deleteObject:mobj];
            refetch = YES;
        }
    }
    if (refetch)
        songs = [moc executeFetchRequest:request error:&error];
    
    count = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    ptime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    [session setValue:count forKey:@"playCount"];
    [session setValue:ptime forKey:@"playTime"];
    
    [self recreateRatingsCacheForSession:session songs:songs moc:moc];
    [self recreateHourCacheForSession:session songs:songs moc:moc];
    
    // artists
    ScrobLog(SCROB_LOG_VERBOSE, @"scrub: recreating artist play cache");
    entity = [NSEntityDescription entityForName:@"PSessionArtist" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
        ITEM_ARTIST, session]];
    [request setReturnsObjectsAsFaults:NO];
    [request setRelationshipKeyPathsForPrefetching:[NSArray arrayWithObjects:@"item", @"item.songs", nil]];
    NSArray *artists = [moc executeFetchRequest:request error:&error];
    en = [artists objectEnumerator];
    while ((mobj = [en nextObject])) {
        rootObj = [mobj valueForKey:@"item"];
        count = [rootObj valueForKeyPath:@"songs.@sum.playCount"];
        ptime = [rootObj valueForKeyPath:@"songs.@sum.playTime"];
        [rootObj setValue:count forKey:@"playCount"];
        [rootObj setValue:ptime forKey:@"playTime"];
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
    ScrobLog(SCROB_LOG_VERBOSE, @"scrub: recreating album play cache");
    entity = [NSEntityDescription entityForName:@"PSessionAlbum" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
        ITEM_ALBUM, session]];
    [request setReturnsObjectsAsFaults:NO];
    [request setRelationshipKeyPathsForPrefetching:[NSArray arrayWithObjects:@"item", @"item.songs", nil]];
#if 0
    [request setSortDescriptors:[NSArray arrayWithObjects:
        [[[NSSortDescriptor alloc] initWithKey:@"artist.name" ascending:YES] autorelease],
        [[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES] autorelease],
        nil]];
#endif
    NSArray *albums = [moc executeFetchRequest:request error:&error];
    en = [albums objectEnumerator];
    while ((mobj = [en nextObject])) {
        rootObj = [mobj valueForKey:@"item"];
        count = [rootObj valueForKeyPath:@"songs.@sum.playCount"];
        ptime = [rootObj valueForKeyPath:@"songs.@sum.playTime"];
    #if 0
        NSString *msg = [NSString stringWithFormat:@"%@ - %@ (%lu): cache: %@, actual: %@, %@\n",
            [mobj valueForKeyPath:@"artist.name"], [mobj valueForKey:@"name"], [[mobj valueForKey:@"songs"] count],
            [mobj valueForKey:@"playCount"], count,
            ([[mobj valueForKey:@"playCount"] isEqualTo:count]) ? @"" : @"*****"];
        [[PersistentProfile sharedInstance] log:msg];
    #endif
        [rootObj setValue:count forKey:@"playCount"];
        [rootObj setValue:ptime forKey:@"playTime"];
        if ([count unsignedIntValue] > 0) {
            [mobj setValue:count forKey:@"playCount"];
            [mobj setValue:ptime forKey:@"playTime"];
        } else {
            [mobj setValue:zero forKey:@"playTime"];
            [moc deleteObject:mobj];
            refetch = YES;
        }
    }
#ifdef ISDEBUG
    if (refetch)
        albums = [moc executeFetchRequest:request error:&error];
    
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
    
    ScrobLog(SCROB_LOG_TRACE, @"scrub started");
    
    BOOL save;
    @try {
    save = [self mergeSongsInSession:[self sessionWithName:@"all" moc:moc] moc:moc];
    } @catch (NSException *e) {
        save = NO;
        [moc rollback];
        ScrobLog(SCROB_LOG_ERR, @"scrub: exception while merging songs: %@", e);
        return;
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
    
    ScrobLog(SCROB_LOG_TRACE, @"scrub finished");
    
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
        
        nextScrub = now + 600.0;
    } else {
        if (now >= nextScrub)
            nextScrub = now + 420.0;
        
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
    NSCalendarDate *gmtNow = [[NSCalendarDate calendarDate] GMTDate];
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
    epoch = [epoch dateWithCalendarFormat:nil timeZone:[NSTimeZone defaultTimeZone]];
    
    BOOL didRemove = [self removeSongsBefore:epoch inSession:@"lastfm" moc:moc];
    
    epoch = [epoch dateByAddingYears:0 months:0 days:7 hours:0 minutes:0 seconds:0];
    NSCalendarDate *now = [NSCalendarDate date];
    if ([epoch isLessThan:now]) {
        // last week was standard time and the current time is DST, check again at nearest 1/2 hour
        NSInteger mAdj = [now minuteOfHour];
        mAdj = mAdj >= 30 ? (59 - mAdj) : (29 - mAdj);
        epoch = [now dateByAddingYears:0 months:0 days:0 hours:0 minutes:mAdj seconds:(60 - [now secondOfMinute])];
    }
    
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
        hours:0 minutes:-([now minuteOfHour]) seconds:-([now secondOfMinute])];
#endif
    if ([self archiveDailySessionWithEpoch:midnight moc:moc])
        didRemove = YES;
    
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
        [[PersistentProfile sharedInstance] backupDatabase];
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

- (void)synchronizeDatabaseWithiTunes
{
    // We require the extended scrubbing of the 10.5 plugin
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    PersistentProfile *pp = [PersistentProfile sharedInstance];
    if ([pp importInProgress]) {
        ScrobLog(SCROB_LOG_WARN, @"synchronizeWithiTunes: The database is busy");
        return;
    }
    
    [pp setImportInProgress:YES];
    [[[[PersistentProfileImport alloc] init] autorelease] syncWithiTunes];
    [pp setImportInProgress:NO];
    [self setNeedsScrub:YES];
    [self scrub:nil];
    #else
    ScrobLog(SCROB_LOG_WARN, @"synchronizeWithiTunes: not supported with this OS version");
    #endif
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
        #if IS_STORE_V2
        [ratingsCache setValue:[sessionSong valueForKey:@"rating"] forKey:@"rating"];
        #else
        [ratingsCache setValue:[sessionSong valueForKeyPath:@"item.rating"] forKey:@"rating"];
        #endif
        // this is a required value; since it has no meaning for the caches we just set it to the orphan session
        [ratingsCache setValue:orphans forKey:@"item"];
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
        [hoursCache setValue:hour forKey:@"hour"];
        // this is a required value; since it has no meaning for the caches we just set it to the orphan session
        [hoursCache setValue:orphans forKey:@"item"];
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
    NSManagedObject *psong = [song createPersistentSongWithContext:moc];
    ISEndTime();
    ScrobDebug(@"[createPersistentSongWithContext:] returned in %.4f us", ISElapsedMicroSeconds());
    
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
            // limiting to 6 will get us the past 6 weeks of the last.fm weeklies (which are currently the only sessions archived)
            [self archivedSessionsWithMOC:moc weekLimit:6]];
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
        predicate = [song matchingPredicateWithTrackNum:YES];
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
    // see if we can do a case-only change
    if (1 == [result count] && [[[result objectAtIndex:0] objectID] isEqualTo:[mobj objectID]]) {
        result = [NSArray array];
    }
    if (0 == [result count]) {
        [mobj setValue:newName forKey:@"name"];
        (void)[profile save:moc withNotification:NO error:&err];
        [mobj refreshSelf];
    } else {
        err = [NSError errorWithDomain:@"iScrobbler Persistence" code:EINVAL userInfo:
            [NSDictionary dictionaryWithObjectsAndKeys:
                NSLocalizedString(@"Can't rename. An object with the same name already exists.", ""), NSLocalizedDescriptionKey,
                nil]];
    }
    
    } @catch (NSException *e) {
        [profile setImportInProgress:NO];
        [moc rollback];
        @throw (e);
    }
    
    [profile setImportInProgress:NO];
    return (err);
}

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
- (void)updateSongPlayCountsWithRemovedSessionInstance:(NSManagedObject*)sessionSong
{
    NSManagedObject *song = [sessionSong valueForKey:@"item"];
    NSManagedObject *parent;
    NSNumber *playCount = [sessionSong valueForKey:@"playCount"];
    NSNumber *playTime = [sessionSong valueForKey:@"playTime"];
    
    [song decrementPlayCount:playCount];
    [song decrementPlayTime:playTime];
    parent = [song valueForKey:@"artist"];
    [parent decrementPlayCount:playCount];
    [parent decrementPlayTime:playTime];
    parent = [song valueForKey:@"album"];
    if (parent) {
        [parent decrementPlayCount:playCount];
        [parent decrementPlayTime:playTime];
    }
    
    // play history
     NSCalendarDate *playDate = [NSCalendarDate dateWithTimeIntervalSince1970:
        [[sessionSong valueForKey:@"submitted"] timeIntervalSince1970] + [[song valueForKey:@"duration"] unsignedIntValue]];
    if ([[playDate GMTDate] isEqualToDate:[[song valueForKey:@"lastPlayed"] GMTDate]]) {
        NSArray *hist = [[[song valueForKey:@"playHistory"] allObjects] sortedArrayUsingDescriptors:
            [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"lastPlayed" ascending:NO] autorelease]]];
        if ([hist count] > 1)
            [song setValue:[[hist objectAtIndex:1] valueForKey:@"lastPlayed"] forKey:@"lastPlayed"];
    }
    
    NSManagedObjectContext *moc = [song managedObjectContext];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:[NSEntityDescription entityForName:@"PSongLastPlayed" inManagedObjectContext:moc]];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(self IN %@) AND (lastPlayed == %@)",
        [song valueForKey:@"playHistory"], [playDate GMTDate]];
    [request setPredicate:predicate];
    [request setReturnsObjectsAsFaults:NO];
    NSError *error;
    NSArray *histEntries = [moc executeFetchRequest:request error:&error];
    if (1 == [histEntries count]) {
        [moc deleteObject:[histEntries objectAtIndex:0]];
    }
}

- (void)removeAllPlayInstances:(NSManagedObject*)sessionSong
{
    NSManagedObjectContext *moc = [sessionSong managedObjectContext];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:[NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc]];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(self IN %@) AND (submitted == %@) AND (session.name != %@)",
        [sessionSong valueForKeyPath:@"item.sessionAliases"], [[sessionSong valueForKey:@"submitted"] GMTDate], @"all"];
    [request setPredicate:predicate];
    [request setReturnsObjectsAsFaults:NO];
    NSError *error;
    NSArray *entries = [moc executeFetchRequest:request error:&error];
    NSManagedObject *s;
    NSEnumerator *en = [entries objectEnumerator];
    while ((s = [en nextObject])) {
        NSManagedObject *session = [s valueForKey:@"session"];
        [self removeSongs:[NSArray arrayWithObject:s] fromSession:session moc:moc];
    }
}
#endif

- (NSError*)removeObject:(NSManagedObjectID*)moid
{
    ScrobDebug(@"");
    
    // We require the extended scrubbing of the 10.5 plugin
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing moc");
    NSError *err = nil;
    
    PersistentProfile *profile = [PersistentProfile sharedInstance];
    [profile setImportInProgress:YES]; // lock the database from additions by external clients
    
    NSNumber *zero = [NSNumber numberWithInt:0];
    
    @try {
    BOOL isSessionSong = NO;
    NSManagedObject *song = [moc objectWithID:moid];
    NSMutableSet *sessions = [NSMutableSet set];
    NSString *type = [song valueForKey:@"itemType"];
    NSString *songClass = [[song entity] name];
    if ([ITEM_SONG isEqualTo:type]) {
        if ([@"PSong" isEqualToString:songClass]) {
            [sessions setSet:[song valueForKeyPath:@"sessionAliases.session"]];
        } else {
            isSessionSong = YES;
            [self updateSongPlayCountsWithRemovedSessionInstance:song];
            [self removeAllPlayInstances:song];
        }
    } else {
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"remove object: invalid type" userInfo:nil]);
    }
    
    if (NO == isSessionSong) {
        // scrub takes care of updating the 'all' session
        [sessions removeObject:[self sessionWithName:@"all" moc:moc]];
        NSManagedObject *containingSession;
        NSEnumerator *en = [sessions objectEnumerator];
        NSSet *allSessionAliases = [song valueForKey:@"sessionAliases"];
        while ((containingSession = [en nextObject])) {
            NSArray *sessionSongs = [[allSessionAliases filteredSetUsingPredicate:
                [NSPredicate predicateWithFormat:@"session == %@", containingSession]] allObjects];
            [self removeSongs:sessionSongs fromSession:containingSession moc:moc];
        }
        [moc deleteObject:song];
    }
    
    if ([[PersistentProfile sharedInstance] save:moc withNotification:NO error:&err]) {
        [self setNeedsScrub:YES];
        // scrub will be performed when this RunLoop run finishes
        //[self scrub:nil];
    }
    
    } @catch (NSException *e) {
        [profile setImportInProgress:NO];
        [moc rollback];
        @throw (e);
    }
    
    [profile setImportInProgress:NO];
    return (err);
    #else
    @throw ([NSException exceptionWithName:NSInternalInconsistencyException reason:@"removeObject: not supported with this OS version" userInfo:nil]);
    #endif
}

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5 && defined(ISDEBUG)
- (NSError*)mergeObject:(NSManagedObjectID*)fromID intoObject:(NSManagedObjectID*)toID mergeCounts:(NSNumber*)mergeCounts
{
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing moc");
    NSManagedObject *from = [moc objectWithID:fromID];
    NSManagedObject *to = [moc objectWithID:toID];
    NSError *err = nil;
    
    if ([to isEqualTo:from])
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"merge object: cannot merge into self" userInfo:nil]);
    
    if (NO == [[to valueForKey:@"itemType"] isEqualToString:ITEM_SONG]
        || NO == [[from valueForKey:@"itemType"] isEqualToString:ITEM_SONG])
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"merge object: invalid type" userInfo:nil]);
    
    if ([[to valueForKey:@"artist"] isNotEqualTo:[from valueForKey:@"artist"]])
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"merge object: artists do not match" userInfo:nil]);
    
    PersistentProfile *profile = [PersistentProfile sharedInstance];
    [profile setImportInProgress:YES]; // lock the database from additions by external clients
    
    @try {
    
    if ([[from valueForKey:@"firstPlayed"] isLessThan:[to valueForKey:@"firstPlayed"]])
        [to setValue:[from valueForKey:@"firstPlayed"] forKey:@"firstPlayed"];
    if ([[from valueForKey:@"lastPlayed"] isGreaterThan:[to valueForKey:@"lastPlayed"]])
        [to setValue:[from valueForKey:@"lastPlayed"] forKey:@"lastPlayed"];
    if ([[from valueForKey:@"submitted"] isGreaterThan:[to valueForKey:@"submitted"]])
        [to setValue:[from valueForKey:@"submitted"] forKey:@"submitted"];
    #if 0
    if (nil == [to valueForKey:@"mbid"] && nil != [from valueForKey:@"mbid"])
        [to setValue:[from valueForKey:@"mbid"] forKey:@"mbid"];
    #endif
    
    if (mergeCounts && [mergeCounts boolValue])
        [to incrementPlayCount:[from valueForKey:@"playCount"]];
    u_int64_t newDuration = [[to valueForKey:@"duration"] unsignedLongLongValue];
    u_int64_t newPlaytime = [[to valueForKey:@"playCount"] unsignedLongLongValue] * newDuration;
    [to setValue:[NSNumber numberWithUnsignedLongLong:newPlaytime] forKey:@"playTime"];
    
    NSManagedObject *oldAlbum = [from valueForKey:@"album"];
    NSManagedObject *newAlbum = [to valueForKey:@"album"];
    
    unsigned count = [[from valueForKey:@"nonLocalPlayCount"] unsignedIntValue] + [[to valueForKey:@"nonLocalPlayCount"] unsignedIntValue];
    if (count <= [[to valueForKey:@"playCount"] unsignedIntValue])
        [to setValue:[NSNumber numberWithUnsignedInt:count] forKey:@"nonLocalPlayCount"];
    
    count = [[from valueForKey:@"importedPlayCount"] unsignedIntValue] + [[to valueForKey:@"importedPlayCount"] unsignedIntValue];
    if (count <= [[to valueForKey:@"playCount"] unsignedIntValue])
        [to setValue:[NSNumber numberWithUnsignedInt:count] forKey:@"importedPlayCount"];
    
    NSEnumerator *en = [[[from valueForKey:@"playHistory"] allObjects] objectEnumerator];
    NSManagedObject *event;
    while ((event = [en nextObject])) {
        [event setValue:to forKey:@"song"];
    }
    
    en = [[[from valueForKey:@"sessionAliases"] allObjects] objectEnumerator];
    while ((event = [en nextObject])) {
        if ([[event valueForKeyPath:@"session.name"] isEqualToString:@"all"])
            continue; // scrub will handle this
        
        NSManagedObject *sAlbum;
        NSNumber *eventPlaycount = [event valueForKey:@"playCount"];
        if (oldAlbum) {
            if ((sAlbum = [self sessionAlbumForSessionSong:event])) {
                [sAlbum decrementPlayCount:eventPlaycount];
                [sAlbum decrementPlayTime:[event valueForKey:@"playTime"]];
            }
        }
        
        [event setValue:to forKey:@"item"];
        
        if (newAlbum) {
            if ((sAlbum != [self sessionAlbumForSessionSong:event])) {
                // there's no alias for the "new" album, we have to create it
                NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionAlbum" inManagedObjectContext:moc];
                sAlbum = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
                [sAlbum setValue:ITEM_ALBUM forKey:@"itemType"];
                [sAlbum setValue:newAlbum forKey:@"item"];
                [sAlbum setValue:[event valueForKey:@"session"] forKey:@"session"];
                 
            }
            newPlaytime = [eventPlaycount unsignedLongLongValue] * newDuration;
            [sAlbum incrementPlayCount:eventPlaycount];
            [sAlbum incrementPlayTime:[NSNumber numberWithUnsignedLongLong:newPlaytime]];
        }
    }
    
    NSNumber *zero = [NSNumber numberWithUnsignedInt:0];
    if (mergeCounts && [mergeCounts boolValue]) {
        [from setValue:zero forKey:@"playCount"];
        [from setValue:zero forKey:@"playTime"];
    }
    if ([[PersistentProfile sharedInstance] save:moc withNotification:NO error:&err]) {
        // scrub will update the 'all' session
        err = [self removeObject:fromID];
    }
    
    } @catch (NSException *e) {
        [profile setImportInProgress:NO];
        [moc rollback];
        @throw (e);
    }
    
    [profile setImportInProgress:NO];
    return (err);
}
#endif

- (NSError*)addHistoryEvent:(NSDate*)playDate forObject:(NSManagedObjectID*)moid
{
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing moc");
    NSError *err = nil;
    
    NSManagedObject *mobj = [moc objectWithID:moid];
    if (NO == [[[mobj entity] name] isEqualToString:@"PSong"])
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"add history: invalid type" userInfo:nil]);
        
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSongLastPlayed" inManagedObjectContext:moc];
    NSManagedObject *event = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
    [event setValue:playDate forKey:@"lastPlayed"];
    [event setValue:mobj forKey:@"song"];
    (void)[[PersistentProfile sharedInstance] save:moc withNotification:NO error:&err];
    return (err);
}

- (NSError*)removeHistoryEvent:(NSManagedObjectID*)eventID forObject:(NSManagedObjectID*)moid
{
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing moc");
    NSError *err = nil;
    
    NSManagedObject *mobj = [moc objectWithID:moid];
    NSManagedObject *event = [moc objectWithID:eventID];
    if (NO == [[[mobj entity] name] isEqualToString:@"PSong"] || NO == [[[event entity] name] isEqualToString:@"PSongLastPlayed"])
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"remove history: invalid type" userInfo:nil]);
    
    if (NO == [[event valueForKey:@"song"] isEqualTo:mobj])
        @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"remove history: invalid event" userInfo:nil]);
        
    [moc deleteObject:event];
    (void)[[PersistentProfile sharedInstance] save:moc withNotification:NO error:&err];
    return (err);
}

@end

@implementation SongData (PersistentAdditions)

- (NSPredicate*)matchingPredicateWithTrackNum:(BOOL)includeTrackNum
{
    NSPredicate *predicate;
    NSString *aTitle;
    if ((aTitle = [self album]) && [aTitle length] > 0) {
        if (includeTrackNum) {
            NSNumber *trackNo = [self trackNumber];
            if ([trackNo unsignedIntValue] > 0) {
                predicate = [NSPredicate predicateWithFormat:
                    @"(itemType == %@) AND (trackNumber == %@) AND (artist.name LIKE[cd] %@) AND (album.name LIKE[cd] %@) AND (name LIKE[cd] %@)",
                    ITEM_SONG, trackNo,
                    [[self artist] stringByEscapingNSPredicateReserves],
                    [aTitle stringByEscapingNSPredicateReserves],
                    [[self title] stringByEscapingNSPredicateReserves]];
            } else {
                predicate = [NSPredicate predicateWithFormat:
                    @"(itemType == %@) AND ((trackNumber == NULL) OR (trackNumber == 0)) AND (artist.name LIKE[cd] %@) AND (album.name LIKE[cd] %@) AND (name LIKE[cd] %@)",
                    ITEM_SONG,
                    [[self artist] stringByEscapingNSPredicateReserves],
                    [aTitle stringByEscapingNSPredicateReserves],
                    [[self title] stringByEscapingNSPredicateReserves]];
            }
        } else {
            predicate = [NSPredicate predicateWithFormat:
                @"(itemType == %@) AND (artist.name LIKE[cd] %@) AND (album.name LIKE[cd] %@) AND (name LIKE[cd] %@)",
                ITEM_SONG,
                [[self artist] stringByEscapingNSPredicateReserves],
                [aTitle stringByEscapingNSPredicateReserves],
                [[self title] stringByEscapingNSPredicateReserves]];
        }
    } else {
        predicate = [NSPredicate predicateWithFormat:
            @"(itemType == %@) AND (artist.name LIKE[cd] %@) AND (name LIKE[cd] %@)",
            ITEM_SONG, [[self artist] stringByEscapingNSPredicateReserves], [[self title] stringByEscapingNSPredicateReserves]];
    }
    return (predicate);
}

- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc
{
    #ifndef ISDEBUG
    NSManagedObjectID *soid;
    @synchronized(self) {
        // this should be retain retained, but it's not used outside of this method, so we are OK
        // XXX: if merging is ever implemented, then this needs to be updated for the deleted object
        soid = persistentID;
    }
    if (soid) {
        ScrobLog(SCROB_LOG_TRACE, @"[persistentSongWithContext:] OID cache hit");
        return ([moc objectWithID:soid]);
    }
    #endif
    
    NSManagedObject *song = nil;
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    NSPredicate *predicate = [self matchingPredicateWithTrackNum:YES];
    [request setPredicate:predicate];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
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
       song = [result objectAtIndex:0];
    }
    
    // XXX: This is a spurious (and much more expensive w/o the track num condition) search
    // for a track that does not exist in the db yet.
    unsigned tno;
    if (!song && (tno = [[self trackNumber] unsignedIntValue]) > 0) {        
        predicate = [self matchingPredicateWithTrackNum:NO];
        [request setPredicate:predicate];
        // w/o the track num condition, we could get multiples - sort them so those w/o a track num are first
        [request setSortDescriptors:[NSArray arrayWithObject:
            [[[NSSortDescriptor alloc] initWithKey:@"trackNumber" ascending:NO] autorelease]]];
        
        result = [moc executeFetchRequest:request error:&error];
        if ([result count] > 1) {
            (void)[result valueForKeyPath:@"name"]; // make sure they are faulted in for logging
            ScrobLog(SCROB_LOG_WARN, @"Multiple songs found in database! {{%@}}", result);
            ScrobLog(SCROB_LOG_WARN, @"Using first song found.");
            result = [NSArray arrayWithObject:[result objectAtIndex:0]];
        }
        
        if (1 == [result count]) {
            song = [result objectAtIndex:0];
            if ([[song valueForKey:@"trackNumber"] unsignedIntValue] == 0) {
                // XXX: we assume this is the same song in the music player DB, and the user just set the track number
                [song setValue:[self trackNumber] forKey:@"trackNumber"];
            } else {
                /* The found track could be different.
                There are several albums that contain different tracks musically but with the same title. */
                song = nil;
            }
        }
    }
    
    if (song) {
        @synchronized(self) {
            if (!persistentID)
                persistentID = [[song objectID] retain];
            #ifdef ISDEBUG
            else
                ISASSERT([persistentID isEqualTo:[song objectID]], "db object id's don't match!");
            #endif
        }
    }
    
    return (song);
}

- (NSManagedObject*)createPersistentSongWithContext:(NSManagedObjectContext*)moc
{
    @try {
    NSCalendarDate *myLastPlayed = [NSCalendarDate dateWithTimeIntervalSince1970:
        [[self postDate] timeIntervalSince1970] + [[self duration] unsignedIntValue]];
    
    NSManagedObject *moSong = [self persistentSongWithContext:moc];
    if (moSong) {
        [moSong setValue:[self postDate] forKey:@"submitted"];
        [moSong setValue:myLastPlayed forKey:@"lastPlayed"];
        
        NSString *mymbid = [self mbid];
        if ([mymbid length] > 0) {
            NSString *pmbid;
            if (!(pmbid = [moSong valueForKey:@"mbid"]) || NSOrderedSame != [mymbid caseInsensitiveCompare:pmbid])
                [moSong setValue:mymbid forKey:@"mbid"];
        }
        
        return (moSong);
    }
    
    // Song not found
    NSString *aTitle = [self album];
    if (aTitle && 0 == [aTitle length])
        aTitle = nil;
    
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
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
    
    NSArray *result = [moc executeFetchRequest:request error:&error];
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
