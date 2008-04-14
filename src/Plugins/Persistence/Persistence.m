//
//  Persistence.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/3/2007.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <libkern/OSAtomic.h>

#import "Persistence.h"
#import "PersistentSessionManager.h"
#import "PersistenceImport.h"
#import "SongData.h"
#import "ISThreadMessenger.h"

/**
Simple CoreDate overview: http://cocoadevcentral.com/articles/000086.php
Important CoreData behaviors:
http://www.cocoadev.com/index.pl?CoreDataInheritanceIssues
http://www.cocoadev.com/index.pl?CoreDataQuestions

Tiger note:
Performance of the SQL store can be SEVERLY impacted by a slow hard disk (e.g. 4200RPM laptop drive)
On import, setting "com.apple.CoreData.SQLiteDebugSynchronous" to 1 or 0 should help a lot
(at the risk of data corruption if the machine crashes or loses power).
**/

@interface PersistentSessionManager (Private)
- (void)recreateRatingsCacheForSession:(NSManagedObject*)session songs:(NSArray*)songs moc:(NSManagedObjectContext*)moc;
@end

@interface PersistentSessionManager (Editors)
// generic interface to execute an edit
- (void)editObject:(NSDictionary*)args;
// specfic editors -- these are private
- (NSError*)rename:(NSManagedObjectID*)moid to:(NSString*)newName;
- (NSError*)removeObject:(NSManagedObjectID*)moid;
- (NSError*)addHistoryEvent:(NSDate*)playDate forObject:(NSManagedObjectID*)moid;
- (NSError*)removeHistoryEvent:(NSManagedObjectID*)eventID forObject:(NSManagedObjectID*)moid;
@end

@interface PersistentProfile (SessionManagement)
- (BOOL)performSelectorOnSessionMgrThread:(SEL)selector withObject:(id)object;
- (void)pingSessionManager;
- (BOOL)addSongPlaysToAllSessions:(NSArray*)queue;
@end

@implementation PersistentProfile

- (void)displayErrorWithTitle:(NSString*)title message:(NSString*)msg
{
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
        [[NSApp delegate] methodSignatureForSelector:@selector(displayErrorWithTitle:message:)]];
    [inv retainArguments];
    [inv setTarget:[NSApp delegate]]; // arg 0
    [inv setSelector:@selector(displayErrorWithTitle:message:)]; // arg 1
    [inv setArgument:&title atIndex:2];
    [inv setArgument:&msg atIndex:3];
    [inv performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
}

- (void)displayWarningWithTitle:(NSString*)title message:(NSString*)msg
{
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
        [[NSApp delegate] methodSignatureForSelector:@selector(displayWarningWithTitle:message:)]];
    [inv retainArguments];
    [inv setTarget:[NSApp delegate]]; // arg 0
    [inv setSelector:@selector(displayWarningWithTitle:message:)]; // arg 1
    [inv setArgument:&title atIndex:2];
    [inv setArgument:&msg atIndex:3];
    [inv performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
}

- (void)postNoteWithArgs:(NSDictionary*)args
{
    @try {
    [[NSNotificationCenter defaultCenter] postNotificationName:[args objectForKey:@"name"] object:self
        userInfo:[args objectForKey:@"info"]];
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while posting notification '%@': %@", [args objectForKey:@"name"], e);
    }
}

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

- (BOOL)save:(NSManagedObjectContext*)moc withNotification:(BOOL)notify error:(NSError**)failure
{
    NSError *error; 
    if ([moc save:&error]) {
        if (notify)
            [self performSelectorOnMainThread:@selector(profileDidChange) withObject:nil waitUntilDone:NO];
        if (failure)
            failure = nil;
        return (YES);
    } else {
        if (failure)
            *failure = error;
        NSString *title = NSLocalizedStringFromTableInBundle(@"Local Charts Could Not Be Saved", nil, [NSBundle bundleForClass:[self class]], "");
        NSString *msg = NSLocalizedStringFromTableInBundle(@"The local charts database could not be saved. This may be an indication of corruption. See the log file for more information.", nil, [NSBundle bundleForClass:[self class]], "");
        [self displayErrorWithTitle:title message:msg];
        
        ScrobLog(SCROB_LOG_ERR, @"failed to save persistent db (%@ -- %@)", error,
            [[error userInfo] objectForKey:NSDetailedErrorsKey]);
        [moc rollback];
    }
    return (NO);
}

- (BOOL)save:(NSManagedObjectContext*)moc withNotification:(BOOL)notify
{
    return ([self save:moc withNotification:notify error:nil]);
}

- (BOOL)save:(NSManagedObjectContext*)moc
{
    return ([self save:moc withNotification:YES error:nil]);
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

- (PersistentSessionManager*)sessionManager
{
    return (sessionMgr);
}

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

- (void)rename:(NSManagedObjectID*)moid to:(NSString*)newTitle
{
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
        moid, @"oid",
        NSStringFromSelector(@selector(rename:to:)), @"method",
        [NSArray arrayWithObjects:moid, newTitle, nil], @"args",
        @"rename", @"what",
        nil];

    [self performSelectorOnSessionMgrThread:@selector(editObject:) withObject:args];
}

- (void)removeObject:(NSManagedObjectID*)moid
{
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
        moid, @"oid",
        NSStringFromSelector(@selector(removeObject:)), @"method",
        [NSArray arrayWithObjects:moid, nil], @"args",
        @"remove", @"what",
        nil];

    [self performSelectorOnSessionMgrThread:@selector(editObject:) withObject:args];
}

- (void)addHistoryEvent:(NSDate*)playDate forObject:(NSManagedObjectID*)moid
{
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
        moid, @"oid",
        NSStringFromSelector(@selector(addHistoryEvent:forObject:)), @"method",
        [NSArray arrayWithObjects:playDate, moid, nil], @"args",
        @"addhist", @"what",
        nil];

    [self performSelectorOnSessionMgrThread:@selector(editObject:) withObject:args];
}

- (void)removeHistoryEvent:(NSManagedObjectID*)eventID forObject:(NSManagedObjectID*)moid
{
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
        moid, @"oid",
        NSStringFromSelector(@selector(removeHistoryEvent:forObject:)), @"method",
        [NSArray arrayWithObjects:eventID, moid, nil], @"args",
        @"remhist", @"what",
        nil];

    [self performSelectorOnSessionMgrThread:@selector(editObject:) withObject:args];
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
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
            ITEM_SONG, session]];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
    return ([moc executeFetchRequest:request error:&error]);
}

- (NSArray*)ratingsForSession:(id)session
{
    NSError *error;
    NSManagedObjectContext *moc = [session managedObjectContext];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PRatingCache" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
            ITEM_RATING_CCH, session]];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
    return ([moc executeFetchRequest:request error:&error]);
}

- (NSArray*)hoursForSession:(id)session
{
    NSError *error;
    NSManagedObjectContext *moc = [session managedObjectContext];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PHourCache" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session == %@)",
            ITEM_HOUR_CCH, session]];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    [request setReturnsObjectsAsFaults:NO];
    #endif
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

- (void)persistentProfileDidEditObject:(NSNotification*)note
{
    ISASSERT(mainMOC != nil, "missing thread moc!");
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread isMainThread], "!mainThread!");
    #endif
    
    NSManagedObjectID *oid = [[note userInfo] objectForKey:@"oid"];
    NSManagedObject *obj = [mainMOC objectRegisteredForID:oid];
    if (obj) {
        [obj refreshSelf];
    }
}

- (void)addSongPlaysDidFinish:(id)obj
{
    [self addSongPlay:nil]; // process any queued songs
}

- (NSArray*)dataModelBundles
{
    return ([NSArray arrayWithObjects:[NSBundle bundleForClass:[self class]], nil]);
}

- (void)backupDatabase
{
    NSString *backup = [PERSISTENT_STORE_DB stringByAppendingString:@"-backup"];
    (void)[[NSFileManager defaultManager] removeFileAtPath:[backup stringByAppendingString:@"-1"] handler:nil];
    (void)[[NSFileManager defaultManager] movePath:backup toPath:[backup stringByAppendingString:@"-1"] handler:nil];
    (void)[[NSFileManager defaultManager] copyPath:PERSISTENT_STORE_DB toPath:backup handler:nil];
}

- (void)createDatabase
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

- (void)databaseDidInitialize:(NSDictionary*)metadata
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread isMainThread], "!mainThread!");
    #endif
    
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(persistentProfileDidEditObject:)
        name:PersistentProfileDidEditObject
        object:nil];
    
    ScrobLog(SCROB_LOG_TRACE, @"Opened Local Charts database version %@. Internal version is %@.",
            [metadata objectForKey:(NSString*)kMDItemVersion], IS_CURRENT_STORE_VERSION);
    ScrobLog(SCROB_LOG_TRACE, @"Local Charts epoch is '%@'", [metadata objectForKey:(NSString*)kMDItemContentCreationDate]);
    
    id ver = [metadata objectForKey:(NSString*)kMDItemCreator];
    ScrobLog(SCROB_LOG_TRACE, @"Local Charts creator is '%@'", ver ? ver : @"pre-2.1.1");
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ver = [metadata objectForKey:(NSString*)kMDItemEditors];
    ScrobLog(SCROB_LOG_TRACE, @"Local Charts were last opened by '%@'", ver ? ver : @"pre-2.1.1");
    [self setStoreMetadata:[NSArray arrayWithObject:[mProxy applicationVersion]] forKey:(NSString*)kMDItemEditors moc:mainMOC];
    #endif
    
    [self performSelector:@selector(pingSessionManager) withObject:nil afterDelay:0.0];
    
    if (NO == [[metadata objectForKey:@"ISDidImportiTunesLibrary"] boolValue]) {
        PersistentProfileImport *import = [[PersistentProfileImport alloc] init];
        [NSThread detachNewThreadSelector:@selector(importiTunesDB:) toTarget:import withObject:self];
        [import release];
    }
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
        selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:[PERSISTENT_STORE_DB stringByAppendingString:@"-backup-1"]];
    if (NO == CSBackupIsItemExcluded(url, NULL))
        (void)CSBackupSetItemExcluded(url, YES, YES);
    #endif
}

- (void)databaseDidFailInitialize:(id)arg
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread isMainThread], "!mainThread!");
    #endif
    
    [mainMOC release];
    mainMOC = nil;
    sessionMgr = nil;
}

#if IS_STORE_V2
/*
The repair method does its job, but when saving the test databases caused the process to run out of VM space (32bit) because of thousands of exceptions.
So for now, this is disabled.
*/
#ifdef ISDB_REPAIR
- (void)repairDatabaseInconsistenciesWithModel:(NSManagedObjectModel*)model URL:(NSURL*)url
{
    NSString *errMsg;
    NSManagedObjectContext *moc = nil;
    NSError *error;
    @try {
    
    moc = [[NSManagedObjectContext alloc] init];
    [moc setUndoManager:nil];
    
    NSPersistentStoreCoordinator *psc;
    psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [moc setPersistentStoreCoordinator:psc];
    [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error];
    [psc release];
    
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionItem" inManagedObjectContext:moc];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"item == NULL || session == NULL"];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:predicate];
    
    NSArray *results = [moc executeFetchRequest:request error:nil];
    if ([results count] > 0) {
        ScrobLog(SCROB_LOG_WARN, @"The database appears to be corrupted, attempting repair.");
        errMsg = NSLocalizedStringFromTableInBundle(@"The database appears to be corrupted, attempting repair.", nil, [NSBundle bundleForClass:[self class]], "");
        [self displayWarningWithTitle:@"" message:errMsg];
    } else
        errMsg = nil;
    
    NSManagedObject *mobj;
    NSEnumerator *en = [results objectEnumerator];
    while ((mobj = [en nextObject])) {
        ScrobLog(SCROB_LOG_WARN, @"Session object '%@' is invalid and cannot be recovered, deleting...", [mobj objectID]);
        [moc deleteObject:mobj];
    }
    
    predicate = [NSPredicate predicateWithFormat:@"itemType == NULL"];
    [request setPredicate:predicate];
    results = [moc executeFetchRequest:request error:nil];
    if ([results count] > 0 && !errMsg) {
        ScrobLog(SCROB_LOG_WARN, @"The database appears to be corrupted, attempting repair.");
        errMsg = NSLocalizedStringFromTableInBundle(@"The database appears to be corrupted, attempting repair.", nil, [NSBundle bundleForClass:[self class]], "");
        [self displayWarningWithTitle:@"" message:errMsg];
    }
    
    en = [results objectEnumerator];
    while ((mobj = [en nextObject])) {
        NSString *mobjClass = [[mobj entity] managedObjectClassName];
        if ([mobjClass isEqualToString:@"PSessionSong"]) {
            [mobj setValue:ITEM_SONG forKey:@"itemType"];
        } else if ([mobjClass isEqualToString:@"PSessionArtist"]) {
            [mobj setValue:ITEM_ARTIST forKey:@"itemType"];
        } else if ([mobjClass isEqualToString:@"PSessionAlbum"]) {
            [mobj setValue:ITEM_ALBUM forKey:@"itemType"];
        } else if ([mobjClass isEqualToString:@"PHourCache"]) {
            [mobj setValue:ITEM_HOUR_CCH forKey:@"itemType"];
        } else if ([mobjClass isEqualToString:@"PRatingCache"]) {
            [mobj setValue:ITEM_RATING_CCH forKey:@"itemType"];
        }
    }
    
    entity = [NSEntityDescription entityForName:@"PItem" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:nil];
    results = [moc executeFetchRequest:request error:nil];
    
    if ([moc hasChanges])
        [moc save:&error];
    
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while attempting to repair database: %@", e);
        [moc rollback];
        
        NSString *title = NSLocalizedStringFromTableInBundle(@"Database Repairs Failed", nil, [NSBundle bundleForClass:[self class]], "");
        errMsg = NSLocalizedStringFromTableInBundle(@"The database may be in an unrecoverable state.", nil, [NSBundle bundleForClass:[self class]], "");
        [self displayErrorWithTitle:title message:errMsg];
    }
    
    @try {
    [moc release];
    } @catch (NSException *e2) {}
}
#endif // ISDB_REPAIR

- (void)migrationDidComplete:(NSDictionary*)metadata
{   
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread isMainThread], "!mainThread!");
    #endif
    
    [self databaseDidInitialize:metadata];
    [self postNote:PersistentProfileDidMigrateNotification];
    [self profileDidChange];
    [self performSelector:@selector(addSongPlay:) withObject:nil afterDelay:0.10]; // process any queued songs
}

- (void)migrateDatabase:(id)arg
{
    ISElapsedTimeInit();
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSManagedObjectContext *moc = nil;
    NSError *error = nil;
    BOOL migrated = NO;
    
    [self performSelectorOnMainThread:@selector(postNote:) withObject:PersistentProfileWillMigrateNotification waitUntilDone:NO];
    
    [self setImportInProgress:YES];
    
    NSURL *dburl = [NSURL fileURLWithPath:PERSISTENT_STORE_DB];
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
        URL:dburl error:nil];
    NSDate *createDate = [metadata objectForKey:(NSString*)kMDItemContentCreationDate];
    if (!createDate) {
        ISASSERT(0, "missing creation date!");
        createDate = [NSDate date];
    }
    ISASSERT(nil != [metadata objectForKey:@"ISDidImportiTunesLibrary"], "missing import state!");
    
    ScrobLog(SCROB_LOG_TRACE, @"Migrating Local Charts database version %@ to version %@.",
            [metadata objectForKey:(NSString*)kMDItemVersion], IS_CURRENT_STORE_VERSION);
    
    NSAutoreleasePool *tempPool = [[NSAutoreleasePool alloc] init];
    @try {
    
    NSArray *searchBundles = [self dataModelBundles];
    NSURL *tmpURL;
    #ifdef ISDB_REPAIR
    // Before migration, attempt to repair any DB problems
    // The v1reapir MOM is a copy of the v1 MOM with relaxed relationship requirements so bad objects can be loaded
    tmpURL = [NSURL fileURLWithPath:[[searchBundles objectAtIndex:0]
        pathForResource:@"iScrobblerV1repair" ofType:@"mom" inDirectory:@"iScrobbler.momd"]];
    NSManagedObjectModel *v1repairmom = [[[NSManagedObjectModel alloc] initWithContentsOfURL:tmpURL] autorelease];
    if (v1repairmom)
        [self repairDatabaseInconsistenciesWithModel:v1repairmom URL:dburl];
    #endif
    
    tmpURL = [NSURL fileURLWithPath:[[searchBundles objectAtIndex:0]
        pathForResource:@"iScrobbler" ofType:@"mom" inDirectory:@"iScrobbler.momd"]];
    NSManagedObjectModel *v1mom = [[[NSManagedObjectModel alloc] initWithContentsOfURL:tmpURL] autorelease];
    if (!v1mom)
        ScrobLog(SCROB_LOG_ERR, @"Migration: Failed to load v1 mom from: %@", [tmpURL path]);
    
    tmpURL = [NSURL fileURLWithPath:[[searchBundles objectAtIndex:0]
        pathForResource:@"iScrobblerV2" ofType:@"mom" inDirectory:@"iScrobbler.momd"]];
    NSManagedObjectModel *v2mom = [[[NSManagedObjectModel alloc] initWithContentsOfURL:tmpURL] autorelease];
    if (!v2mom)
        ScrobLog(SCROB_LOG_ERR, @"Migration: Failed to load v2 mom from: %@", [tmpURL path]);
    
    NSMappingModel *map = [NSMappingModel mappingModelFromBundles:searchBundles forSourceModel:v1mom destinationModel:v2mom];
    if (!map)
        ScrobLog(SCROB_LOG_ERR, @"Migration: Failed to create mapping model");
    
    NSMigrationManager *migm = [[[NSMigrationManager alloc] initWithSourceModel:v1mom destinationModel:v2mom] autorelease];
    if (migm) {
        tmpURL = [NSURL fileURLWithPath:
            [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ISMIG_%d", random()]]];
        ISStartTime();
        migrated = [migm migrateStoreFromURL:dburl
            type:NSSQLiteStoreType
            options:nil
            withMappingModel:map
            toDestinationURL:tmpURL
            destinationType:NSSQLiteStoreType
            destinationOptions:nil
            error:&error];
        ISEndTime();
        ScrobDebug(@"Migration finished in %.4lf seconds", (abs2clockns / 1000000000.0));
        if (migrated) {
            // swap the files as [addPersistentStoreWithType:] would
            migrated = NO;
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dbpath = [dburl path];
            NSString *tmppath = [tmpURL path];
            NSString *backup = [[[dbpath stringByDeletingPathExtension] stringByAppendingString:@"~"]
                stringByAppendingPathExtension:[dbpath pathExtension]];
            (void)[fm removeItemAtPath:backup error:nil];
            if ([fm linkItemAtPath:dbpath toPath:backup error:&error]) {
                if ([fm removeItemAtPath:dbpath error:&error]) {
                    if ([fm copyItemAtPath:tmppath toPath:dbpath error:&error]) {
                        migrated = YES;
                    }
                }
            }
            (void)[fm removeItemAtPath:tmppath error:nil];
        }  
    } else
        ScrobLog(SCROB_LOG_ERR, @"Migration: Failed to create migration manager");
    
    } @catch (NSException *e) {
        migrated = NO;
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
            NSLocalizedString(@"An exception occurred during database migration.", ""),
            NSLocalizedDescriptionKey,
            nil]];
        ScrobLog(SCROB_LOG_ERR, @"Migration: an exception occurred during database migration. (%@)", e);
    }
    (void)[error retain];
    [tempPool release];
    tempPool = nil;
    (void)[error autorelease];
    
    NSPersistentStore *store;
    NSPersistentStoreCoordinator *psc = nil;
    if (migrated) {
        psc = [mainMOC persistentStoreCoordinator];
        store = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:dburl options:nil error:&error];
        moc = [[[NSManagedObjectContext alloc] init] autorelease];
        [moc setPersistentStoreCoordinator:psc];
        [moc setUndoManager:nil];
        
        if (![NSThread isMainThread])
            [[[NSThread currentThread] threadDictionary] setObject:moc forKey:@"moc"];
    } else {
        store = nil;
        migrated = NO;
    }
    
    if (store) {
        metadata = [NSDictionary dictionaryWithObjectsAndKeys:
            IS_CURRENT_STORE_VERSION, (NSString*)kMDItemVersion,
            createDate, (NSString*)kMDItemContentCreationDate, // epoch
            [metadata objectForKey:@"ISDidImportiTunesLibrary"], @"ISDidImportiTunesLibrary",
            [mProxy applicationVersion], (NSString*)kMDItemCreator,
            // NSStoreTypeKey and NSStoreUUIDKey are always added
            nil];
        [psc setMetadata:metadata forPersistentStore:store];
        
        tempPool = [[NSAutoreleasePool alloc] init];
        // force scrub the db -- this reduces the size of the dub
        // it also fixes a cache bug in the 'all' session caused during a 2.0 import
        ISStartTime();
        [sessionMgr performSelector:@selector(performScrub:) withObject:nil];
        ISEndTime();
        ScrobDebug(@"Migration: scrubbed db in in %.4lf seconds", (abs2clockns / 1000000000.0));
        [tempPool release];
        
        // update session ratings
        tempPool = [[NSAutoreleasePool alloc] init];
        ISStartTime();
        NSEnumerator *en = [[[sessionMgr activeSessionsWithMOC:moc] arrayByAddingObjectsFromArray:
            [sessionMgr archivedSessionsWithMOC:moc weekLimit:0]] objectEnumerator];
        NSManagedObject *mobj;
        while ((mobj = [en nextObject])) {
            #ifndef ISDEBUG
            if ([@"all" isEqualToString:[mobj valueForKey:@"name"]])
                continue; // this was performed in the db scrub
            #endif
            @try {
            [sessionMgr recreateRatingsCacheForSession:mobj songs:[self songsForSession:mobj] moc:moc];
            [self save:moc withNotification:NO];
            } @catch (NSException *e) {
                ScrobLog(SCROB_LOG_ERR, @"Migration: exception updating ratings for %@. (%@)",
                    [mobj valueForKey:@"name"], e);
            }
        }
        ISEndTime();
        ScrobDebug(@"Migration: ratings update in in %.4lf seconds", (abs2clockns / 1000000000.0));
        
        [tempPool release];
        tempPool = nil;
        
        NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
        NSEntityDescription *entity;
        // set Artist firstPlayed times (non-import only)
        @try {
            ISStartTime();
            entity = [NSEntityDescription entityForName:@"PArtist" inManagedObjectContext:moc];
            [request setEntity:entity];
            [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@)", ITEM_ARTIST]];
            [request setReturnsObjectsAsFaults:NO];
            [request setRelationshipKeyPathsForPrefetching:[NSArray arrayWithObjects:@"songs", nil]];
            en = [[moc executeFetchRequest:request error:&error] objectEnumerator];
            
            tempPool = [[NSAutoreleasePool alloc] init];
            while ((mobj = [en nextObject])) {
                if ([[mobj valueForKeyPath:@"songs.importedPlayCount.@sum.unsignedIntValue"] unsignedIntValue] > 0)
                    continue;
                entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
                [request setEntity:entity];
                [request setPredicate:[NSPredicate predicateWithFormat:
                    @"(itemType == %@) && (firstPlayed != nil) && (artist == %@)", ITEM_SONG, mobj]];
                NSArray *songs = [moc executeFetchRequest:request error:&error];
                if ([songs count] > 0) {
                    NSNumber *firstPlayed = [songs valueForKeyPath:@"firstPlayed.@min.timeIntervalSince1970"];
                    if (firstPlayed) {
                        [mobj setValue:[NSDate dateWithTimeIntervalSince1970:[firstPlayed doubleValue]]
                            forKey:@"firstPlayed"];
                    }
                    error = nil;
                    [tempPool release];
                    tempPool = [[NSAutoreleasePool alloc] init];
                }
            }
            ISEndTime();
            ScrobDebug(@"Migration: artist update in in %.4lf seconds", (abs2clockns / 1000000000.0));
        } @catch (NSException *e) {
            ScrobLog(SCROB_LOG_ERR, @"Migration: exception updating artists. (%@)", e);
        }
        
        error = nil;
        [tempPool release];
        tempPool = nil;
        [self save:moc withNotification:NO];
    } else
        migrated = NO;
    [self setImportInProgress:NO];
    
    [moc reset];
    
    if (migrated) {
        [self performSelectorOnMainThread:@selector(migrationDidComplete:) withObject:metadata waitUntilDone:NO];
    } else {
        ScrobLog(SCROB_LOG_ERR, @"Migration failed with: %@", error ? error : @"unknown");
        [self performSelectorOnMainThread:@selector(databaseDidFailInitialize:) withObject:nil waitUntilDone:YES];
        [self performSelectorOnMainThread:@selector(postNote:) withObject:PersistentProfileMigrateFailedNotification waitUntilDone:NO];
    }
    
    [pool release];
    if (![NSThread isMainThread])
        [NSThread exit];
}
#endif

- (BOOL)moveDatabaseToNewSupportFolder
{
    NSString *oldPath = PERSISTENT_STORE_DB_21X;
    
    NSURL *url = [NSURL fileURLWithPath:oldPath];
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:nil URL:url error:nil];
    #else
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreWithURL:url error:nil];
    #endif
    if (metadata && nil == [metadata objectForKey:@"ISStoreLocationVersion"]) {
        NSString *newPath = PERSISTENT_STORE_DB;
        #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
        BOOL good = [[NSFileManager defaultManager] moveItemAtPath:oldPath toPath:newPath error:nil];
        #else
        BOOL good = [[NSFileManager defaultManager] movePath:oldPath toPath:newPath handler:nil];
        #endif
        if (good) {
            // move the most recent backup and create a symlink for the old file
            NSString *backup = [oldPath stringByAppendingString:@"-backup"];
            NSString *newBackup = [newPath stringByAppendingString:@"-backup"];
            NSString *symlinkDest = [NSString stringWithFormat:@"./%@/%@",
                [[newPath stringByDeletingLastPathComponent] lastPathComponent],
                [newPath lastPathComponent]];
            
            #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
            (void)[[NSFileManager defaultManager] moveItemAtPath:backup toPath:newBackup error:nil];
            (void)[[NSFileManager defaultManager] removeItemAtPath:[backup stringByAppendingString:@"-1"] error:nil];
            (void)[[NSFileManager defaultManager] createSymbolicLinkAtPath:oldPath withDestinationPath:symlinkDest error:nil];
            #else
            (void)[[NSFileManager defaultManager] movePath:backup toPath:newBackup handler:nil];
            (void)[[NSFileManager defaultManager] removeFileAtPath:[backup stringByAppendingString:@"-1"] handler:nil];
            (void)[[NSFileManager defaultManager] createSymbolicLinkAtPath:oldPath pathContent:symlinkDest];
            #endif
            
            return (YES);
        }
    } else if (metadata) {
        // remove stale backups
        NSString *backup = [oldPath stringByAppendingString:@"-backup"];
        #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
        (void)[[NSFileManager defaultManager] removeItemAtPath:backup error:nil];
        (void)[[NSFileManager defaultManager] removeItemAtPath:[backup stringByAppendingString:@"-1"] error:nil];
        #else
        (void)[[NSFileManager defaultManager] removeFileAtPath:backup handler:nil];
        (void)[[NSFileManager defaultManager] removeFileAtPath:[backup stringByAppendingString:@"-1"] handler:nil];
        #endif
    }
    
    return (NO);
}

- (BOOL)initDatabase:(NSError**)failureReason
{
    NSError *error = nil;
    NSPersistentStore *mainStore;
    mainMOC = [[NSManagedObjectContext alloc] init];
    [mainMOC setUndoManager:nil];
    
    *failureReason = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL
        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
            NSLocalizedString(@"The database could not be opened. An unknown error occurred.", ""),
            NSLocalizedDescriptionKey,
            nil]];
    
    NSPersistentStoreCoordinator *psc;
    psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:
        [NSManagedObjectModel mergedModelFromBundles:[self dataModelBundles]]];
    [mainMOC setPersistentStoreCoordinator:psc];
    [psc release];
    // we don't allow the user to make changes and the session mgr background thread handles all internal changes
    [mainMOC setMergePolicy:NSRollbackMergePolicy];
    
    sessionMgr = [PersistentSessionManager sharedInstance];
    
    BOOL didLocationMove = [self moveDatabaseToNewSupportFolder];
    
    NSURL *url = [NSURL fileURLWithPath:PERSISTENT_STORE_DB];
    // NSXMLStoreType is slow and keeps the whole object graph in mem, but great for looking at the DB internals (debugging)
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5 
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType URL:url error:nil];
    #else
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreWithURL:url error:nil];
    #endif
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
                IS_CURRENT_STORE_VERSION, (NSString*)kMDItemVersion,
                now, (NSString*)kMDItemContentCreationDate, // epoch
                [NSNumber numberWithBool:NO], @"ISDidImportiTunesLibrary",
                [NSNumber numberWithLongLong:[[NSTimeZone defaultTimeZone] secondsFromGMT]], @"ISTZOffset",
                [mProxy applicationVersion], (NSString*)kMDItemCreator,
                PERSISTENT_STORE_DB_LOCATION_VERSION, @"ISStoreLocationVersion",
                // NSStoreTypeKey and NSStoreUUIDKey are always added
                nil]
            forPersistentStore:mainStore];
        
        [self createDatabase];
        
        NSManagedObject *allSession = [sessionMgr sessionWithName:@"all" moc:mainMOC];
        ISASSERT(allSession != nil, "missing all session!");
        [allSession setValue:now forKey:@"epoch"];
        
        [mainMOC save:nil];
    } else {
        #if IS_STORE_V2
        if (![[psc managedObjectModel] isConfiguration:nil compatibleWithStoreMetadata:metadata]) {
        #else
        if (![[metadata objectForKey:(NSString*)kMDItemVersion] isEqualTo:IS_CURRENT_STORE_VERSION]) {
        #endif
            #if IS_STORE_V2
            #if !defined(ISDEBUG) || 1
            [NSThread detachNewThreadSelector:@selector(migrateDatabase:) toTarget:self withObject:nil];
            #else
            [self migrateDatabase:nil];
            #endif
            return (YES);
            #else
            [self databaseDidFailInitialize:nil];
            *failureReason = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL
                userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                    NSLocalizedString(@"The database could not be opened because it was created with a different design model. You need to upgrade iScrobbler or Mac OS X.", ""),
                    NSLocalizedDescriptionKey,
                    nil]];
            return (NO);
            #endif
        }
        
        mainStore = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error];
        if (!mainStore) {
            [self databaseDidFailInitialize:nil];
            *failureReason = error;
            return (NO);
        }
    }
    
    const char *appSig = [[[mProxy applicationBundle] objectForInfoDictionaryKey:@"CFBundleSignature"]
        cStringUsingEncoding:NSASCIIStringEncoding];
    if (appSig && strlen(appSig) >= 4) {
        OSType ccode = appSig[0] << 24 | appSig[1] << 16 | appSig[2] << 8 | appSig[3];
        NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithUnsignedInt:ccode], NSFileHFSCreatorCode,
            nil];
        #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5 
        if (0 == [[[[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:nil] objectForKey:NSFileHFSCreatorCode] intValue]) {
            (void)[[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:[url path] error:nil];
        }
        #else
        if (0 == [[[[NSFileManager defaultManager] fileAttributesAtPath:[url path] traverseLink:YES] objectForKey:NSFileHFSCreatorCode] intValue]) {
            (void)[[NSFileManager defaultManager] changeFileAttributes:attrs atPath:[url path]];
        }
        #endif
    }
    
    [self databaseDidInitialize:metadata];
    if (didLocationMove) {
        [self setStoreMetadata:PERSISTENT_STORE_DB_LOCATION_VERSION forKey:@"ISStoreLocationVersion" moc:mainMOC];
        [self save:mainMOC withNotification:NO];
    }
    *failureReason = nil;
    return (YES);
}

- (BOOL)isVersion2
{
    return (IS_STORE_V2);
}

#ifdef ISDEBUG
- (void)log:(NSString*)msg
{
    [mLog writeData:[msg dataUsingEncoding:NSUTF8StringEncoding]];
}
#endif

// singleton support
static PersistentProfile *shared = nil;
+ (PersistentProfile*)sharedInstance
{
    return (shared);
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

// ISPlugin protocol

- (id)initWithAppProxy:(id<ISPluginProxy>)proxy
{
    self = [super init];
    ISASSERT(shared == nil, "double load!");
    shared = self;
    mProxy = proxy;

#ifdef ISDEBUG
    mLog = [ScrobLogCreate(@"ISPersistence.log", 0, 1) retain];
#endif
    
    return (self);
}

- (NSString*)description
{
    return (NSLocalizedString(@"Persistence Plugin", ""));
}

- (void)applicationWillTerminate
{
#ifdef ISDEBUG
    [mLog closeFile];
    [mLog release];
    mLog = nil;
#endif
}

@end

@implementation PersistentProfile (SessionManagement)

- (BOOL)performSelectorOnSessionMgrThread:(SEL)selector withObject:(id)object
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread mainThread], "wrong thread!");
    #endif
    
    if (![sessionMgr threadMessenger])
        return (NO);
    
    [ISThreadMessenger makeTarget:[sessionMgr threadMessenger] performSelector:selector withObject:object];
    return (YES);
}

- (void)pingSessionManager
{
    static BOOL init = YES;
    if (init && ![self importInProgress]) {
        init = NO;
        [NSThread detachNewThreadSelector:@selector(sessionManagerThread:) toTarget:sessionMgr withObject:self];
    } else if (![self importInProgress]) {
        (void)[self performSelectorOnSessionMgrThread:@selector(sessionManagerUpdate) withObject:nil];
    }
}

- (BOOL)addSongPlaysToAllSessions:(NSArray*)queue
{
    ISASSERT([sessionMgr threadMessenger] != nil, "nil send port!");
    return ([self performSelectorOnSessionMgrThread:@selector(processSongPlays:) withObject:[[queue copy] autorelease]]);
}

@end

@implementation PersistentProfile (PItemAdditions)

- (BOOL)isSong:(NSManagedObject*)item
{
    return ([ITEM_SONG isEqualTo:[item valueForKey:@"itemType"]]);
}

- (BOOL)isArtist:(NSManagedObject*)item
{
    return ([ITEM_ARTIST isEqualTo:[item valueForKey:@"itemType"]]);
}

- (BOOL)isAlbum:(NSManagedObject*)item
{
    return ([ITEM_ALBUM isEqualTo:[item valueForKey:@"itemType"]]);
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
