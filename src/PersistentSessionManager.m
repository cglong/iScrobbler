//
//  PersistentSessionManager.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/17/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//
#import "PersistentSessionManager.h"
#import "Persistence.h"
#import "ISThreadMessenger.h"
#import "SongData.h"

#ifdef ISDEBUG
__private_extern__ NSThread *mainThread;
#endif

@interface PersistentProfile (Private)
- (BOOL)save:(NSManagedObjectContext*)moc withNotification:(BOOL)notify;
- (BOOL)save:(NSManagedObjectContext*)moc;
- (void)resetMain;
- (void)setImportInProgress:(BOOL)import;
- (NSManagedObjectContext*)mainMOC;
- (void)addSongPlaysDidFinish:(id)obj;
@end

@interface SongData (PersistentAdditions)
- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc;
@end

@implementation PersistentSessionManager

- (NSArray*)activeSessionsWithMOC:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (archive == NULL)", ITEM_SESSION]];
    LEOPARD_BEGIN
    [request setReturnsObjectsAsFaults:NO];
    LEOPARD_END
    
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
    LEOPARD_BEGIN
    [request setReturnsObjectsAsFaults:NO];
    LEOPARD_END
    
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
    LEOPARD_BEGIN
    [request setReturnsObjectsAsFaults:NO];
    LEOPARD_END
    
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
    LEOPARD_BEGIN
    [request setReturnsObjectsAsFaults:NO];
    LEOPARD_END
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
    LEOPARD_BEGIN
    [request setReturnsObjectsAsFaults:NO];
    LEOPARD_END
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
    
    lfmUpdateTimer = sUpdateTimer = nil;
    [self performSelector:@selector(updateLastfmSession:) withObject:nil];
    [self performSelector:@selector(updateSessions:) withObject:nil];
    
    thMsgr = [[ISThreadMessenger scheduledMessengerWithDelegate:self] retain];
    
    do {
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
        @try {
        [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
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
    ISASSERT(mainThread && (mainThread != [NSThread currentThread]), "wrong thread!");
    [self performSelector:@selector(updateLastfmSession:) withObject:nil];
    [self performSelector:@selector(updateSessions:) withObject:nil];
}

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
        
#if IS_THREAD_SESSIONMGR
        // we've replaced a session object, it's important other threads and class clients are notified ASAP
        [[PersistentProfile sharedInstance] save:moc withNotification:NO];
        ISASSERT(moc != [[PersistentProfile sharedInstance] mainMOC], "invalid MOC!");
        #ifdef notyet
        [[PersistentProfile sharedInstance] performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
        #endif
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
        mobj = [self cacheForRating:[sessionSong valueForKeyPath:@"item.rating"] inSession:session moc:moc];
        if (mobj) {
            [mobj decrementPlayCount:playCount];
            [mobj decrementPlayTime:playTime];
        }
    
        NSCalendarDate *submitted = [NSCalendarDate dateWithTimeIntervalSince1970:
            [[sessionSong valueForKey:@"submitted"] timeIntervalSince1970]];
        NSNumber *hour = [NSNumber numberWithShort:[submitted hourOfDay]];
        mobj = [self cacheForHour:hour inSession:session moc:moc];
        if (mobj) {
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
    
    songs = [[PersistentProfile sharedInstance] ratingsForSession:session];
    totalPlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    totalPlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([totalPlayCount isEqualTo:[session valueForKey:@"playCount"]], "rating cache counts don't match session total!");
    ISASSERT([totalPlayTime isEqualTo:[session valueForKey:@"playTime"]], "rating cache times don't match session total!");
    
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
        ScrobDebug(@"removed %lu songs from session %@", [invalidSongs count], sessionName);
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
        
        ScrobDebug(@"recreated session %@ with %lu valid songs (%lu invalid)", sessionName, [validSongs count], [invalidSongs count]);
    }
    
    [session setValue:epoch forKey:@"epoch"];
    
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while updating session %@ (%@)", sessionName, e);
    }
    return (YES);
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
    (void)[[PersistentProfile sharedInstance] save:moc withNotification:didRemove];
#if IS_THREAD_SESSIONMGR
    if (didRemove) {
        [moc reset];
        [[PersistentProfile sharedInstance] performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
    }
#endif
    
    epoch = [epoch dateByAddingYears:0 months:0 days:7 hours:0 minutes:0 seconds:0];
    
    lfmUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:[epoch timeIntervalSinceNow]
        target:self selector:@selector(updateLastfmSession:) userInfo:nil repeats:NO] retain];
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
    
    (void)[[PersistentProfile sharedInstance] save:moc withNotification:didRemove];
#if IS_THREAD_SESSIONMGR
    if (didRemove) {
        [moc reset];
        [[PersistentProfile sharedInstance] performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
    }
#endif
    
#ifndef REAP_DEBUG
    midnight = [midnight dateByAddingYears:0 months:0 days:0 hours:24 minutes:0 seconds:0];
#else
    midnight = [now dateByAddingYears:0 months:0 days:0 hours:1 minutes:0 seconds:0];
#endif
    
    sUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:[midnight timeIntervalSinceNow]
        target:self selector:@selector(updateSessions:) userInfo:nil repeats:NO] retain];
}

- (void)processSongPlays:(NSArray*)queue
{
    NSManagedObjectContext *moc;
#if IS_THREAD_SESSIONMGR
    ISASSERT(mainThread && (mainThread != [NSThread currentThread]), "wrong thread!");
    
    moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread MOC!");
#else
    moc = [[PersistentProfile sharedInstance] mainMOC];
#endif
    
    [[PersistentProfile sharedInstance] setImportInProgress:YES];
    
    NSEnumerator *en;
    NSManagedObject *moSong;
    NSMutableArray *addedSongs = [NSMutableArray array];
    @try {
    
    en = [queue objectEnumerator];
    id obj;
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
#if IS_THREAD_SESSIONMGR
    // Turn the added songs into faults as we probably won't need them anytime soon
    // (we may need the artist/album/session objects though). This should save on some memory.
    en = [addedSongs objectEnumerator];
    while ((moSong = [en nextObject])) {
        [[moSong managedObjectContext] refreshObject:moSong mergeChanges:NO];
    }
#endif
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

- (void)updateSongHistory:(NSManagedObject*)psong count:(NSNumber*)count time:(NSNumber*)time moc:(NSManagedObjectContext*)moc
{
    // Create a last played history item
    NSManagedObject *lastPlayed;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSongLastPlayed" inManagedObjectContext:moc];
    lastPlayed = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
    [lastPlayed setValue:[psong valueForKey:@"lastPlayed"] forKey:@"lastPlayed"];
    [lastPlayed setValue:psong forKey:@"song"];
    
    [psong incrementPlayCount:count];
    [psong incrementPlayTime:time];
    [[psong valueForKey:@"artist"] incrementPlayCount:count];
    [[psong valueForKey:@"artist"] incrementPlayTime:time];
    [[psong valueForKey:@"artist"] setValue:[psong valueForKey:@"lastPlayed"] forKey:@"lastPlayed"];
    if ([psong valueForKey:@"album"]) {
        [[psong valueForKey:@"album"] incrementPlayCount:count];
        [[psong valueForKey:@"album"] incrementPlayTime:time];
    }
}

- (void)incrementSessionCountsWithSong:(NSManagedObject*)sessionSong moc:(NSManagedObjectContext*)moc
{
    NSManagedObject *orphans = [self orphanedItems:moc];
    NSManagedObject *session = [sessionSong valueForKey:@"session"];
    NSManagedObject *ratingsCache, *hoursCache;
    NSEntityDescription *entity;
    
    // Update the ratings cache
    ratingsCache = [self cacheForRating:[sessionSong valueForKeyPath:@"item.rating"] inSession:session moc:moc];
    if (!ratingsCache) {
        entity = [NSEntityDescription entityForName:@"PRatingCache" inManagedObjectContext:moc];
        ratingsCache = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [ratingsCache setValue:ITEM_RATING_CCH forKey:@"itemType"];
        [ratingsCache setValue:session forKey:@"session"];
        [ratingsCache setValue:orphans forKey:@"item"];
        [ratingsCache setValue:[sessionSong valueForKeyPath:@"item.rating"] forKey:@"rating"];
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
    if (trackTypeFile == [song type] && [psong valueForKey:@"importedPlayCount"] > 0) {
        // Make sure our play count is in sync with the player's
        NSNumber *count = [song playCount];
        if ([count unsignedIntValue] > 0 && [[psong valueForKey:@"playCount"] isNotEqualTo:count]) {
            [psong setValue:count forKey:@"playCount"];
            NSNumber *pTime = [psong valueForKey:@"duration"];
            pTime = [NSNumber numberWithUnsignedLongLong:[pTime unsignedLongLongValue] * [count unsignedLongLongValue]];
            [psong setValue:pTime forKey:@"playTime"];
            // Update album and artist with the delta as well?
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

@implementation SongData (PersistentAdditions)

- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
    @try {
    
    // tried optimizing this search by just searching for song titles and then limiting to artist/album in memory,
    // but it made no difference in speed
    NSPredicate *predicate;
    NSString *aTitle;
    if ((aTitle = [self album]) && [aTitle length] > 0) {
        predicate = [NSPredicate predicateWithFormat:
            @"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@) AND (album.name LIKE[cd] %@)",
            ITEM_SONG, [self title], [self artist], aTitle];
    } else {
        aTitle = nil;
        predicate = [NSPredicate predicateWithFormat:
            @"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@)",
            ITEM_SONG, [self title], [self artist]];
    }
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
            ITEM_ARTIST, [self artist]]];
    
    result = [moc executeFetchRequest:request error:&error];
    if (1 == [result count]) {
        moArtist = [result objectAtIndex:0];
    } else if (0 == [result count]) {
        moArtist = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [moArtist setValue:ITEM_ARTIST forKey:@"itemType"];
        [moArtist setValue:[self artist] forKey:@"name"];
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
                ITEM_ALBUM, aTitle, [self artist]]];
        
        result = [moc executeFetchRequest:request error:&error];
        if (1 == [result count]) {
            moAlbum = [result objectAtIndex:0];
        } else if (0 == [result count]) {
            moAlbum = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
            [moAlbum setValue:ITEM_ALBUM forKey:@"itemType"];
            [moAlbum setValue:aTitle forKey:@"name"];
            [moAlbum setValue:moArtist forKey:@"artist"];
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
        [request setPredicate:[NSPredicate predicateWithFormat:@"name LIKE[cd] %@", aTitle]];
        
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
    u_int32_t playCount = [[self valueForKey:@"playCount"] unsignedIntValue] - [count unsignedIntValue];
    [self setValue:[NSNumber numberWithUnsignedInt:playCount] forKey:@"playCount"];
}

- (void)decrementPlayTime:(NSNumber*)count
{
    u_int64_t playTime = [[self valueForKey:@"playTime"] unsignedLongLongValue] - [count unsignedLongLongValue];
    [self setValue:[NSNumber numberWithUnsignedLongLong:playTime] forKey:@"playTime"];
}

@end
