//
//  iTunesImport.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/7/2007.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "ISiTunesLibrary.h"
#import "PersistentSessionManager.h"

@interface SongData (iTunesImport)
- (SongData*)initWithiTunesXMLTrack:(NSDictionary*)track;
@end

// in PersistentSessionManager.m
@interface SongData (PersistentAdditions)
- (NSPredicate*)matchingPredicateWithTrackNum:(BOOL)includeTrackNum;
- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc;
@end

@implementation PersistentProfileImport

- (void)killCachedObjects
{
    [currentArtist release];
    currentArtist = nil;
    [currentAlbum release];
    currentAlbum = nil;
    
    [moSession release];
    moSession = nil;
    [moPlayer release];
    moPlayer = nil;
    [moArtist release];
    moArtist = nil;
    [moAlbum release];
    moAlbum = nil;
    
    [mosArtist release];
    mosArtist = nil;
    [mosAlbum release];
    mosAlbum = nil;
}

#if IS_STORE_V2
- (void)createSessionEntriesForSong:(NSManagedObject*)psong withHistory:(NSArray*)playHistory
{
    PersistentSessionManager *smgr = [profile sessionManager];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    NSEntityDescription *histEntity = [NSEntityDescription entityForName:@"PSongLastPlayed" inManagedObjectContext:moc];
    NSArray *sessions = [[smgr activeSessionsWithMOC:moc] arrayByAddingObjectsFromArray:
        [smgr archivedSessionsWithMOC:moc weekLimit:0]];
    NSNumber *playCount = [NSNumber numberWithInteger:1];
    NSNumber *playTime = [psong valueForKey:@"duration"];
    #ifdef WTF
    // // Why does a set fail a valid [containsObject:] test when an array does not!! Cocoa bug?
    NSSet *currentHistory = [[[psong valueForKey:@"playHistory"] valueForKey:@"lastPlayed"] valueForKey:@"GMTDate"];
    #else
    NSArray *currentHistory = [[[[psong valueForKey:@"playHistory"] valueForKey:@"lastPlayed"] valueForKey:@"GMTDate"] allObjects];
    #endif
    
    playHistory = [playHistory valueForKey:@"GMTDate"];
    for (NSDate *lastPlayed in playHistory) {
        // add to sessions
        // XXX: playTime is assumed to be equal to the song duration
        NSCalendarDate *submitted = [NSCalendarDate dateWithTimeIntervalSince1970:
            [lastPlayed timeIntervalSince1970] - [playTime unsignedIntValue]];
        NSManagedObject *sessionSong, *session;
        for (session in sessions) {
            if ([[session valueForKey:@"name"] isEqualTo:@"all"])
                continue;
            
            NSDate *term = [[session valueForKey:@"term"] GMTDate];
            if ([lastPlayed isLessThan:[[session valueForKey:@"epoch"] GMTDate]]
                || (term && [lastPlayed isGreaterThan:term])) {
                continue;
            }
            
            sessionSong = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
            [sessionSong setValue:ITEM_SONG forKey:@"itemType"];
            [sessionSong setValue:psong forKey:@"item"];
            [sessionSong setValue:submitted forKey:@"submitted"];
            [sessionSong setValue:[psong valueForKey:@"rating"] forKey:@"rating"];
            [sessionSong incrementPlayCount:playCount];
            [sessionSong incrementPlayTime:playTime];
            
            if (![smgr addSessionSong:sessionSong toSession:session moc:moc]) 
                [moc deleteObject:sessionSong];
        }
        
        if (NO == [currentHistory containsObject:lastPlayed]) {
            NSManagedObject *he = [[[NSManagedObject alloc] initWithEntity:histEntity insertIntoManagedObjectContext:moc] autorelease];
            [he setValue:lastPlayed forKey:@"lastPlayed"];
            [he setValue:psong forKey:@"song"];
        }
    }
}

- (void)createSessionArchives:(NSArray*)entries
{
    NSEntityDescription *sessionEntity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
    NSEntityDescription *archiveEntity = [NSEntityDescription entityForName:@"PSessionArchive" inManagedObjectContext:moc];
    
    for (NSDictionary *entry in entries) {
        NSManagedObject *session = [[NSManagedObject alloc] initWithEntity:sessionEntity insertIntoManagedObjectContext:moc];
        [session setValue:ITEM_SESSION forKey:@"itemType"];
        [session setValue:[entry objectForKey:@"name"] forKey:@"name"];
        [session setValue:[entry objectForKey:@"epoch"] forKey:@"epoch"];
        [session setValue:[entry objectForKey:@"localizedName"] forKey:@"localizedName"];
        [session setValue:[entry objectForKey:@"term"] forKey:@"term"];
        
        NSManagedObject *sArchive = [[NSManagedObject alloc] initWithEntity:archiveEntity insertIntoManagedObjectContext:moc];
        [session setValue:sArchive forKey:@"archive"];
        [sArchive setValue:[entry objectForKey:@"created"] forKey:@"created"];
        
        [sArchive release];
        [session release];
    }
}
#endif // IS_STORE_V2

/** This is faster than [addSongPlay:] when aggregated over many imports,
     as it makes assumptions to avoid searching as much as possible:
     1: There are no existing artists or albums
     2: The DB will not be modified by other threads during an import
**/
- (NSManagedObject*)importSong:(SongData*)song withPlayCount:(NSNumber*)playCount
{
    NSError *error;
    NSEntityDescription *entity;
    NSPredicate *predicate;
    NSString *aTitle;
    
    @try {
    
    PersistentSessionManager *sMgr = [profile sessionManager];
    
    NSManagedObject *moSong, *mosSong;
    if (!currentArtist || NSOrderedSame != [currentArtist caseInsensitiveCompare:[song artist]]) {
        // Saving less often is a much greater performance gain (as opposed to saving after every track)
        // than [importSong:] vs [addSong:]
        (void)[profile save:moc withNotification:NO];
        [moc reset]; // purge memory
        
        [self killCachedObjects];
        
        // recreate our cached objects 
        currentArtist = [[song artist] retain];
        
        moSession = [[sMgr sessionWithName:@"all" moc:moc] retain];
        moPlayer = [[profile playerWithName:@"iTunes" moc:moc] retain];
        
        entity = [NSEntityDescription entityForName:@"PArtist" inManagedObjectContext:moc];
        moArtist = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc];
        [moArtist setValue:ITEM_ARTIST forKey:@"itemType"];
        [moArtist setValue:[song artist] forKey:@"name"];
        
        entity = [NSEntityDescription entityForName:@"PSessionArtist" inManagedObjectContext:moc];
        mosArtist = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc];
        [mosArtist setValue:ITEM_ARTIST forKey:@"itemType"];
        [mosArtist setValue:moArtist forKey:@"item"];
        [mosArtist setValue:moSession forKey:@"session"];
    }
    
    if (!currentAlbum || NSOrderedSame != [currentAlbum caseInsensitiveCompare:[song album]]) {
        [currentAlbum release];
        currentAlbum = [[song album] retain];
        
        [moAlbum release];
        moAlbum = nil;
        [mosAlbum release];
        mosAlbum = nil;
        
        // create new album
        if (currentAlbum && [currentAlbum length] > 0) {
            entity = [NSEntityDescription entityForName:@"PAlbum" inManagedObjectContext:moc];
            moAlbum = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc];
            [moAlbum setValue:ITEM_ALBUM forKey:@"itemType"];
            [moAlbum setValue:currentAlbum forKey:@"name"];
            [moAlbum setValue:moArtist forKey:@"artist"];
            
            // create new session album
            entity = [NSEntityDescription entityForName:@"PSessionAlbum" inManagedObjectContext:moc];
            mosAlbum = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc];
            [mosAlbum setValue:ITEM_ALBUM forKey:@"itemType"];
            [mosAlbum setValue:moAlbum forKey:@"item"];
            [mosAlbum setValue:moSession forKey:@"session"];
        }
    }
    
    // the track may be a duplicate, so we have to search for an existing one
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    [request setEntity:entity];
    // Matching on track number may give us duplicates in our db if the user is sloppy about meta-data.
    // However, there are several albums that contain different tracks musically but with the same title.
    predicate = [song matchingPredicateWithTrackNum:YES];
    [request setPredicate:predicate];
    
    NSNumber *playTime;
    playTime = [NSNumber numberWithUnsignedLongLong:[playCount unsignedLongLongValue] * [[song duration] unsignedLongLongValue]];
    NSArray *result = [moc executeFetchRequest:request error:&error];
    if (1 == [result count]) {
         // Update song values
        moSong = [result objectAtIndex:0];
        ScrobDebug(@"import: %@ already in database as (%@, %@, %@)", [song brief],
            [moSong valueForKey:@"name"], [[moSong valueForKey:@"album"] valueForKey:@"name"],
            [[moSong valueForKey:@"artist"] valueForKey:@"name"]);
        NSDate *prevLastPlayed = [moSong valueForKey:@"lastPlayed"];
        [moSong setValue:[song lastPlayed] forKey:@"lastPlayed"];
        [sMgr updateSongHistory:moSong count:playCount time:playTime moc:moc];
        if ([[[song lastPlayed] GMTDate] isLessThan:[prevLastPlayed GMTDate]])
            [moSong setValue:prevLastPlayed forKey:@"lastPlayed"];
        
        [moSong valueForKey:@"sessionAliases"];
        
        // Get the session alias, there should only be one
        entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
        [request setEntity:entity];
        predicate = [NSPredicate predicateWithFormat:@"(item == %@) AND (session == %@)", moSong, moSession];
        [request setPredicate:predicate];
        NSArray *aliases = [moc executeFetchRequest:request error:&error];
        ISASSERT([aliases count] > 0, "invalid state - missing session aliases!");
        mosSong = [aliases lastObject];
        [mosSong incrementPlayCount:playCount];
        [mosSong incrementPlayTime:playTime];
    } else {
        // Song not found
        ISASSERT(0 == [result count], "multiple songs found in db!");
        
        // Create the song
        NSCalendarDate *myLastPlayed = [NSCalendarDate dateWithTimeIntervalSince1970:
            [[song postDate] timeIntervalSince1970] + [[song duration] unsignedIntValue]];
        moSong = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [moSong setValue:ITEM_SONG forKey:@"itemType"];
        [moSong setValue:[song title] forKey:@"name"];
        [moSong setValue:[song duration] forKey:@"duration"];
        [moSong setValue:[song postDate] forKey:@"submitted"];
        [moSong setValue:myLastPlayed forKey:@"firstPlayed"];
        [moSong setValue:myLastPlayed forKey:@"lastPlayed"];
        [moSong setValue:[song rating] forKey:@"rating"];
        if ([[song trackNumber] intValue] > 0)
            [moSong setValue:[song trackNumber] forKey:@"trackNumber"];
        if ([[song mbid] length] > 0)
            [moSong setValue:[song mbid] forKey:@"mbid"];
        [moSong setValue:playCount forKey:@"importedPlayCount"];
        
        [moSong setValue:moArtist forKey:@"artist"];
        [moSong setValue:moAlbum forKey:@"album"];
        [moSong setValue:moPlayer forKey:@"player"];
        [sMgr updateSongHistory:moSong count:playCount time:playTime moc:moc];
        
        // Create the session alias
        entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
        mosSong = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [mosSong setValue:ITEM_SONG forKey:@"itemType"];
        [mosSong setValue:moSong forKey:@"item"];
        [mosSong setValue:[moSong valueForKey:@"submitted"] forKey:@"submitted"];
        [mosSong setValue:moSession forKey:@"session"];
        #if IS_STORE_V2
        [mosSong setValue:[song rating] forKey:@"rating"];
        #endif
        [mosSong incrementPlayCount:playCount];
        [mosSong incrementPlayTime:playTime];
    }
    
    // update session counts
    [mosArtist incrementPlayCountWithObject:mosSong];
    [mosArtist incrementPlayTimeWithObject:mosSong];
    if (mosAlbum) {
        [mosAlbum incrementPlayCountWithObject:mosSong];
        [mosAlbum incrementPlayTimeWithObject:mosSong];
    }
    [sMgr incrementSessionCountsWithSong:mosSong moc:moc];
    
    return (moSong);
    
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception creating song for %@ (%@)", [song brief], e);
    }
    
    return (nil);
}

- (void)importiTunesDB:(id)importArgs
{
    u_int32_t totalTracks = 0;
    u_int32_t importedTracks = 0;
    ISElapsedTimeInit();

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    profile = [PersistentProfile sharedInstance];
    moc = [[NSManagedObjectContext alloc] init];
    [moc setPersistentStoreCoordinator:[[profile valueForKey:@"mainMOC"] persistentStoreCoordinator]];
    [moc setUndoManager:nil];
    LEOPARD_BEGIN
    if (![NSThread isMainThread])
        [[[NSThread currentThread] threadDictionary] setObject:moc forKey:@"moc"];
    LEOPARD_END
    
    double pri = [NSThread threadPriority];
    [NSThread setThreadPriority:pri - (pri * 0.20)];
    
    NSString *importFilePath = [importArgs objectForKey:@"xmlFile"];
    PersistentSessionManager *smgr = [profile sessionManager];
    [profile setStoreMetadata:[NSNumber numberWithBool:YES] forKey:@"ISWillImportiTunesLibrary" moc:moc];
    
    #if IS_STORE_V2
    if (importFilePath) {
        // we are going to assume that this is an import of an XML dump from a failed migration, so
        // setup the session epochs so play history is added
        @try {
            for (NSManagedObject *session in [smgr activeSessionsWithMOC:moc]) {
                [session setValue:[NSDate distantPast] forKey:@"epoch"];
            }
            [smgr performSelector:@selector(sessionManagerUpdate) withObject:nil];
        } @catch (NSException *e) {
            ScrobDebug("%@", e);
        }
    }
    #endif
    
    [profile setImportInProgress:YES];
    @try {
    
    // begin import note
    NSNotification *note = [NSNotification notificationWithName:PersistentProfileImportProgress object:self userInfo:
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:totalTracks], @"total",
            [NSNumber numberWithUnsignedInt:0], @"imported", nil]];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];
    
    ISStartTime();
    
    NSMutableDictionary *iTunesLib;
    if (importFilePath) {
        iTunesLib = [[[ISiTunesLibrary sharedInstance] loadFromPath:importFilePath] mutableCopy];
        #if IS_STORE_V2
        NSDate *creation = [iTunesLib objectForKey:(NSString*)kMDItemContentCreationDate];
        for (NSManagedObject *session in [smgr activeSessionsWithMOC:moc]) {
            if ([creation isGreaterThan:[session valueForKey:@"epoch"]])
                [session setValue:creation forKey:@"epoch"];
        }
        
        [self createSessionArchives:[iTunesLib objectForKey:@"org.iScrobbler.Archives"]];
        #endif
    } else
        iTunesLib = [[[ISiTunesLibrary sharedInstance] load] mutableCopy];
    if (!iTunesLib) {
        @throw ([NSException exceptionWithName:NSGenericException reason:@"iTunes XML Library not found" userInfo:nil]);
    }
    
    [pool release];
    pool = [[NSAutoreleasePool alloc] init];
    (void)[iTunesLib autorelease];
    
    // Sorting the array allows us to optimze the import by eliminating the need to search for existing artist/albums in our nacent db
    NSArray *allTracks = [[[iTunesLib objectForKey:@"Tracks"] allValues]
        sortedArrayUsingDescriptors:[NSArray arrayWithObjects:
        [[[NSSortDescriptor alloc] initWithKey:@"Artist" ascending:YES selector:@selector(caseInsensitiveCompare:)] autorelease],
        [[[NSSortDescriptor alloc] initWithKey:@"Album" ascending:YES selector:@selector(caseInsensitiveCompare:)] autorelease],
        [[[NSSortDescriptor alloc] initWithKey:@"Play Date UTC" ascending:NO] autorelease],
        nil]];
    [iTunesLib setValue:allTracks forKey:@"Tracks"];
    NSString *uuid = [iTunesLib objectForKey:@"Library Persistent ID"];
    
    ISEndTime();
    ScrobDebug(@"Opened iTunes Library in %.4lf seconds", (abs2clockns / 1000000000.0));
    ISStartTime();
    
    totalTracks = (typeof(totalTracks))[allTracks count];
    
    NSNumber *epochSecs;
    if (!(epochSecs = [[iTunesLib objectForKey:@"org.iScrobbler.PlayEpoch"] valueForKey:@"timeIntervalSince1970"]))
        epochSecs = [allTracks valueForKeyPath:@"Date Added.@min.timeIntervalSince1970"];
    if (!epochSecs)
        @throw ([NSException exceptionWithName:NSGenericException reason:@"could not calculate library epoch" userInfo:nil]);
    
    NSCalendarDate *epoch = [NSCalendarDate dateWithTimeIntervalSince1970:[epochSecs doubleValue]];
    
    NSManagedObject *allSession = [[profile sessionManager] sessionWithName:@"all" moc:moc];
    ISASSERT(allSession != nil, "missing all session!");
    [allSession setValue:epoch forKey:@"epoch"];
    allSession = nil;
    
    BOOL skipDisabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"iTunesImportSkipDisabledTrack"];
    NSDictionary *track;
    NSEnumerator *en = [allTracks objectEnumerator];
    SongData *song;
    
    NSAutoreleasePool *trackPool = [[NSAutoreleasePool alloc] init];
    while ((track = [en nextObject])) {
        @try {
            song = [[[SongData alloc] initWithiTunesXMLTrack:track] autorelease];
        } @catch (id e) {
            song = nil;
            ScrobLog(SCROB_LOG_WARN, @"exception while importing iTunes track %@ (%@)",
                [NSString stringWithFormat:@"'%@ by %@'", [track objectForKey:@"Name"],
                    [track objectForKey:@"Artist"]],
                e);
        }
        
        BOOL disabled = [track objectForKey:@"Disabled"] ? [[track objectForKey:@"Disabled"] boolValue] : NO;
        if (!song || [song ignore] || (skipDisabled && disabled))
            continue;
        
        [[moc persistentStoreCoordinator] lock];
        NSManagedObject *psong = [self importSong:song withPlayCount:[track objectForKey:@"Play Count"]];
        #if IS_STORE_V2
        if (psong)
            [self createSessionEntriesForSong:psong withHistory:[track objectForKey:@"org.iScrobbler.PlayHistory"]];
        #else
        #pragma unused (psong)
        #endif
        [[moc persistentStoreCoordinator] unlock];
        ++importedTracks;

        if (0 == (importedTracks % 100)) {
            note = [NSNotification notificationWithName:PersistentProfileImportProgress object:self userInfo:
                [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:totalTracks], @"total",
                    [NSNumber numberWithUnsignedInt:importedTracks], @"imported", nil]];
            [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];
#ifdef ISDEBUG
            ISEndTime();
            ScrobDebug(@"Imported %u tracks (of %u) in %.4lf seconds", importedTracks, totalTracks, (abs2clockns / 1000000000.0));
#endif
        }
        
        [trackPool release];
        trackPool = [[NSAutoreleasePool alloc] init];
    }
    
    // end import note
    note = [NSNotification notificationWithName:PersistentProfileImportProgress object:self userInfo:
        [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:totalTracks] forKey:@"total"]];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];

    [trackPool release];
    trackPool = nil;
    
    if (uuid && [uuid length] > 0) {
        [[profile playerWithName:@"iTunes" moc:moc] setValue:uuid forKey:@"libraryUUID"];
    }
    
    [profile setStoreMetadata:nil forKey:@"ISWillImportiTunesLibrary" moc:moc];
    [profile setStoreMetadata:[NSNumber numberWithBool:YES] forKey:@"ISDidImportiTunesLibrary" moc:moc];
    id val;
    if ((val = [iTunesLib objectForKey:(NSString*)kMDItemContentCreationDate])) {
        [profile setStoreMetadata:[profile storeMetadataForKey:(NSString*)kMDItemContentCreationDate moc:moc]
            forKey:@"ISImportDate" moc:moc];
        [profile setStoreMetadata:val forKey:(NSString*)kMDItemContentCreationDate moc:moc];
    }
    if ((val = [iTunesLib objectForKey:NSStoreUUIDKey]))
        [profile setStoreMetadata:val forKey:[@"ISImport-" stringByAppendingString:NSStoreUUIDKey] moc:moc];
    
    // setStoreMetadata saves the moc for us
        
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while importing iTunes library (%@)", e);
    }
    
    [self killCachedObjects];
    [moc release];
    
    ISEndTime();
    ScrobDebug(@"Imported %u tracks (of %u) in %.4lf seconds", importedTracks, totalTracks, (abs2clockns / 1000000000.0));
    
    [profile performSelectorOnMainThread:@selector(importDidFinish:) withObject:nil waitUntilDone:NO];
    [pool release];
    
    [NSThread exit];
}

- (void)syncWithiTunes
{
    u_int32_t totalTracks = 0;
    u_int32_t importedTracks = 0;
    ISElapsedTimeInit();

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    ISASSERT(moc == nil, "existing MOC!");
    moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread MOC!");
    PersistentProfile *profile = [PersistentProfile sharedInstance];

    @try {
    
    // begin import note
    NSNotification *note = [NSNotification notificationWithName:PersistentProfileImportProgress object:self userInfo:
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:totalTracks], @"total",
            [NSNumber numberWithUnsignedInt:0], @"imported", nil]];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];
    
    ISStartTime();
    
    NSDictionary *iTunesLib;
    if (!(iTunesLib = [[ISiTunesLibrary sharedInstance] load])) {
        @throw ([NSException exceptionWithName:NSGenericException reason:@"iTunes XML Library not found" userInfo:nil]);
    }
    
    NSArray *allTracks = [[[iTunesLib objectForKey:@"Tracks"] allValues] retain];
    NSString *uuid = [[iTunesLib objectForKey:@"Library Persistent ID"] retain];
    iTunesLib = nil;
    
    [pool release];
    pool = [[NSAutoreleasePool alloc] init];
    (void)[allTracks autorelease];
    (void)[uuid autorelease];
    
    ISEndTime();
    ScrobDebug(@"Opened iTunes Library in %.4lf seconds", (abs2clockns / 1000000000.0));
    ISStartTime();
    
    totalTracks = (typeof(totalTracks))[allTracks count];
    
    BOOL skipDisabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"iTunesImportSkipDisabledTrack"];
    NSDictionary *track;
    NSEnumerator *en = [allTracks objectEnumerator];
    SongData *song;
    NSMutableSet *processedSongs = [NSMutableSet set];
    PersistentSessionManager *psm = [[PersistentProfile sharedInstance] sessionManager];
    
    NSAutoreleasePool *trackPool = [[NSAutoreleasePool alloc] init];
    while ((track = [en nextObject])) {
        @try {
            song = [[[SongData alloc] initWithiTunesXMLTrack:track] autorelease];
        } @catch (id e) {
            song = nil;
            ScrobLog(SCROB_LOG_WARN, @"exception while creating iTunes track %@ (%@)",
                [NSString stringWithFormat:@"'%@ by %@'", [track objectForKey:@"Name"],
                    [track objectForKey:@"Artist"]],
                e);
        }
        
        BOOL disabled = [track objectForKey:@"Disabled"] ? [[track objectForKey:@"Disabled"] boolValue] : NO;
        if (!song || [song ignore] || (skipDisabled && disabled))
            continue;
        
        NSManagedObject *psong = [song persistentSongWithContext:moc];
        if (psong) {
            NSNumber *playCount;
            #if IS_STORE_V2
            playCount = [NSNumber numberWithUnsignedLongLong:
                [[track objectForKey:@"Play Count"] unsignedIntValue] + [[psong valueForKey:@"nonLocalPlayCount"] unsignedIntValue]];
            #else
            playCount = [track objectForKey:@"Play Count"];
            #endif
            NSNumber *playTime = [NSNumber numberWithUnsignedLongLong:
                (u_int64_t)[playCount unsignedIntValue] * (u_int64_t)[[psong valueForKey:@"duration"] unsignedIntValue]];
            
            BOOL dupe = [processedSongs containsObject:psong];
            if ([playCount isNotEqualTo:[psong valueForKey:@"playCount"]]
                || [playTime isNotEqualTo:[psong valueForKey:@"playTime"]] || dupe) {
                ScrobLog(SCROB_LOG_TRACE, @"%@ counts don't match: iTunes count=%@, DB count=%@, iTunes time=%@, DB time=%@",
                    [song brief], playCount, [psong valueForKey:@"playCount"], playTime, [psong valueForKey:@"playTime"]);
                
                if ([[[song lastPlayed] GMTDate] isGreaterThan:[[psong valueForKey:@"lastPlayed"] GMTDate]])
                    [psong setValue:[song lastPlayed] forKey:@"lastPlayed"];
                
                if (NO == dupe) {
                    [psong setValue:playCount forKey:@"playCount"];
                    [psong setValue:playTime forKey:@"playTime"];
                    [processedSongs addObject:psong];
                } else {
                    ScrobLog(SCROB_LOG_TRACE, @"duplicate song: %@", [song brief]);
                    [psong incrementPlayCount:playCount];
                    [psong incrementPlayTime:playTime];
                }   
            } else
                [psong refreshSelf]; // release mem
            
            ++importedTracks;
        } else {
            [psm addSongPlay:song withImportedPlayCount:[track objectForKey:@"Play Count"] moc:moc];
            ScrobLog(SCROB_LOG_TRACE, @"iTunes sync: added song %@", [song brief]);
        }
        
        if (0 == (importedTracks % 100)) {
            [trackPool release];
            trackPool = [[NSAutoreleasePool alloc] init];
            
            note = [NSNotification notificationWithName:PersistentProfileImportProgress object:self userInfo:
                [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:totalTracks], @"total",
                    [NSNumber numberWithUnsignedInt:importedTracks], @"imported", nil]];
            [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];
#ifdef ISDEBUG
            ISEndTime();
            ScrobDebug(@"Synchronized %u tracks (of %u) in %.4lf seconds", importedTracks, totalTracks, (abs2clockns / 1000000000.0));
#endif
        }
    }
    
    // end import note
    note = [NSNotification notificationWithName:PersistentProfileImportProgress object:self userInfo:
        [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:totalTracks] forKey:@"total"]];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];

    [trackPool release];
    trackPool = nil;
    
    if (uuid && [uuid length] > 0) {
        [[[PersistentProfile sharedInstance] playerWithName:@"iTunes" moc:moc] setValue:uuid forKey:@"libraryUUID"];
    }
    
    [moc save:nil];
        
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while syncing iTunes library (%@)", e);
        [moc rollback];
    }
    
    ISEndTime();
    ScrobDebug(@"Synced %u tracks (of %u) in %.4lf seconds", importedTracks, totalTracks, (abs2clockns / 1000000000.0));
    
    [pool release];
}

@end

@implementation SongData (iTunesImport)

- (SongData*)initWithiTunesXMLTrack:(NSDictionary*)track
{
    id obj;
    
    if (!(obj = [track objectForKey:@"Name"]) || 0 == [obj length]) {
        [self autorelease];
        @throw ([NSException exceptionWithName:NSGenericException reason:@"missing track name" userInfo:nil]);
    }
    [self setTitle:obj];
    
    if (!(obj = [track objectForKey:@"Artist"]) || 0 == [obj length]) {
        [self autorelease];
        @throw ([NSException exceptionWithName:NSGenericException reason:@"missing artist" userInfo:nil]);
    }
    [self setArtist:obj];
    
    if ((obj = [track objectForKey:@"Location"]) && NO == [[NSURL URLWithString:obj] isFileURL]) {
        [self autorelease];
        @throw ([NSException exceptionWithName:NSGenericException reason:@"unsupported file type" userInfo:nil]);
    }
    if (!(obj = [track objectForKey:@"Play Date UTC"])) {
        [self autorelease];
        return (nil); // just return nil, so there's no warning log
        //@throw ([NSException exceptionWithName:NSGenericException reason:@"missing play date" userInfo:nil]);
    }
    
    obj = [NSCalendarDate dateWithTimeIntervalSince1970:[obj timeIntervalSince1970]];
    [self setLastPlayed:obj];
    
    [self setType:trackTypeFile];
    
    if ((obj = [track objectForKey:@"Album"]) && [obj length] > 0)
        [self setAlbum:obj];
    if ((obj = [track objectForKey:@"Track Number"]))
        [self setTrackNumber:obj];
    if (!(obj = [track objectForKey:@"Rating"]))
        obj = [NSNumber numberWithInt:0];
    [self setRating:obj];
    if (!(obj = [track objectForKey:@"Comments"]))
        obj = @"";
    [self setComment:obj];
    if (!(obj = [track objectForKey:@"Genre"]))
        obj = @"";
    [self setGenre:obj];
    [self setIsPlayeriTunes:YES];
    obj = [NSNumber numberWithUnsignedLongLong:[[track objectForKey:@"Total Time"] unsignedLongLongValue] / 1000];
    [self setDuration:obj];
    [self setPostDate:[NSDate dateWithTimeIntervalSince1970:
        [[self lastPlayed] timeIntervalSince1970] - [[self duration] unsignedIntValue]]];
    [self setStartTime:[self postDate]];
    
    return (self);
}

@end
