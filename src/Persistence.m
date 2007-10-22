//
//  Persistence.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/3/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "Persistence.h"
#import "PersistentSessionManager.h"
#import "SongData.h"

#ifdef ISDEBUG
#include <mach/mach.h>
#include <mach/mach_time.h>

#define ISElapsedTimeInit() \
u_int64_t start, end, diff; \
double abs2clockns; \
mach_timebase_info_data_t info; \
(void)mach_timebase_info(&info); \

#define ISStartTime() do { start = mach_absolute_time(); } while(0)
#define ISEndTime() do { \
    end = mach_absolute_time(); \
    diff = end - start; \
    abs2clockns = (double)info.numer / (double)info.denom; \
    abs2clockns *= diff; \
} while(0)
#else
#define ISElapsedTimeInit() {}
#define ISStartTime() {}
#define ISEndTime() {}
#endif

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
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self];
}

- (BOOL)save:(NSManagedObjectContext*)moc withNotification:(BOOL)notify
{
    NSError *error;
    if ([moc save:&error]) {
        if (notify)
            [self performSelectorOnMainThread:@selector(postNote:) withObject:PersistentProfileDidUpdateNotification waitUntilDone:NO];
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
    [self save:mainMOC withNotification:NO];
    [mainMOC reset];
    // so clients can refresh themselves
    [self postNote:PersistentProfileDidResetNotification];
}

- (NSManagedObjectContext*)mainMOC
{
    return (mainMOC);
}

//******* public API ********//

- (BOOL)newProfile
{
    return (newProfile);
}

- (BOOL)importInProgress
{
    return (importing);
}

- (BOOL)canApplicationTerminate
{
    return (!importing /*&& update thread inactive*/);
}

- (void)addSongPlay:(SongData*)song
{
    static NSMutableArray *queue = nil;
    if (!queue)
        queue = [[NSMutableArray alloc] init];
    
    if (song)
        [queue addObject:song];
    
    // the importer makes the assumption that no one else will modify the DB (so it doesn't have to search as much)
    if (!importing && [queue count] > 0) {
        if ([self addSongPlaysToAllSessions:queue])
            [queue removeAllObjects];
    }
}

- (NSArray*)allSessions
{
    return ([sessionMgr allSessionsWithMOC:mainMOC]);
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
    
    NSString *format = @"(song.name LIKE[cd] %@) AND (song.artist.name LIKE[cd] %@)";
    NSString *album = [song album];
    if (!ignoreAlbum && album && [album length] > 0)
        format = [format stringByAppendingString:@" AND (song.album.name LIKE[cd] %@)"];
    else
        album = nil;
    [request setPredicate:[NSPredicate predicateWithFormat:format, [song title], [song artist], album]];
    
    return ([mainMOC executeFetchRequest:request error:&error]);
}

- (u_int32_t)playCountForSong:(SongData*)song ignoreAlbum:(BOOL)ignoreAlbum
{
    return (0);
}
#endif

//******* end public API ********//

- (NSManagedObject*)playerWithName:(NSString*)name moc:(NSManagedObjectContext*)moc
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:[NSEntityDescription entityForName:@"PPlayer" inManagedObjectContext:moc]];
    [request setPredicate:[NSPredicate predicateWithFormat:@"name LIKE[cd] %@", name]];
    
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
    importing  = NO;
    //[self setValue:[NSNumber numberWithBool:NO] forKey:@"importing"];
    
    // Reset so any cached objects are forced to refault
    ISASSERT(NO == [mainMOC hasChanges], "somebody modifed the DB during an import");
    [self resetMain];
    
    [self addSongPlay:nil]; // process any queued songs
    [self pingSessionManager];
}

- (void)initDB
{
    NSCalendarDate *now = [NSCalendarDate distantPast];
    
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
    int i = 0;
    while ((name = [en nextObject])) {
        obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:mainMOC];
        [obj setValue:ITEM_SESSION forKey:@"itemType"];
        [obj setValue:name forKey:@"name"];
        [obj setValue:now forKey:@"epoch"];
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
    // NSXMLStoreType is super slow, but great for looking at the DB internals (debugging)
    NSDictionary *metadata;
    if (!(metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreWithURL:url error:nil])) {
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
        
        newProfile = YES;
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
        
        mainStore = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error];
    }
    
    // we don't allow the user to make changes and the session mgr background thread handles all internal changes
    [mainMOC setMergePolicy:NSRollbackMergePolicy];

    [self pingSessionManager];
    
    if (NO == [[metadata objectForKey:@"ISDidImportiTunesLibrary"] boolValue]) {
        importing = YES;
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

- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (unsigned)retainCount
{
    return (UINT_MAX);  //denotes an object that cannot be released
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
    if (init && !importing) {
        #ifdef ISDEBUG
        mainThread = [NSThread currentThread];
        #endif
        init = NO;
        [NSThread detachNewThreadSelector:@selector(sessionManagerThread:) toTarget:sessionMgr withObject:self];
    } else if (!importing) {
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

#import "iTunesImport.m"
