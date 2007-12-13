//
//  Persistence.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/3/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <libkern/OSAtomic.h>

#import "Persistence.h"
#import "PersistentSessionManager.h"
#import "SongData.h"

/**
Simple CoreDate overview: http://cocoadevcentral.com/articles/000086.php
Important CoreData behaviors:
http://www.cocoadev.com/index.pl?CoreDataInheritanceIssues
http://www.cocoadev.com/index.pl?CoreDataQuestions

Performance of the SQL store can be SEVERLY impacted by a slow hard disk (e.g. 4200RPM laptop drive)
On import, setting "com.apple.CoreData.SQLiteDebugSynchronous" to 1 or 0 should help a lot
(at the risk of data corruption if the machine crashes or loses power).
**/

#define PERSISTENT_STORE_DB \
[@"~/Library/Application Support/org.bergstrand.iscrobbler.persistent.toplists.data" stringByExpandingTildeInPath]

#define IS_THREAD_IMPORT 1

#if IS_THREAD_SESSIONMGR
#import "ISThreadMessenger.h"
#ifdef ISDEBUG
__private_extern__ NSThread *mainThread = nil;
#endif
#endif

@interface NSManagedObject (ISProfileAdditions)
- (void)refreshSelf;
@end

@interface PersistentProfileImport : NSObject {
    PersistentProfile *profile;
    NSString *currentArtist, *currentAlbum;
    NSManagedObjectContext *moc;
    NSManagedObject *moArtist, *moAlbum, *moSession, *mosArtist, *mosAlbum, *moPlayer;
}

- (void)importiTunesDB:(id)obj;
@end

@interface PersistentProfile (SessionManagement)
- (void)pingSessionManager;
- (BOOL)addSongPlaysToAllSessions:(NSArray*)queue;
- (PersistentSessionManager*)sessionManager;
@end

@implementation PersistentProfile

- (void)postNote:(NSString*)name
{
    @try {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self];
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while posting notification '%@': %@", name, e);
    }
}

- (void)profileDidChange
{   
    // we assume all chnages are done from a bg thread
    // refault sessions
    [[self allSessions] makeObjectsPerformSelector:@selector(refreshSelf)];
    (void)[self allSessions]; // fault the data back in
    
    [self postNote:PersistentProfileDidUpdateNotification];
}

- (BOOL)save:(NSManagedObjectContext*)moc withNotification:(BOOL)notify
{
    NSError *error;
    if ([moc save:&error]) {
        if (notify)
            [self performSelectorOnMainThread:@selector(profileDidChange) withObject:nil waitUntilDone:NO];
        return (YES);
    } else {
        ScrobLog(SCROB_LOG_ERR, @"failed to save persistent db (%@ -- %@)", error,
            [[error userInfo] objectForKey:NSDetailedErrorsKey]);
        [moc rollback];
    }
    return (NO);
}

- (BOOL)save:(NSManagedObjectContext*)moc
{
    return ([self save:moc withNotification:YES]);
}

- (void)resetMain
{
    // Prevent access while we are reseting
    NSManagedObjectContext *moc = mainMOC;
    mainMOC = nil;
    
    // so clients can prepae to refresh themselves
    [self postNote:PersistentProfileWillResetNotification];
    
    @try {
    [moc reset];
    } @catch (id e) {
        ScrobLog(SCROB_LOG_TRACE, @"resetMain: reset generated an exception: %@", e);
    }
    mainMOC = moc;
    
    // so clients can refresh themselves
    [self postNote:PersistentProfileDidResetNotification];
}

- (NSManagedObjectContext*)mainMOC
{
    return (mainMOC);
}

- (id)storeMetadataForKey:(NSString*)key moc:(NSManagedObjectContext*)moc
{
    id store = [[[moc persistentStoreCoordinator] persistentStores] objectAtIndex:0];
    return ([[[moc persistentStoreCoordinator] metadataForPersistentStore:store] objectForKey:key]);
}

- (void)setStoreMetadata:(id)object forKey:(NSString*)key moc:(NSManagedObjectContext*)moc
{
    id store = [[[moc persistentStoreCoordinator] persistentStores] objectAtIndex:0];
    NSMutableDictionary *d = [[[[moc persistentStoreCoordinator] metadataForPersistentStore:store] mutableCopy] autorelease];
    if (object)
        [d setObject:object forKey:key];
    else
        [d removeObjectForKey:key];
    [[moc persistentStoreCoordinator] setMetadata:d forPersistentStore:store];
    (void)[self save:moc withNotification:NO];
}

//******* public API ********//

- (BOOL)importInProgress
{
     OSMemoryBarrier();
     return (importing > 0);
}

- (void)setImportInProgress:(BOOL)import
{
    if (import) {
        OSMemoryBarrier();
        ++importing;
    } else {
        OSMemoryBarrier();
        --importing;
    }
    ISASSERT(importing >= 0, "importing went south!");
}

- (void)addSongPlay:(SongData*)song
{
    static NSMutableArray *queue = nil;
    if (!queue)
        queue = [[NSMutableArray alloc] init];
    
    if (song)
        [queue addObject:song];
    
    // the importer makes the assumption that no one else will modify the DB (so it doesn't have to search as much)
    if (![self importInProgress] && [queue count] > 0) {
        if ([self addSongPlaysToAllSessions:queue])
            [queue removeAllObjects];
    }
}

- (NSArray*)allSessions
{
    return ([[sessionMgr activeSessionsWithMOC:mainMOC] arrayByAddingObjectsFromArray:
        [sessionMgr archivedSessionsWithMOC:mainMOC weekLimit:10]]);
}

- (NSArray*)songsForSession:(id)session
{
    NSError *error;
    NSManagedObjectContext *moc = [session managedObjectContext];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@)",
            ITEM_SONG, [session valueForKey:@"name"]]];
    LEOPARD_BEGIN
    [request setReturnsObjectsAsFaults:NO];
    LEOPARD_END
    return ([moc executeFetchRequest:request error:&error]);
}

- (NSArray*)ratingsForSession:(id)session
{
    NSError *error;
    NSManagedObjectContext *moc = [session managedObjectContext];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PRatingCache" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@)",
            ITEM_RATING_CCH, [session valueForKey:@"name"]]];
    LEOPARD_BEGIN
    [request setReturnsObjectsAsFaults:NO];
    LEOPARD_END
    return ([moc executeFetchRequest:request error:&error]);
}

- (NSArray*)hoursForSession:(id)session
{
    NSError *error;
    NSManagedObjectContext *moc = [session managedObjectContext];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PHourCache" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@)",
            ITEM_HOUR_CCH, [session valueForKey:@"name"]]];
    LEOPARD_BEGIN
    [request setReturnsObjectsAsFaults:NO];
    LEOPARD_END
    return ([moc executeFetchRequest:request error:&error]);
}

#if 0
- (NSArray*)playHistoryForSong:(SongData*)song ignoreAlbum:(BOOL)ignoreAlbum
{
    NSError *error;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSongLastPlayed" inManagedObjectContext:mainMOC];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
    [request setSortDescriptors:[NSArray arrayWithObject:
        [[[NSSortDescriptor alloc] initWithKey:@"lastPlayed" ascending:NO] autorelease]]];
    
    NSString *format = @"(itemType == %@) AND (song.name LIKE[cd] %@) AND (song.artist.name LIKE[cd] %@)";
    NSString *album = [song album];
    if (!ignoreAlbum && album && [album length] > 0)
        format = [format stringByAppendingString:@" AND (song.album.name LIKE[cd] %@)"];
    else
        album = nil;
    [request setPredicate:[NSPredicate predicateWithFormat:format, ITEM_SONG,
        [[song title] stringByEscapingNSPredicateReserves], [[song artist] stringByEscapingNSPredicateReserves],
        [album stringByEscapingNSPredicateReserves]]];
    
    return ([mainMOC executeFetchRequest:request error:&error]);
}

- (NSNumber*)playCountForSong:(SongData*)song
{
    NSError *error;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:mainMOC];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
    NSString *format = @"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@)";
    NSString *album = [song album];
    if (album && [album length] > 0)
        format = [format stringByAppendingString:@" AND (album.name LIKE[cd] %@)"];
    else
        album = nil;
    [request setPredicate:[NSPredicate predicateWithFormat:format, ITEM_SONG,
        [[song title] stringByEscapingNSPredicateReserves], [[song artist] stringByEscapingNSPredicateReserves],
        [album stringByEscapingNSPredicateReserves]]];
    
    NSArray *result = [mainMOC executeFetchRequest:request error:&error];
    if (1 == [result count]) {
        return ([[result objectAtIndex:0] valueForKey:@"playCount"]);
    } else if ([result count] > 0) {
        if (!album) {
            ScrobLog(SCROB_LOG_WARN, @"playCountForSong: multiple songs for '%@' found in chart database", [song brief]);
            return ([[result objectAtIndex:0] valueForKey:@"playCount"]);
        } else
            ISASSERT(0, "multiple songs found!");
    }
    return (nil);
}
#endif

//******* end public API ********//

- (NSManagedObject*)playerWithName:(NSString*)name moc:(NSManagedObjectContext*)moc
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:[NSEntityDescription entityForName:@"PPlayer" inManagedObjectContext:moc]];
    [request setPredicate:[NSPredicate predicateWithFormat:@"name LIKE[cd] %@", [name stringByEscapingNSPredicateReserves]]];
    
    NSArray *result = [moc executeFetchRequest:request error:nil];
    if (1 == [result count])
        return ([result objectAtIndex:0]);
    
    return (nil);
}

- (void)didWake:(NSNotification*)note
{
    [self pingSessionManager];
}

- (void)importDidFinish:(id)obj
{
    [self setImportInProgress:NO];
    //[self setValue:[NSNumber numberWithBool:NO] forKey:@"importInProgress"];
    
    // Reset so any cached objects are forced to refault
    ISASSERT(NO == [mainMOC hasChanges], "somebody modifed the DB during an import");
    [self resetMain];
    
    [self pingSessionManager]; // this makes sure the sessions are properly setup before adding any songs
    [self performSelector:@selector(addSongPlay:) withObject:nil afterDelay:0.10]; // process any queued songs
}

- (void)addSongPlaysDidFinish:(id)obj
{
    [self addSongPlay:nil]; // process any queued songs
}

- (void)initDB
{
    NSDate *dbEpoch = [self storeMetadataForKey:(NSString*)kMDItemContentCreationDate moc:mainMOC];
    
    // Create sessions
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:mainMOC];
    NSEnumerator *en = [[NSArray arrayWithObjects:
        @"all", @"lastfm", @"pastday", @"pastweek", @"pastmonth", @"past3months", @"pastsixmonths", @"pastyear", @"temp", nil] objectEnumerator];
    NSArray *displayNames = [NSArray arrayWithObjects:
        NSLocalizedString(@"Overall", ""), NSLocalizedString(@"Last.fm Weekly", ""),
        NSLocalizedString(@"Today", ""), NSLocalizedString(@"Past Week", ""),
        NSLocalizedString(@"Past Month", ""), NSLocalizedString(@"Past Three Months", ""),
        NSLocalizedString(@"Past Six Months", ""),
        NSLocalizedString(@"Past Year", ""), NSLocalizedString(@"Internal", ""),
        nil];
    NSString *name;
    NSManagedObject *obj;
    NSUInteger i = 0;
    while ((name = [en nextObject])) {
        obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:mainMOC];
        [obj setValue:ITEM_SESSION forKey:@"itemType"];
        [obj setValue:name forKey:@"name"];
        [obj setValue:dbEpoch forKey:@"epoch"];
        [obj setValue:[displayNames objectAtIndex:i] forKey:@"localizedName"];
        ++i;
        [obj release];
    }
    
    // Create player entries
    entity = [NSEntityDescription entityForName:@"PPlayer" inManagedObjectContext:mainMOC];
    obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:mainMOC];
    [obj setValue:@"iTunes" forKey:@"name"];
    [obj release];
    
    obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:mainMOC];
    [obj setValue:@"iTunes Shared Library" forKey:@"name"];
    [obj release];
    
    obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:mainMOC];
    [obj setValue:@"Last.fm Radio" forKey:@"name"];
    [obj release];
    
    // This is used for PSessionItem.item when the item has no other relationship (currently the caches)
    entity = [NSEntityDescription entityForName:@"PItem" inManagedObjectContext:mainMOC];
    obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:mainMOC];
    [obj setValue:@"-DB-Orphans-" forKey:@"name"];
    // type is left at unknown
    [obj release];
}

- (void)backup
{
    NSString *backup = [PERSISTENT_STORE_DB stringByAppendingString:@"-backup"];
    (void)[[NSFileManager defaultManager] removeFileAtPath:[backup stringByAppendingString:@"-1"] handler:nil];
    (void)[[NSFileManager defaultManager] movePath:backup toPath:[backup stringByAppendingString:@"-1"] handler:nil];
    (void)[[NSFileManager defaultManager] copyPath:PERSISTENT_STORE_DB toPath:backup handler:nil];
}

#define CURRENT_STORE_VERSION @"1"
- (id)init
{
    NSError *error = nil;
    id mainStore;
    mainMOC = [[NSManagedObjectContext alloc] init];
    [mainMOC setUndoManager:nil];
    
    NSPersistentStoreCoordinator *psc;
    psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[NSManagedObjectModel mergedModelFromBundles:nil]];
    [mainMOC setPersistentStoreCoordinator:psc];
    [psc release];
    
    sessionMgr = [PersistentSessionManager sharedInstance];
    
    NSURL *url = [NSURL fileURLWithPath:PERSISTENT_STORE_DB];
    // NSXMLStoreType is slow and keeps the whole object graph in mem, but great for looking at the DB internals (debugging)
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreWithURL:url error:nil];
    if (metadata && nil != [metadata objectForKey:@"ISWillImportiTunesLibrary"]) {
        // import was interrupted, reset everything
        ScrobLog(SCROB_LOG_ERR, @"The iTunes import failed, removing corrupt database.");
        (void)[[NSFileManager defaultManager] removeFileAtPath:PERSISTENT_STORE_DB handler:nil];
        // try and remove any SQLite journal as well
        (void)[[NSFileManager defaultManager] removeFileAtPath:
            [PERSISTENT_STORE_DB stringByAppendingString:@"-journal"] handler:nil];
        metadata = nil;
    }
    if (!metadata) {
        NSCalendarDate *now = [NSCalendarDate date];
        mainStore = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error];
        [psc setMetadata:
            [NSDictionary dictionaryWithObjectsAndKeys:
                CURRENT_STORE_VERSION, kMDItemVersion,
                now, kMDItemContentCreationDate, // epoch
                [NSNumber numberWithBool:NO], @"ISDidImportiTunesLibrary",
                // NSStoreTypeKey and NSStoreUUIDKey are always added
                nil]
            forPersistentStore:mainStore];
        
        [self initDB];
        NSManagedObject *allSession = [sessionMgr sessionWithName:@"all" moc:mainMOC];
        ISASSERT(allSession != nil, "missing all session!");
        [allSession setValue:now forKey:@"epoch"];
        
        [mainMOC save:nil];
    } else {
        if (![[metadata objectForKey:(NSString*)kMDItemVersion] isEqualTo:CURRENT_STORE_VERSION]) {
            [mainMOC release];
            return (nil);
        #ifdef notyet
            [psc migratePersistentStore:mainStore toURL:nil options:nil withType:NSSQLiteStoreType error:nil];
        #endif
        }
        
        [self backup];
        mainStore = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error];
        
        // 2.0b3, session epoch to the epoch of the DB so the stats are accurately portrayed to the user
        @try {
        NSDate *dbEpoch = [[self storeMetadataForKey:(NSString*)kMDItemContentCreationDate moc:mainMOC] GMTDate];
        NSEnumerator *en = [[self allSessions] objectEnumerator];
        NSManagedObject *s;
        while ((s = [en nextObject])) {
            if ([[s valueForKey:@"name"] isEqualTo:@"all"])
                continue;
            if ([[[s valueForKey:@"epoch"] GMTDate] isLessThan:dbEpoch]) {
                [s setValue:dbEpoch forKey:@"epoch"];
            }
        }
        if ([mainMOC hasChanges])
            [mainMOC save:nil];
        } @catch (NSException *e) {
            [mainMOC rollback];
            ScrobLog(SCROB_LOG_ERR, @"init: exception while updating session epochs: %@", e);
        }
    }
    
    // we don't allow the user to make changes and the session mgr background thread handles all internal changes
    [mainMOC setMergePolicy:NSRollbackMergePolicy];

    [self performSelector:@selector(pingSessionManager) withObject:nil afterDelay:0.0];
    
    if (NO == [[metadata objectForKey:@"ISDidImportiTunesLibrary"] boolValue]) {
        PersistentProfileImport *import = [[PersistentProfileImport alloc] init];
    #if IS_THREAD_IMPORT
        [NSThread detachNewThreadSelector:@selector(importiTunesDB:) toTarget:import withObject:self];
        [import release];
    #else
        [import importiTunesDB:self];
        // leak import, but for debugging it's OK
    #endif
    }
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
        selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    
    return (self);
}

// singleton support
+ (PersistentProfile*)sharedInstance
{
    static PersistentProfile *shared = nil;
    return (shared ? shared : (shared = [[PersistentProfile alloc] init]));
}

+ (BOOL)newProfile
{
    NSURL *url = [NSURL fileURLWithPath:PERSISTENT_STORE_DB];
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreWithURL:url error:nil];
    // while technically indicating a new profile, the last check is also true while an import is in progress
    // and [iScrobblerController applicatinoShouldTerminate:] would break in this case.
    return (!metadata /*|| (nil != [metadata objectForKey:@"ISWillImportiTunesLibrary"]*/);
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

@implementation PersistentProfile (SessionManagement)

#if IS_THREAD_SESSIONMGR
- (BOOL)performSelectorOnSessionMgrThread:(SEL)selector withObject:(id)object
{
    ISASSERT(mainThread && (mainThread == [NSThread currentThread]), "wrong thread!");
    
    if (![sessionMgr threadMessenger])
        return (NO);
    
    [ISThreadMessenger makeTarget:[sessionMgr threadMessenger] performSelector:selector withObject:object];
    return (YES);
}
#endif

- (void)pingSessionManager
{
#if IS_THREAD_SESSIONMGR
    static BOOL init = YES;
    if (init && ![self importInProgress]) {
        #ifdef ISDEBUG
        mainThread = [NSThread currentThread];
        #endif
        init = NO;
        [NSThread detachNewThreadSelector:@selector(sessionManagerThread:) toTarget:sessionMgr withObject:self];
    } else if (![self importInProgress]) {
        (void)[self performSelectorOnSessionMgrThread:@selector(sessionManagerUpdate) withObject:nil];
    }
#else
    [sessionMgr updateLastfmSession:nil];
    [sessionMgr updateSessions:nil];
    [sessionMgr resetMain];
#endif
}

- (BOOL)addSongPlaysToAllSessions:(NSArray*)queue
{
#if IS_THREAD_SESSIONMGR
    ISASSERT([sessionMgr threadMessenger] != nil, "nil send port!");
    return ([self performSelectorOnSessionMgrThread:@selector(processSongPlays:) withObject:[[queue copy] autorelease]]);
#else
    [sessionMgr processSongPlays:queue];
    return (YES);
#endif
}

- (PersistentSessionManager*)sessionManager
{
    return (sessionMgr);
}

@end

@implementation NSManagedObject (ISProfileAdditions)

- (void)refreshSelf
{
    @try {
    [[self managedObjectContext] refreshObject:self mergeChanges:NO];
    } @catch (id e) {
        ScrobDebug(@"exception: %@", e);
    }
}

@end

#import "iTunesImport.m"

@implementation NSString (ISNSPredicateEscape)

- (NSString*)stringByEscapingNSPredicateReserves
{
    NSMutableString *s = [self mutableCopy];
    NSRange r;
    r.location = 0;
    r.length = [s length];
    NSUInteger replaced;
    replaced = [s replaceOccurrencesOfString:@"?" withString:@"\\?" options:NSLiteralSearch range:r];
    r.length = [s length];
    replaced += [s replaceOccurrencesOfString:@"*" withString:@"\\*" options:NSLiteralSearch range:r];
    if (replaced > 0) {
        return ([s autorelease]);
    }
    
    [s release];
    return (self);
}

@end
