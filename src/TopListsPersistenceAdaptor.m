//
//  TopListsPersistenceAdaptor.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/21/07.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <libkern/OSAtomic.h>

#import "PersistentSessionManager.h"

#define IMPORT_CHUNK 50

@implementation TopListsController (PersistenceAdaptor)

- (BOOL)loading
{
    return (sessionLoads > 0 || [persistence importInProgress]);
}

- (void)setLoading:(BOOL)isLoading
{
    loadIssued = 0;
    if (isLoading)
        sessionLoads++;
    else
        sessionLoads--;
    
    ISASSERT(sessionLoads >= 0, "gone south!");
    
    if (sessionLoads <= 0) {
        OSMemoryBarrier();
        cancelLoad = 0;
        if (wantLoad) {
            wantLoad = 0;
            ScrobDebug(@"issuing delayed session load");
            [self performSelector:@selector(sessionDidChange:) withObject:nil afterDelay:0.05];
        }
    }
}

- (void)setLoadingWithBool:(NSNumber*)isLoading
{
    [self setValue:isLoading forKey:@"loading"];
}

#define ClearExtendedData() do { \
[topRatings release]; \
topRatings = nil; \
[topHours release]; \
topHours = nil; \
[artistComparisonData release]; \
artistComparisonData = nil; \
} while(0)

// methods that run on the main thread
- (void)sessionDidChange:(id)arg
{
    static NSManagedObjectID *lastSession = nil;
    
    NSManagedObjectID *oid = [[self selectedSession] objectID];
    if ([self loading]) {
        // Make sure we don't issue a load while one is in progress or we may have duplicate entries in the controllers
        if (lastSession && oid && ![lastSession isEqualTo:oid]) {
            OSMemoryBarrier();
            cancelLoad = 1;
            wantLoad = 1;
            ScrobDebug(@"load in progress, set want");
        }
        return;
    }
    if (lastSession != oid) {
        [lastSession release];
        lastSession = [oid retain];
        loadIssued = 0;
    } else if (loadIssued)
        return;
    
    if (windowIsVisisble && oid) {
        loadIssued = 1;
        [ISThreadMessenger makeTarget:persistenceTh performSelector:@selector(loadInitialSessionData:) withObject:oid];
    } else if (!oid) {
        ScrobDebug(@"missing session oid");
        #if 0
        [topArtistsController removeObjects:[topArtistsController content]];
        [topTracksController removeObjects:[topTracksController content]];
        #endif
    }
}

- (void)persistentProfileWillReset:(NSNotification*)note
{
    @try {
    if (persistenceTh) {
        if ([self loading]) {
            OSMemoryBarrier();
            cancelLoad = 1;
        }
        [ISThreadMessenger makeTarget:persistenceTh performSelector:@selector(resetPersistenceManager) withObject:nil];
    }
    } @catch (id e) {
    ScrobDebug(@"exception: %@", e);
    }

    @try {
    ClearExtendedData();
    
    [sessionController setContent:[NSMutableArray array]];
    [sessionController rearrangeObjects];
    }@catch (id e) {
    ScrobDebug(@"exception: %@", e);
    }
}

- (void)persistentProfileDidReset:(NSNotification*)note
{
    [self performSelector:@selector(persistentProfileDidUpdate:) withObject:note];
}

- (void)persistentProfileDidUpdate:(NSNotification*)note
{
    NSSet *updatedObjects = [[note userInfo] objectForKey:NSUpdatedObjectsKey];
    if (updatedObjects) {
        [ISThreadMessenger makeTarget:persistenceTh performSelector:@selector(managedObjectsDidUpdate:) withObject:updatedObjects];
    }   

    // update the session bindings that we use
    // it seems this is needed so the names will update when the underlying object is still a fault
    [self willChangeValueForKey:@"allSessions"];
    [self didChangeValueForKey:@"allSessions"];
    
    if ([self selectedSession]) {
        [[self selectedSession] willChangeValueForKey:@"playCount"];
        [[self selectedSession] didChangeValueForKey:@"playCount"];
    }
    
    [self sessionDidChange:nil];
}

- (void)persistenceManagerDidReset:(id)arg
{
    [self sessionDidChange:nil];
}

- (void)persistenceManagerDidStart:(id)arg
{
    static BOOL sinit = YES;
    
    if (sinit) {
        sinit = NO;
        
        // Persistence notes
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileDidUpdate:)
            name:PersistentProfileDidUpdateNotification
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileDidReset:)
            name:PersistentProfileDidResetNotification
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileWillReset:)
            name:PersistentProfileWillResetNotification
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileDidEditObject:)
            name:PersistentProfileDidEditObject
            object:nil];
        
        [self willChangeValueForKey:@"allSessions"];
        [self didChangeValueForKey:@"allSessions"];
    }
    
    // small delay to reduce the chance of a race with the bindings updating
    // (sessionDidChange: is called twice before the load thread even starts). It's no
    // big deal, but why do an extra load if we don't have to
    if (![self loading])
        [self performSelector:@selector(sessionDidChange:) withObject:nil afterDelay:0.0];
}

- (void)persistentProfileDidEditObject:(NSNotification*)note
{
    NSString *what = [[note userInfo] objectForKey:@"what"];
    if (what && ([what isEqualToString:@"addhist"] || [what isEqualToString:@"remhist"]))
        return;
    NSManagedObjectID *oid = [[note userInfo] objectForKey:@"oid"];
    [ISThreadMessenger makeTarget:persistenceTh performSelector:@selector(objectDidChange:) withObject:oid];
}

- (void)sessionWillLoad:(id)arg
{
    [self setValue:[NSNumber numberWithBool:YES] forKey:@"loading"];
    // remove the stale data
    [topArtistsController setContent:[NSMutableArray array]];
    [topTracksController setContent:[NSMutableArray array]];
    [topAlbumsController setContent:[NSMutableArray array]];
    ClearExtendedData();
}

- (void)finalizeSessionLoad:(id)arg
{
    [topArtistsController rearrangeObjects];
    [topTracksController rearrangeObjects];
    [topAlbumsController rearrangeObjects];
}

- (void)sessionDidLoad:(id)arg
{
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"loading"];
    [self performSelector:@selector(finalizeSessionLoad:) withObject:arg afterDelay:0.0];
}

- (void)displayEntries:(NSArray*)entries withController:(id)controller
{
    if (![controller isSearchInProgress]) {
        if ([entries count]) {
            [controller addObjects:entries];
        }
    } else {
         // Can't alter the arrangedObjects array when a search is active
        // So manually enter the item in the content array
        NSMutableArray *contents = [controller content];
        [contents addObjectsFromArray:entries];
        //[controller setContent:contents];
    }
}

- (void)displayArtistEntries:(NSArray*)entries
{
    [self displayEntries:entries withController:topArtistsController];
}

- (void)displayTrackEntries:(NSArray*)entries
{
    [self displayEntries:entries withController:topTracksController];
}

- (void)displayAlbumEntries:(NSArray*)entries
{
    [self displayEntries:entries withController:topAlbumsController];
}

- (void)loadExtendedDidFinish:(NSDictionary*)results
{
    if (results) {
        @try {
        
        ClearExtendedData(); // in case an exception is thrown
        
        topRatings = [[results objectForKey:@"ratings"] retain];
        topHours = [[results objectForKey:@"hours"] retain];
        artistComparisonData = [[results objectForKey:@"artistComparison"] retain]; 
        
        [self generateProfileReport];
        
        } @catch (id e) {
        ClearExtendedData();
        NSBeep();
        }
    } else
        NSBeep();
    
    // set in createProfileReport
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"loading"];
}

// methods that run on the background thread
- (void)objectDidChange:(NSManagedObjectID*)oid
{
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread moc!");
    
    NSManagedObject *obj = [moc objectRegisteredForID:oid];
    if (obj) {
        [obj refreshSelf];
        [self performSelectorOnMainThread:@selector(persistentProfileDidUpdate:) withObject:nil waitUntilDone:NO]; 
    }
}

- (void)managedObjectsDidUpdate:(NSSet*)updatedObjects
{
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread moc!");
    
    NSManagedObjectID *oid;
    NSEnumerator *en = [updatedObjects objectEnumerator];
    while ((oid = [en nextObject])) {
        NSManagedObject *mobj = [moc objectRegisteredForID:oid];
        if (mobj)
            [mobj refreshSelf];
    }
}

- (NSString*)rootNameOfSession:(NSManagedObject*)session
{
    // XXX: internal knowledge of archive naming convention
    NSString *sname = [session valueForKey:@"name"];
    NSRange r = [sname rangeOfString:@"-"];
    if (r.location != NSNotFound)
        return ([sname substringToIndex:r.location]);
    
    return (sname);
}

- (NSDictionary*)artistCountsForSessionPreviousTo:(NSManagedObject*)session
{
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread moc!");
    
    NSCalendarDate *sEpoch = [NSCalendarDate dateWithTimeIntervalSince1970:[[session valueForKey:@"epoch"] timeIntervalSince1970]];
    NSCalendarDate *sTerm = [NSCalendarDate dateWithTimeIntervalSince1970:[[session valueForKey:@"term"] timeIntervalSince1970]];
    NSInteger limit = (NSInteger)round([sTerm timeIntervalSinceDate:sEpoch] / 86400.0);
    if (limit > 7) {
        if (limit <= 31) {
            static const int daysInMonth[12] = {31,29,31,30,31,30,31,31,30,31,30,31};
            int i = [sEpoch monthOfYear] - 1; // -1 to index into our table
            if ((i -= 1) < 0) // -1 one more to get previous month
                i = 11;
            limit = daysInMonth[i];
        } else 
            limit += 1; // account for leap-years
    }
    NSCalendarDate *fromDate = [sEpoch dateByAddingYears:0 months:0 days:-(limit)
        hours:-([sEpoch hourOfDay]) minutes:-([sEpoch minuteOfHour]) seconds:-([sEpoch secondOfMinute]+1)];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:
        @"(itemType == %@) AND (self != %@) AND (archive != NULL) AND (epoch < %@) AND (epoch >= %@) AND (name BEGINSWITH %@)",
        ITEM_SESSION, session, [sEpoch GMTDate], [fromDate GMTDate], [self rootNameOfSession:session]];
    
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:predicate];
    [request setReturnsObjectsAsFaults:NO];
    
    NSArray *results = [moc executeFetchRequest:request error:&error];
    if ([results count] > 0) {
        // We should never get more than 1, but just in case:
        results = [results sortedArrayUsingDescriptors:
            [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"epoch" ascending:NO] autorelease]]];
        
        NSEnumerator *en;
        NSManagedObject *mobj;
        NSManagedObject *comparisonSession = [results objectAtIndex:0];
        ScrobLog(SCROB_LOG_TRACE, @"local charts: using session '%@' for artist movement comparison",
            [comparisonSession valueForKey:@"name"]);
        
        NSArray *cArtists = [[persistence sessionManager] artistsForSession:comparisonSession moc:moc];
        // prefetch the object releationship
        entity = [NSEntityDescription entityForName:@"PArtist" inManagedObjectContext:moc];
        [request setEntity:entity];
        [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", [cArtists valueForKeyPath:@"item.objectID"]]];
        error = nil;
        (void)[moc executeFetchRequest:request error:&error];
        
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:[cArtists count]];
        en = [cArtists objectEnumerator];
        while ((mobj = [en nextObject])) {
            [d setObject:[mobj valueForKey:@"playCount"] forKey:[mobj valueForKeyPath:@"item.name"]];
        }
        return (d);
    }
    return (nil);
}

- (void)loadInitialSessionData:(NSManagedObjectID*)sessionID
{
    if ([persistence importInProgress])
        return;

    [self performSelectorOnMainThread:@selector(sessionWillLoad:) withObject:nil waitUntilDone:YES];
    
    // if our last session load was large, reset the MOC so we reclaim some memory
    static NSUInteger lastLoadCount = 0;
    
    NSMutableDictionary *didLoadInfo = [NSMutableDictionary dictionary]; 
    
    @try {
    
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread moc!");
    
    if (lastLoadCount >= 5000UL /*XXX: arbitrary */) {
        @try {
            [moc reset];
        } @catch (NSException *ex) {}
    }
    
    NSNumber *yes = [NSNumber numberWithBool:YES];
    NSNumber *no = [NSNumber numberWithBool:NO];
    
    NSManagedObject *session = [moc objectWithID:sessionID];
    ISASSERT(session != nil, "session not found!");
    ScrobDebug(@"%@", [session valueForKey:@"name"]);
    NSDate *sessionEpoch = [[session valueForKey:@"epoch"] GMTDate];
    BOOL isRollingSession = NO == [[session valueForKey:@"name"] isEqualToString:@"all"];
    
    BOOL isV2 = [persistence isVersion2];
    BOOL isV3 = [persistence isVersion3];
    
    NSError *error = nil;
    NSEntityDescription *entity;
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    // get the session songs
    NSArray *sessionSongs = [persistence songsForSession:session];
    if (0 == (lastLoadCount = [sessionSongs count]))
        goto loadExit;
    //// ARTISTS ////
    NSArray *sessionArtists = [[persistence sessionManager] artistsForSession:session moc:moc];
    // pre-fetch the relationships (individual backing store faults are VERY expensive)
    // processing the artists is much less work and we can present the data faster to the user
    entity = [NSEntityDescription entityForName:@"PArtist" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", [sessionArtists valueForKeyPath:@"item.objectID"]]];
    error = nil;
    (void)[moc executeFetchRequest:request error:&error];

    // import the data into the GUI
    NSEnumerator *en;
    NSManagedObject *mobj;
    NSMutableDictionary *entry;
    u_int64_t secs;
    NSString *playTime;
    unsigned days, hours, minutes, seconds, i = 0;
    en = [sessionArtists objectEnumerator];
    NSAutoreleasePool *entryPool = [[NSAutoreleasePool alloc] init];
    NSMutableArray *chartEntries = [NSMutableArray arrayWithCapacity:IMPORT_CHUNK]; // alloc in loop pool!
    BOOL loadCanceled = NO;
    NSDate *firstPlayed;
    while ((mobj = [en nextObject])) {
        secs = [[mobj valueForKey:@"playTime"] unsignedLongLongValue];
        ISDurationsFromTime64(secs, &days, &hours, &minutes, &seconds);
        playTime = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [mobj valueForKeyPath:@"item.name"], @"Artist",
            [mobj valueForKey:@"playCount"], @"Play Count",
            [mobj valueForKey:@"playTime"], @"Total Duration",
            playTime, @"Play Time",
            // this can be used to get further info, or to edit the object
            [[mobj valueForKey:@"item"] objectID], @"objectID",
            nil];
        if (isV2 && isRollingSession && nil != (firstPlayed = [mobj valueForKeyPath:@"item.firstPlayed"])
            && [[firstPlayed GMTDate] isGreaterThanOrEqualTo:sessionEpoch]) {
            [entry setObject:yes forKey:@"New This Session"];
        } else
            [entry setObject:no forKey:@"New This Session"];
        [chartEntries addObject:entry];
        
        if (0 == (++i % IMPORT_CHUNK)) {
            // Display the entries in the GUI            
            [self performSelectorOnMainThread:@selector(displayArtistEntries:) withObject:chartEntries waitUntilDone:NO];
            [entryPool release];
            entryPool = [[NSAutoreleasePool alloc] init];
            chartEntries = [NSMutableArray arrayWithCapacity:IMPORT_CHUNK];
            
            OSMemoryBarrier();
            if ((loadCanceled = (cancelLoad > 0)))
                break;
        }
    }
    if (!loadCanceled && [chartEntries count] > 0)
        [self performSelectorOnMainThread:@selector(displayArtistEntries:) withObject:chartEntries waitUntilDone:NO];
    
    // send empty set to signal we are done
    [self performSelectorOnMainThread:@selector(displayArtistEntries:) withObject:[NSArray array] waitUntilDone:NO];
    [entryPool release];
    if (loadCanceled)
        goto loadExit;
    
    //// ABLUMS ////
    NSManagedObject *rootObj;
    NSArray *sessionAlbums = [[persistence sessionManager] albumsForSession:session moc:moc];
    // pre-fetch the albums
    entity = [NSEntityDescription entityForName:@"PAlbum" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", [sessionAlbums valueForKeyPath:@"item.objectID"]]];
    (void)[moc executeFetchRequest:request error:&error];
    error = nil;
    
    en = [sessionAlbums objectEnumerator];
    entryPool = [[NSAutoreleasePool alloc] init];
    chartEntries = [NSMutableArray arrayWithCapacity:IMPORT_CHUNK]; // alloc in loop pool!
    i = 0;
    while ((mobj = [en nextObject])) {        
        secs = [[mobj valueForKey:@"playTime"] unsignedLongLongValue];
        ISDurationsFromTime64(secs, &days, &hours, &minutes, &seconds);
        playTime = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
        rootObj = [mobj valueForKey:@"item"];
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [rootObj valueForKeyPath:@"artist.name"], @"Artist",
            [rootObj valueForKey:@"name"], @"Album",
            [mobj valueForKey:@"playCount"], @"Play Count",
            [mobj valueForKey:@"playTime"], @"Total Duration",
            playTime, @"Play Time",
            // this can be used to get further info, or to edit the object
            [rootObj objectID], @"objectID",
            nil];
        [chartEntries addObject:entry];
        
        if (0 == (++i % IMPORT_CHUNK)) {
            // Display the entries in the GUI            
            [self performSelectorOnMainThread:@selector(displayAlbumEntries:) withObject:chartEntries waitUntilDone:NO];
            [entryPool release];
            entryPool = [[NSAutoreleasePool alloc] init];
            chartEntries = [NSMutableArray arrayWithCapacity:IMPORT_CHUNK];
            
            OSMemoryBarrier();
            if ((loadCanceled = (cancelLoad > 0)))
                break;
        }
    }
    if (!loadCanceled && [chartEntries count] > 0)
        [self performSelectorOnMainThread:@selector(displayAlbumEntries:) withObject:chartEntries waitUntilDone:NO];
    
    // send empty set to signal we are done
    [self performSelectorOnMainThread:@selector(displayAlbumEntries:) withObject:[NSArray array] waitUntilDone:NO];
    [entryPool release];
    if (loadCanceled)
        goto loadExit;
    
    //// SONGS ////
    NSCountedSet *yearCounts = [NSCountedSet set];
    if (isV3)
        [didLoadInfo setObject:yearCounts forKey:@"yearCounts"];
    
    // pre-fetch the songs
    entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", [sessionSongs valueForKeyPath:@"item.objectID"]]];
    error = nil;
    (void)[moc executeFetchRequest:request error:&error];
    
    entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", sessionSongs]];
    [request setSortDescriptors:
        [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"item" ascending:NO] autorelease]]];
    sessionSongs = [moc executeFetchRequest:request error:&error];
    [request setSortDescriptors:nil];
    
    BOOL overallSession = [@"all" isEqualToString:[session valueForKey:@"name"]];
    NSManagedObject *mAlbum;
    NSMutableArray *allSongPlays = [NSMutableArray array]; // alloc outside of loop pool!
    // tracks however, have a session entry for each play and the GUI displays all track plays merged as one
    // so we have to do a little extra work;
    en = [sessionSongs objectEnumerator];
    entryPool = [[NSAutoreleasePool alloc] init];
    chartEntries = [NSMutableArray arrayWithCapacity:IMPORT_CHUNK]; // alloc in loop pool!
    i = 1;
    [allSongPlays addObject:[en nextObject]];
    while ((mobj = [en nextObject])) {
        rootObj = [[allSongPlays objectAtIndex:0] valueForKey:@"item"];
        NSNumber *rootYear = isV3 ? [rootObj valueForKey:@"year"] : nil;
        if ([[mobj valueForKey:@"item"] isEqualTo:rootObj]) {
            [allSongPlays addObject:mobj];
            
            if (isV3)
                [yearCounts addObject:rootYear];
            continue;
        }
        
        NSDate *lastPlayed;
        if (!overallSession) {
            lastPlayed = [[[allSongPlays valueForKeyPath:@"submitted"]
                sortedArrayUsingSelector:@selector(compare:)] lastObject];
            lastPlayed = [NSDate dateWithTimeIntervalSince1970:
                [lastPlayed timeIntervalSince1970] + [[rootObj valueForKey:@"duration"] unsignedIntValue]];
        } else
            lastPlayed = [rootObj valueForKey:@"lastPlayed"];
        
        mAlbum = [rootObj valueForKey:@"album"];
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [rootObj valueForKeyPath:@"artist.name"], @"Artist",
            [allSongPlays valueForKeyPath:@"playCount.@sum.unsignedIntValue"], @"Play Count",
            [allSongPlays valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"], @"Total Duration",
            [rootObj valueForKey:@"name"], @"Track",
            lastPlayed, @"Last Played",
            // these can be used to get further info, such as the complete play time history
            [rootObj objectID], @"objectID",
            [allSongPlays valueForKeyPath:@"objectID"], @"sessionInstanceIDs",
            [mAlbum valueForKey:@"name"], @"Album", // mAlbum may be nil
            nil];
        [chartEntries addObject:entry];
        
        [allSongPlays removeAllObjects];
        [allSongPlays addObject:mobj]; // starting a new track
        
        if (0 == (++i % IMPORT_CHUNK)) {
            // Display the entries in the GUI            
            [self performSelectorOnMainThread:@selector(displayTrackEntries:) withObject:chartEntries waitUntilDone:NO];
            [entryPool release];
            entryPool = [[NSAutoreleasePool alloc] init];
            chartEntries = [NSMutableArray arrayWithCapacity:IMPORT_CHUNK];
            
            OSMemoryBarrier();
            if ((loadCanceled = (cancelLoad > 0)))
                break;
        }
    }
    if ([allSongPlays count] > 0) {
        rootObj = [[allSongPlays objectAtIndex:0] valueForKey:@"item"];
        mAlbum = [rootObj valueForKey:@"album"];
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [rootObj valueForKeyPath:@"artist.name"], @"Artist",
            [allSongPlays valueForKeyPath:@"playCount.@sum.unsignedIntValue"], @"Play Count",
            [allSongPlays valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"], @"Total Duration",
            [rootObj valueForKey:@"name"], @"Track",
            [rootObj valueForKey:@"lastPlayed"], @"Last Played",
            // these can be used to get further info, such as the complete play time history
            [rootObj objectID], @"objectID",
            [allSongPlays valueForKeyPath:@"objectID"], @"sessionInstanceIDs",
            [mAlbum valueForKey:@"name"], @"Album", // mAlbum may be nil
            nil];
        [chartEntries addObject:entry];
    }
    
    if (!loadCanceled && [chartEntries count] > 0)
        [self performSelectorOnMainThread:@selector(displayTrackEntries:) withObject:chartEntries waitUntilDone:NO];
    
    // send empty set to signal we are done
    [self performSelectorOnMainThread:@selector(displayTrackEntries:) withObject:[NSArray array] waitUntilDone:NO];
    [entryPool release];
    
loadExit:
    // fault our copy of the session, just so we are assured of good data
    [moc refreshObject:session mergeChanges:NO];
    
    } @catch (NSException *ex) {
        ScrobLog(SCROB_LOG_ERR, @"[loadInitialSessionData:] exception: %@", ex);
        lastLoadCount = NSUIntegerMax; // force a MOC reset on the next load
    }
    
    [self performSelectorOnMainThread:@selector(sessionDidLoad:) withObject:didLoadInfo waitUntilDone:NO];
}

- (void)loadExtendedSessionData:(NSManagedObjectID*)sessionID // profile report data not seen in the GUI
{
    if ([persistence importInProgress])
        return;
    
    // loadInitial should have completed
    // this is loaded on demand mainly for memory reasons - CPU use shouldn't be too bad
    [self performSelectorOnMainThread:@selector(setLoadingWithBool:) withObject:[NSNumber numberWithBool:YES] waitUntilDone:YES];
    
    @try {
        
    NSManagedObjectContext *moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread moc!");

    NSManagedObject *session = [moc objectWithID:sessionID];
    ISASSERT(session != nil, "session not found!");
    
    NSManagedObject *mobj;
    NSMutableDictionary *entry;
    unsigned i;
    NSMutableDictionary *ratingEntries = [NSMutableDictionary dictionaryWithCapacity:5];
    NSArray *sessionRatings = [persistence ratingsForSession:session];
    NSEnumerator *en = [sessionRatings objectEnumerator];
    while ((mobj = [en nextObject])) {
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [mobj valueForKey:@"playCount"], @"Play Count",
            [mobj valueForKey:@"playTime"],  @"Total Duration",
            nil];
        [ratingEntries setObject:entry forKey:[mobj valueForKey:@"rating"]];
    }
    OSMemoryBarrier();
    if (cancelLoad > 0)
        goto loadExit;
    
    NSNumber *zero = [NSNumber numberWithInt:0];
    NSMutableArray *hourEntries = [NSMutableArray arrayWithCapacity:24];
    NSMutableDictionary *zeroHour = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        zero, @"Play Count", zero, @"Total Duration", nil];
    for (i = 0; i < 24; ++i) {
        [hourEntries addObject:zeroHour];
    }
    NSArray *sessionHours = [[persistence hoursForSession:session] sortedArrayUsingDescriptors:
        [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"hour" ascending:NO] autorelease]]];
    en = [sessionHours objectEnumerator];
    while ((mobj = [en nextObject])) {
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [mobj valueForKey:@"playCount"], @"Play Count",
            [mobj valueForKey:@"playTime"],  @"Total Duration",
            nil];
        [hourEntries replaceObjectAtIndex:[[mobj valueForKey:@"hour"] unsignedIntValue] withObject:entry];
    }
    OSMemoryBarrier();
    if (cancelLoad > 0)
        goto loadExit;
    
    // Attempt to get the data to compute artist movements. We only do this for archived time-bounded sessions.
    NSDictionary *artistComparison;
    NSString *sname = [session valueForKey:@"name"];
    if (nil != [session valueForKey:@"archive"]
        && ([sname hasPrefix:@"lastfm"] || [sname hasPrefix:@"monthtodate"] || [sname hasPrefix:@"yeartodate"])) {
        artistComparison = [self artistCountsForSessionPreviousTo:session];
    } else
        artistComparison = nil;
    
    OSMemoryBarrier();
    if (cancelLoad > 0)
        goto loadExit;
    
    NSDictionary *results = [NSDictionary dictionaryWithObjectsAndKeys:
        ratingEntries, @"ratings",
        hourEntries, @"hours",
        artistComparison, @"artistComparison", // can be nil
        nil];
    [self performSelectorOnMainThread:@selector(loadExtendedDidFinish:) withObject:results waitUntilDone:NO];
    
loadExit: ;
    } @catch (id e) {
        [self performSelectorOnMainThread:@selector(loadExtendedDidFinish:) withObject:nil waitUntilDone:NO];
        ScrobLog(SCROB_LOG_ERR, @"[loadExtendedSessionData:] exception: %@", e);
    }
    
    [self performSelectorOnMainThread:@selector(setLoadingWithBool:) withObject:[NSNumber numberWithBool:NO] waitUntilDone:NO];
}

- (void)sendPersistenceManagerDidStart:(NSTimer*)timer
{
    [self performSelectorOnMainThread:@selector(persistenceManagerDidStart:) withObject:nil waitUntilDone:NO];
}

- (void)resetPersistenceManager
{
    [[[[NSThread currentThread] threadDictionary] objectForKey:@"moc"] reset];
    [self performSelectorOnMainThread:@selector(persistenceManagerDidReset:) withObject:nil waitUntilDone:NO];
}

- (void)persistenceManagerThread:(id)arg
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] init];
    [moc setUndoManager:nil];
    // we don't allow the user to make changes and the session mgr background thread handles all internal changes
    [moc setMergePolicy:NSRollbackMergePolicy];
    id psc = [[persistence performSelector:@selector(mainMOC)] persistentStoreCoordinator];
    [moc setPersistentStoreCoordinator:psc];
    
    [[[NSThread currentThread] threadDictionary] setObject:moc forKey:@"moc"];
    
    persistenceTh = [[ISThreadMessenger scheduledMessengerWithDelegate:self] retain];
    
    (void)[NSTimer scheduledTimerWithTimeInterval:0.0 target:self selector:@selector(sendPersistenceManagerDidStart:) userInfo:nil repeats:NO];
    do {
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
        @try {
        [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        } @catch (id e) {
            ScrobLog(SCROB_LOG_TRACE, @"[top lists persistenceManager] uncaught exception: %@", e);
        }
    } while (1);
    
    ISASSERT(0, "top lists persistenceManager run loop exited!");
    [persistenceTh release];
    persistenceTh = nil;
    [pool release];
    [NSThread exit];
}

@end
