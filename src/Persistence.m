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
#import "SongData.h"
#import "ND/NDRunLoopMessenger.h"

#ifdef ISDEBUG
#include <mach/mach.h>
#include <mach/mach_time.h>

#define ISElapsedTimeInit() \
u_int32_t totalTracks = 0; \
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
**/

#define PERSISTENT_STORE_DB \
[@"~/Library/Application Support/org.bergstrand.iscrobbler.persistent.toplists.data" stringByExpandingTildeInPath]

#define ITEM_UNKNOWN @"u"
#define ITEM_SONG @"so"
#define ITEM_ARTIST @"a"
#define ITEM_ALBUM @"al"
#define ITEM_SESSION @"s"
#define ITEM_RATING_CCH @"r"
#define ITEM_HOUR_CCH @"h"

#define IS_THREAD_IMPORT 1
#define IS_THREAD_SESSIONMGR 1

#if IS_THREAD_SESSIONMGR
static NDRunLoopMessenger *mainMsgr = nil;
static id sessionMgrProxy = nil;
#endif

@interface SongData (PersistentAdditions)
- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc;
@end

@interface NSManagedObject (PItemMathAdditions)
- (void)incrementPlayCount:(NSNumber*)count;
- (void)incrementPlayTime:(NSNumber*)count;
- (void)incrementPlayCountWithObject:(NSManagedObject*)obj;
- (void)incrementPlayTimeWithObject:(NSManagedObject*)obj;

- (void)decrementPlayCount:(NSNumber*)count;
- (void)decrementPlayTime:(NSNumber*)count;
@end

@interface PersistentProfile (SessionManagement)
- (void)addSongPlaysToAllSessions:(NSArray*)queue;
- (NSManagedObject*)sessionWithName:(NSString*)name moc:(NSManagedObjectContext*)moc;
- (NSArray*)artistsForSession:(id)session moc:(NSManagedObjectContext*)moc;
- (NSArray*)albumsForSession:(id)session moc:(NSManagedObjectContext*)moc;
- (BOOL)addSessionSong:(NSManagedObject*)sessionSong toSession:(NSManagedObject*)session moc:(NSManagedObjectContext*)moc;
- (void)pingSessionManager;
@end

@interface PersistentProfileImport : NSObject {
    PersistentProfile *profile;
    NSString *currentArtist, *currentAlbum;
    NSManagedObjectContext *moc;
    NSManagedObject *moArtist, *moAlbum, *moSession, *mosArtist, *mosAlbum, *moPlayer;
}

- (void)importiTunesDB:(id)obj;
@end

@implementation PersistentProfile

+ (PersistentProfile*)sharedInstance
{
    static PersistentProfile *shared = nil;
    return (shared ? shared : (shared = [[PersistentProfile alloc] init]));
}

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
    [self postNote:PersistentProfileDidUpdateNotification];
}

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

- (NSArray*)allSessionsWithMOC:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"itemType == %@", ITEM_SESSION]];
    [[moc persistentStoreCoordinator] lock];
    NSArray *results = [moc executeFetchRequest:request error:&error];
    [[moc persistentStoreCoordinator] unlock];
    return (results);
}

- (NSManagedObject*)addSongPlay:(SongData*)song withImportedPlayCount:(NSNumber*)importCount moc:(NSManagedObjectContext*)moc
{
    NSManagedObject *psong = [song persistentSongWithContext:moc];
    
    if (psong) {
        NSEntityDescription *entity;
        
        // increment counts
        NSNumber *pCount;
        NSNumber *pTime;
        if (nil == importCount) {
            pCount = [NSNumber numberWithUnsignedInt:1];
            pTime = [psong valueForKey:@"duration"];
            
            // Make sure our play count is in sync with the player's
            NSNumber *songPlayedCount = [song playCount];
            if ([songPlayedCount unsignedIntValue] && [psong valueForKey:@"importedPlayCount"]
                && [[psong valueForKey:@"playCount"] isNotEqualTo:songPlayedCount]) {
                [psong setValue:songPlayedCount forKey:@"playCount"];
                pTime = [NSNumber numberWithUnsignedLongLong:[pTime unsignedLongLongValue] * [pCount unsignedLongLongValue]];
                [psong setValue:pTime forKey:@"playTime"];
                // Update album and artist with the delta as well?
                pTime = [psong valueForKey:@"duration"];
            }
        } else {
            pCount = importCount;
            pTime = [NSNumber numberWithUnsignedLongLong:
                [[psong valueForKey:@"duration"] unsignedLongLongValue] * [pCount unsignedLongLongValue]];
            [psong setValue:importCount forKey:@"importedPlayCount"];
        }
        [self updateSongHistory:psong count:pCount time:pTime moc:moc];
        
        // add to sessions
        NSManagedObject *sessionSong, *session;
        NSEnumerator *en = [[self allSessionsWithMOC:moc] objectEnumerator];
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
            
            if (![self addSessionSong:sessionSong toSession:session moc:moc]) 
                [moc deleteObject:sessionSong];
            
            [pool release];
        }
    }
    return (psong);
}

//******* public API ********//

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
        [self addSongPlaysToAllSessions:queue];
        [queue removeAllObjects];
    }
}

- (NSArray*)allSessions
{
    return ([self allSessionsWithMOC:mainMOC]);
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

- (NSArray*)artistsForSession:(id)session
{
    return ([self artistsForSession:session moc:mainMOC]);
}

- (NSArray*)albumsForSession:(id)session
{
    return ([self albumsForSession:session moc:mainMOC]);
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
        @"all", @"lastfm", @"pastday", @"pastweek", @"pastmonth", @"pastsixmonths", @"pastyear", @"temp", nil] objectEnumerator];
    NSArray *displayNames = [NSArray arrayWithObjects:
        NSLocalizedString(@"Overall", ""), NSLocalizedString(@"Last.fm Weekly", ""),
        NSLocalizedString(@"Today", ""), NSLocalizedString(@"Past Week", ""),
        NSLocalizedString(@"Past Month", ""), NSLocalizedString(@"Past Six Months", ""),
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
        
        [self initDB];
        NSManagedObject *allSession = [self sessionWithName:@"all" moc:mainMOC];
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

- (NSArray*)artistsForSession:(id)session moc:(NSManagedObjectContext*)moc
{
    NSError *error;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionArtist" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@)",
            ITEM_ARTIST, [session valueForKey:@"name"]]];
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
    
    NSDate *sub = [sessionSong valueForKey:@"submitted"];
    if ([sub isLessThan:[session valueForKey:@"epoch"]]
        || ([session valueForKey:@"term"] && [sub isGreaterThan:[session valueForKey:@"term"]]))
        return (NO);
    
    [sessionSong setValue:session forKey:@"session"];
    NSString *sessionName = [session valueForKey:@"name"], *itemName;
    NSManagedObject *artist, *album;
    NSError *error = nil;
    
    // Update the Artist
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionArtist" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    itemName = [sessionSong valueForKeyPath:@"item.artist.name"];
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@) AND (item.name LIKE[cd] %@)",
            ITEM_ARTIST, sessionName, itemName]];
    
    NSArray *result = [moc executeFetchRequest:request error:&error];
    if (1 == [result count]) {
        artist = [result objectAtIndex:0];
    } else if (0 == [result count]) {
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
        entity = [NSEntityDescription entityForName:@"PSessionAlbum" inManagedObjectContext:moc];
        [request setEntity:entity];
        itemName = [sessionSong valueForKeyPath:@"item.album.name"];
        #ifdef bugbug
        // XXX
        // Do to the way an SQLLite store is created, and the way a fetch is created for SQL, the "item.artist.name" will
        // generate an exception because the Artist, HourCache and RatingCache session item releationships
        // do not contain a valid artist relationship
        [request setPredicate:
            [NSPredicate predicateWithFormat:
                @"(itemType == %@) AND (session.name == %@) AND (item.name LIKE[cd] %@) AND (item.artist.name LIKE[cd] %@)",
                    ITEM_ALBUM, sessionName, itemName, [sessionSong valueForKeyPath:@"item.artist.name"]]];
        #endif
        // instead we just fetch on the item.name relationship and then pare down the results in memory.
        [request setPredicate:
            [NSPredicate predicateWithFormat:
                @"(itemType == %@) AND (session.name == %@) AND (item.name LIKE[cd] %@)", ITEM_ALBUM, sessionName, itemName]];
        
        result = [moc executeFetchRequest:request error:&error];
        if ([result count] > 0) {
            result = [result filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:
                @"item.artist.name LIKE[cd] %@", [sessionSong valueForKeyPath:@"item.artist.name"]]];
        }
        if (1 == [result count]) {
            album = [result objectAtIndex:0];
        } else if (0 == [result count]) {
            album = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
            [album setValue:ITEM_ALBUM forKey:@"itemType"];
            [album setValue:[sessionSong valueForKeyPath:@"item.album"] forKey:@"item"];
            [album setValue:session forKey:@"session"];
        } else
            ISASSERT(0, "multiple artist albums found in session!");
        
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

- (NSManagedObject*)sessionWithName:(NSString*)name moc:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSession" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"(itemType = %@) AND (name == %@)",
        ITEM_SESSION, name]];
    
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
        NSString *archiveName = [sessionName stringByAppendingFormat:@"-%@", [session valueForKey:@"epoch"]];
        [session setValue:archiveName forKey:@"name"];
        archiveName = [[session valueForKey:@"localizedName"] stringByAppendingFormat:@" (%@)", [session valueForKey:@"epoch"]];
        [session setValue:archiveName forKey:@"localizedName"];
        NSCalendarDate *term = [NSCalendarDate dateWithTimeIntervalSince1970:[newEpoch timeIntervalSince1970]-1.0];
        [session setValue:term forKey:@"term"];
        
        entity = [NSEntityDescription entityForName:@"PSessionArchive" inManagedObjectContext:moc];
        obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc];
        [session setValue:obj forKey:@"archive"];
        [obj setValue:[NSDate date] forKey:@"created"];
        [obj release];
        [[moc persistentStoreCoordinator] unlock];
        
#if IS_THREAD_SESSIONMGR
        // we've replaced a session object, it's important other threads and class clients are notified ASAP
        [self save:moc withNotification:NO];
        ISASSERT(moc != mainMOC, "invalid MOC!");
        [self performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
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
    NSEnumerator *en = [songs objectEnumerator];
    NSManagedObject *sessionSong, *mobj, *sArtist, *sAlbum;
    
    NSNumber *totalPlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    NSNumber *totalPlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    NSNumber *playCount, *playTime;
    
    NSArray *sessionArtists = [self artistsForSession:session moc:moc];
    NSArray *sessionAlbums = [self albumsForSession:session moc:moc];
    NSString *artistName;
    NSPredicate *filter;
    NSArray *filterResults;
    while ((sessionSong = [en nextObject])) {
        playCount = [sessionSong valueForKey:@"playCount"];
        playTime = [sessionSong valueForKey:@"playTime"];
        
        ISASSERT(1 == [playCount unsignedIntValue], "invalid play count!");
        // Update all dependencies
        
        // Artist
        artistName = [sessionSong valueForKeyPath:@"item.artist.name"];
        filter = [NSPredicate predicateWithFormat:@"item.name LIKE[cd] %@", artistName];
        filterResults = [sessionArtists filteredArrayUsingPredicate:filter];
        ISASSERT(1 == [filterResults count], "missing or mulitple artists!");
        sArtist = [filterResults objectAtIndex:0];
        [sArtist decrementPlayCount:playCount];
        [sArtist decrementPlayTime:playTime];
        
        // Album
        if ([sessionSong valueForKeyPath:@"item.album"]) {
            filter = [NSPredicate predicateWithFormat:@"(item.name LIKE[cd] %@) AND (item.artist.name LIKE[cd] %@)",
                [sessionSong valueForKeyPath:@"item.album.name"], artistName];
            filterResults = [sessionAlbums filteredArrayUsingPredicate:filter];
            ISASSERT(1 == [filterResults count], "missing or mulitple albums!");
            sAlbum = [filterResults objectAtIndex:0];
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
    [session decrementPlayCount:playCount];
    [session decrementPlayTime:playTime];
    
#ifdef ISDEBUG
    // Do some validation
    songs = [self songsForSession:session];
    totalPlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    totalPlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([totalPlayCount isEqualTo:[session valueForKey:@"playCount"]], "song play counts don't match session total!");
    ISASSERT([totalPlayTime isEqualTo:[session valueForKey:@"playTime"]], "song play times don't match session total!");
    
    songs = [self ratingsForSession:session];
    totalPlayCount = [songs valueForKeyPath:@"playCount.@sum.unsignedIntValue"];
    totalPlayTime = [songs valueForKeyPath:@"playTime.@sum.unsignedLongLongValue"];
    ISASSERT([totalPlayCount isEqualTo:[session valueForKey:@"playCount"]], "rating cache counts don't match session total!");
    ISASSERT([totalPlayTime isEqualTo:[session valueForKey:@"playTime"]], "rating cache times don't match session total!");
    
    songs = [self hoursForSession:session];
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
    
    NSManagedObject *session = [self sessionWithName:sessionName moc:moc];
    // round to avoid microsecond differences
    NSTimeInterval sepoch = floor([[session valueForKey:@"epoch"] timeIntervalSince1970]);
    if (sepoch >= floor([epoch timeIntervalSince1970]))
        return (NO); // nothing to do
    
    ISASSERT(![[session valueForKey:@"name"] isEqualTo:@"all"], "attempting removal on 'all' session!");
    
    // count invalid songs
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@) AND (submitted < %@)",
            ITEM_SONG, sessionName, epoch]];
    NSArray *invalidSongs = [moc executeFetchRequest:request error:&error];
    
    if (0 == [invalidSongs count]) {
        ScrobDebug(@"::%@:: no work to do", sessionName);
        [session setValue:epoch forKey:@"epoch"];
        return (NO);
    }
    
    // count valid songs
    [request setPredicate:
        [NSPredicate predicateWithFormat:@"(itemType == %@) AND (session.name == %@) AND (submitted >= %@)",
            ITEM_SONG, sessionName, epoch]];
    NSArray *validSongs = [moc executeFetchRequest:request error:&error];
    
    if ([validSongs count] > [invalidSongs count]) {
        [self removeSongs:invalidSongs fromSession:session moc:moc];
        ScrobDebug(@"removed %u songs from session %@", [invalidSongs count], sessionName);
    } else {
        // it's probably more efficient to destroy everything and add the valid songs back in
        // this will probably only occur with the daily and last.fm sessions.
        
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
        
        ScrobDebug(@"recreated session %@ with %u valid songs (%u invalid)", sessionName, [validSongs count], [invalidSongs count]);
    }
    
    [session setValue:epoch forKey:@"epoch"];
    
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while updating session %@ (%@)", sessionName, e);
    }
    return (YES);
}

- (void)updateLastfmSession:(NSTimer*)t
{
    NSManagedObjectContext *moc = t ? [t userInfo] : mainMOC;
    
    [lfmUpdateTimer invalidate];
    [lfmUpdateTimer autorelease];
    lfmUpdateTimer = nil;
    
    if (importing) {
        return;
    }
    
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
    (void)[self save:moc];
    if (didRemove) {
#if IS_THREAD_SESSIONMGR
        [moc reset];
        [self performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
#endif
    }
    
    epoch = [epoch dateByAddingYears:0 months:0 days:7 hours:0 minutes:0 seconds:0];
    
    lfmUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:[epoch timeIntervalSinceNow]
        target:self selector:@selector(updateLastfmSession:) userInfo:moc repeats:NO] retain];
}

- (void)updateSessions:(NSTimer*)t
{
    NSManagedObjectContext *moc = t ? [t userInfo] : mainMOC;
    
    [sUpdateTimer invalidate];
    [sUpdateTimer autorelease];
    sUpdateTimer = nil;
    
#if 0
    NSArray *songs = [[self songsForSession:[self sessionWithName:@"pastday" moc:moc]] sortedArrayUsingDescriptors:
        [NSArray arrayWithObject:[[NSSortDescriptor alloc] initWithKey:@"submitted" ascending:NO]]];
    NSEnumerator *en = [songs objectEnumerator];
    id obj;
    while ((obj = [en nextObject])) {
        ScrobLog(SCROB_LOG_TRACE, @"'%@','%@': sub:%@ playCount:%@", [obj valueForKeyPath:@"item.name"],
            [obj valueForKeyPath:@"item.artist.name"], /*[obj valueForKey:@"item.album.name"],*/
            [obj valueForKey:@"submitted"], [obj valueForKey:@"playCount"]);
    }
#endif
    
    if (importing) {
        return;
    }
    
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
    
    NSCalendarDate *lastSixMonths = [midnight dateByAddingYears:0 months:-6 days:0 hours:0 minutes:0 seconds:0];
    if ([self removeSongsBefore:lastSixMonths inSession:@"pastsixmonths" moc:moc])
        didRemove = YES;
    
    NSCalendarDate *lastYear = [midnight dateByAddingYears:-1 months:0 days:0 hours:0 minutes:0 seconds:0];
    if ([self removeSongsBefore:lastYear inSession:@"pastyear" moc:moc])
        didRemove = YES;
    
    (void)[self save:moc];
#if IS_THREAD_SESSIONMGR
    if (didRemove) {
        [moc reset];
        [self performSelectorOnMainThread:@selector(resetMain) withObject:nil waitUntilDone:NO];
    }
#endif
    
#ifndef REAP_DEBUG
    midnight = [midnight dateByAddingYears:0 months:0 days:0 hours:24 minutes:0 seconds:0];
#else
    midnight = [now dateByAddingYears:0 months:0 days:0 hours:1 minutes:0 seconds:0];
#endif
    
    sUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:[midnight timeIntervalSinceNow]
        target:self selector:@selector(updateSessions:) userInfo:moc repeats:NO] retain];
}

- (void)processSongPlays:(NSArray*)queue
{
    NSManagedObjectContext *moc;
#if IS_THREAD_SESSIONMGR
    moc = [[[NSThread currentThread] threadDictionary] objectForKey:@"moc"];
    ISASSERT(moc != nil, "missing thread MOC!");
#else
    moc = mainMOC;
#endif
    
    NSEnumerator *en = [queue objectEnumerator];
    id obj;
    NSManagedObject *moSong;
    NSMutableArray *addedSongs = [NSMutableArray array];;
    while ((obj = [en nextObject])) {
        if ((moSong = [self addSongPlay:obj withImportedPlayCount:nil moc:moc]))
            [addedSongs addObject:moSong];
        else
            [moc rollback];
    }
    (void)[self save:moc];
#if IS_THREAD_SESSIONMGR
    // Turn the added songs into faults as we probably won't need them anytime soon
    // (we may need the artist/album/session objects though). This should save on some memory.
    en = [addedSongs objectEnumerator];
    while ((moSong = [en nextObject])) {
        [[moSong managedObjectContext] refreshObject:moSong mergeChanges:NO];
    }
    
    [queue release];
#endif
}

#if IS_THREAD_SESSIONMGR
- (void)sessionManagerUpdate
{
    [lfmUpdateTimer fire];
    [sUpdateTimer fire];
}

- (void)sessionManager:(id)messenger
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] init];
    [moc setUndoManager:nil];
    [moc setPersistentStoreCoordinator:[mainMOC persistentStoreCoordinator]];
    double pri = [NSThread threadPriority];
    [NSThread setThreadPriority:pri - (pri * 0.10)];
    
    [[[NSThread currentThread] threadDictionary] setObject:moc forKey:@"moc"];
    
    [[NSTimer timerWithTimeInterval:0 target:self selector:@selector(updateLastfmSession:) userInfo:moc repeats:NO] fire];
    [[NSTimer timerWithTimeInterval:0 target:self selector:@selector(updateSessions:) userInfo:moc repeats:NO] fire];
    
    // we should now have scheduled timers in our run loop, so start it
    id ndmsgr = [[NDRunLoopMessenger runLoopMessengerForCurrentRunLoop] retain];
    sessionMgrProxy = [[ndmsgr target:self] retain];
    
    do {
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
        [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    } while (1);
    
    ISASSERT(0, "sessionManager run loop exited!");
    [ndmsgr release];
    [sessionMgrProxy release];
    [pool release];
    [NSThread exit];
}
#endif

- (void)pingSessionManager
{
#if IS_THREAD_SESSIONMGR
    if (!mainMsgr && !importing) {
        mainMsgr = [[NDRunLoopMessenger alloc] init];
        [NSThread detachNewThreadSelector:@selector(sessionManager:) toTarget:self withObject:mainMsgr];
    } else if (!importing) {
        [mainMsgr target:sessionMgrProxy performSelector:@selector(sessionManagerUpdate) withResult:NO];
    }
#else
    [self updateLastfmSession:nil];
    [self updateSessions:nil];
    [self resetMain];
#endif
}

- (void)addSongPlaysToAllSessions:(NSArray*)queue
{
#if IS_THREAD_SESSIONMGR
    [mainMsgr target:sessionMgrProxy performSelector:@selector(processSongPlays:) withObject:[queue copy] withResult:NO];
#else
    [self processSongPlays:queue];
#endif
}

@end

#import "iTunesImport.m"

@implementation SongData (PersistentAdditions)

- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc
{
    NSError *error = nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSong" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
    @try {
    
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
    if (1 == [result count]) {
         // Update song values
        moSong = [result objectAtIndex:0];
        [moSong setValue:[self postDate] forKey:@"submitted"];
        [moSong setValue:myLastPlayed forKey:@"lastPlayed"];
         
        return (moSong);
    }
    
    // Song not found
    ISASSERT(0 == [result count], "multiple songs found in db!");
    
    NSManagedObject *moArtist, *moAlbum;
    moSong = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
    [moSong setValue:ITEM_SONG forKey:@"itemType"];
    [moSong setValue:[self title] forKey:@"name"];
    [moSong setValue:[self duration] forKey:@"duration"];
    [moSong setValue:[self postDate] forKey:@"submitted"];
    [moSong setValue:myLastPlayed forKey:@"firstPlayed"];
    [moSong setValue:myLastPlayed forKey:@"lastPlayed"];
    [moSong setValue:[self scaledRating] forKey:@"rating"];
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
    } else
        ISASSERT(0, "multiple artists found in db!");
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
        } else
            ISASSERT(0, "multiple artists found in db!");
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
        ScrobLog(SCROB_LOG_ERR, @"exception creating song for %@ (%@)", [self brief], e);
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
    u_int32_t playCount = [[self valueForKey:@"playCount"] unsignedIntValue] - [count unsignedIntValue];
    [self setValue:[NSNumber numberWithUnsignedInt:playCount] forKey:@"playCount"];
}

- (void)decrementPlayTime:(NSNumber*)count
{
    u_int64_t playTime = [[self valueForKey:@"playTime"] unsignedLongLongValue] - [count unsignedLongLongValue];
    [self setValue:[NSNumber numberWithUnsignedLongLong:playTime] forKey:@"playTime"];
}

@end
