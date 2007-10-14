//
//  iTunesImport.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/7/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

@interface SongData (iTunesImport)
- (SongData*)initWithiTunesXMLTrack:(NSDictionary*)track;
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

/** This is faster than [addSongPlay:] when aggregated over many imports,
     as it makes assumptions to avoid searching as much as possible:
     1: There are no existing artists or albums
     2: The DB will not be modified during an import
**/
- (void)importSong:(SongData*)song withPlayCount:(NSNumber*)playCount
{
    NSError *error;
    NSEntityDescription *entity;
    NSPredicate *predicate;
    NSString *aTitle;
    
    @try {
    
    NSManagedObject *moSong, *mosSong;
    if (!currentArtist || NSOrderedSame != [currentArtist caseInsensitiveCompare:[song artist]]) {
        // Saving less often is a much greater performance gain (as opposed to saving after every track)
        // than [importSong:] vs [addSong:]
        (void)[profile save:moc withNotification:NO];
        [moc reset]; // purge memory
        
        [self killCachedObjects];
        
        // recreate our cached objects 
        currentArtist = [[song artist] retain];
        
        moSession = [[profile sessionWithName:@"all" moc:moc] retain];
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
    if ((aTitle = [song album]) && [aTitle length] > 0) {
        predicate = [NSPredicate predicateWithFormat:
            @"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@) AND (album.name LIKE[cd] %@)",
            ITEM_SONG, [song title], [song artist], aTitle];
    } else {
        aTitle = nil;
        predicate = [NSPredicate predicateWithFormat:
            @"(itemType == %@) AND (name LIKE[cd] %@) AND (artist.name LIKE[cd] %@)",
            ITEM_SONG, [song title], [song artist]];
    }
    [request setPredicate:predicate];
    
    NSNumber *playTime;
    playTime = [NSNumber numberWithUnsignedLongLong:[playCount unsignedLongLongValue] * [[song duration] unsignedLongLongValue]];
    NSArray *result = [moc executeFetchRequest:request error:&error];
    if (1 == [result count]) {
         // Update song values
        moSong = [result objectAtIndex:0];
        [moSong setValue:[song lastPlayed] forKey:@"lastPlayed"];
        [profile updateSongHistory:moSong count:playCount time:playTime moc:moc];
        
        // Get the session alias, there should only be one
        NSSet *aliases = [moSong valueForKey:@"sessionAliases"];
        ISASSERT([aliases count] > 0, "invalid state - missing session aliases!");
        mosSong = [aliases anyObject];
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
        [moSong setValue:[song scaledRating] forKey:@"rating"];
        if ([[song trackNumber] intValue] > 0)
            [moSong setValue:[song trackNumber] forKey:@"trackNumber"];
        if ([[song mbid] length] > 0)
            [moSong setValue:[song mbid] forKey:@"mbid"];
        [moSong setValue:playCount forKey:@"importedPlayCount"];
        
        [moSong setValue:moArtist forKey:@"artist"];
        [moSong setValue:moAlbum forKey:@"album"];
        [moSong setValue:moPlayer forKey:@"player"];
        [profile updateSongHistory:moSong count:playCount time:playTime moc:moc];
        
        // Create the session alias
        entity = [NSEntityDescription entityForName:@"PSessionSong" inManagedObjectContext:moc];
        mosSong = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:moc] autorelease];
        [mosSong setValue:ITEM_SONG forKey:@"itemType"];
        [mosSong setValue:moSong forKey:@"item"];
        [mosSong setValue:[moSong valueForKey:@"submitted"] forKey:@"submitted"];
        [mosSong setValue:moSession forKey:@"session"];
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
    [profile incrementSessionCountsWithSong:mosSong moc:moc];
    
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception creating song for %@ (%@)", [song brief], e);
    }
}

- (void)importiTunesDB:(id)obj
{
    u_int32_t importedTracks = 0;
    ISElapsedTimeInit();

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    profile = obj;
#if IS_THREAD_IMPORT
    moc = [[NSManagedObjectContext alloc] init];
    [moc setPersistentStoreCoordinator:[[profile valueForKey:@"mainMOC"] persistentStoreCoordinator]];
    double pri = [NSThread threadPriority];
    [NSThread setThreadPriority:pri - (pri * 0.20)];
#else
    moc = [[profile valueForKey:@"mainMOC"] retain];
#endif
    
    @try {
    
    ISStartTime();
    
    NSString *path = [@"~/Music/iTunes/iTunes Music Library.xml" stringByExpandingTildeInPath];
    NSDictionary *iTunesLib = [[NSDictionary alloc] initWithContentsOfFile:path];
    if (!iTunesLib) {
        path = [@"~/Documents/iTunes/iTunes Music Library.xml" stringByExpandingTildeInPath];
        if (!(iTunesLib = [[NSDictionary alloc] initWithContentsOfFile:path])) {
            @throw ([NSException exceptionWithName:NSGenericException reason:@"iTunes XML Library not found" userInfo:nil]);
        }
    }
    
    // Sorting the array allows to optimze import by making eliminating the need to search for existing artist/albums
    NSArray *allTracks = [[[iTunesLib objectForKey:@"Tracks"] allValues]
        sortedArrayUsingDescriptors:[NSArray arrayWithObjects:
        [[[NSSortDescriptor alloc] initWithKey:@"Artist" ascending:YES selector:@selector(caseInsensitiveCompare:)] autorelease],
        [[[NSSortDescriptor alloc] initWithKey:@"Album" ascending:YES selector:@selector(caseInsensitiveCompare:)] autorelease],
        [[[NSSortDescriptor alloc] initWithKey:@"Play Date UTC" ascending:NO] autorelease],
        nil]];
    (void)[allTracks retain];
    NSString *uuid = [[iTunesLib objectForKey:@"Library Persistent ID"] retain];
    [iTunesLib release];
    iTunesLib = nil;
    
    [pool release];
    pool = [[NSAutoreleasePool alloc] init];
    (void)[allTracks autorelease];
    (void)[uuid autorelease];
    
    ISEndTime();
    ScrobDebug(@"Opened iTunes Library in %.4lf seconds", (abs2clockns / 1000000000.0));
    ISStartTime();
    
#ifdef ISDEBUG
    totalTracks = [allTracks count];
#endif
    
    NSNumber *epochSecs = [allTracks valueForKeyPath:@"Date Added.@min.timeIntervalSince1970"];
    if (!epochSecs)
        @throw ([NSException exceptionWithName:NSGenericException reason:@"could not calculate library epoch" userInfo:nil]);
    
    NSCalendarDate *epoch = [NSCalendarDate dateWithTimeIntervalSince1970:[epochSecs doubleValue]];
    
    NSManagedObject *allSession = [profile sessionWithName:@"all" moc:moc];
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
        [self importSong:song withPlayCount:[track objectForKey:@"Play Count"]];
        #ifdef obsolete
        [profile addSongPlay:song withImportedPlayCount:[track objectForKey:@"Play Count"] moc:moc];
        (void)[profile save:moc withNotification:NO];
        #endif
        [[moc persistentStoreCoordinator] unlock];
        
        if (0 == (++importedTracks % 5)) {
            [trackPool release];
            trackPool = [[NSAutoreleasePool alloc] init];
        }

#ifdef ISDEBUG
        if (0 == (importedTracks % 250)) {
            ISEndTime();
            ScrobDebug(@"Imported %u tracks (of %u) in %.4lf seconds", importedTracks, totalTracks, (abs2clockns / 1000000000.0));
        }
#endif
    }
    [trackPool release];
    trackPool = nil;
    
    if (uuid && [uuid length] > 0) {
        [[profile playerWithName:@"iTunes" moc:moc] setValue:uuid forKey:@"libraryUUID"];
    }
    
    id store = [[[moc persistentStoreCoordinator] persistentStores] objectAtIndex:0];
    NSMutableDictionary *d = [[[[moc persistentStoreCoordinator] metadataForPersistentStore:store] mutableCopy] autorelease];
    [d setObject:[NSNumber numberWithBool:YES] forKey:@"ISDidImportiTunesLibrary"];
    [[moc persistentStoreCoordinator] setMetadata:d forPersistentStore:store];
    (void)[profile save:moc withNotification:NO];
        
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception while importing iTunes library (%@)", e);
    }
    
    [self killCachedObjects];
    [moc release];
    
    ISEndTime();
    ScrobDebug(@"Imported %u tracks (of %u) in %.4lf seconds", importedTracks, totalTracks, (abs2clockns / 1000000000.0));
    
    [profile performSelectorOnMainThread:@selector(importDidFinish:) withObject:nil waitUntilDone:NO];
    [pool release];
    
#if IS_THREAD_IMPORT
    [NSThread exit];
#endif
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
    
    if ((obj = [track objectForKey:@"Kind"])
        && NSNotFound == [obj rangeOfString:@"file" options:NSCaseInsensitiveSearch].location) {
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
    
    #ifdef notyet
    if (!(obj = [track objectForKey:@"Location"]))
        obj = @"";
    #endif
    
    return (self);
}

@end
