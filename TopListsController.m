//
//  TopListsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/18/04.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "TopListsController.h"
#import "QueueManager.h"
#import "SongData.h"
#import "ISSearchArrayController.h"

static TopListsController *g_topLists = nil;

@implementation TopListsController

+ (TopListsController*)sharedInstance
{
    if (g_topLists)
        return (g_topLists);
    
    return ((g_topLists = [[TopListsController alloc] initWithWindowNibName:@"TopLists"]));
}

- (void)songQueuedHandler:(NSNotification*)note
{
    SongData *song = [[note userInfo] objectForKey:QM_NOTIFICATION_USERINFO_KEY_SONG];
    NSString *artist = [song artist], *track = [song title];
    NSMutableDictionary *entry;
    NSEnumerator *en;
    NSNumber *count;
    
    // Top Artists
    en = [[topArtistsController content] objectEnumerator];
    while ((entry = [en nextObject])) {
        if ([artist isEqualToString:[entry objectForKey:@"Artist"]]) {
            count = [entry objectForKey:@"Play Count"];
            count = [NSNumber numberWithUnsignedInt:
                [count unsignedIntValue] + 1];
            [entry setValue:count forKeyPath:@"Play Count"];
            break;
        }
    }

    if (!entry) {
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    [song artist], @"Artist", [NSNumber numberWithUnsignedInt:1], @"Play Count", nil];
    } else {
        entry = nil;
    }
    
    if (![topArtistsController isSearchInProgress]) {
        if (entry)
            [topArtistsController addObject:entry];
        [topArtistsController rearrangeObjects];
    } else if (entry) {
        // Can't alter the arrangedObjects array when a search is active
        // So manually enter the item in the content array
        NSMutableArray *contents = [topArtistsController content];
        [contents addObject:entry];
        [topArtistsController setContent:contents];
    }
    
    // Top Tracks
    en = [[topTracksController content] objectEnumerator];
    while ((entry = [en nextObject])) {
        if ([artist isEqualToString:[entry objectForKey:@"Artist"]] &&
             [track isEqualToString:[entry objectForKey:@"Track"]]) {
            count = [entry objectForKey:@"Play Count"];
            count = [NSNumber numberWithUnsignedInt:
                [count unsignedIntValue] + 1];
            [entry setValue:count forKeyPath:@"Play Count"];
            break;
        }
    }

    if (!entry) {
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    artist, @"Artist", [NSNumber numberWithUnsignedInt:1], @"Play Count",
                    track, @"Track", nil];
    } else {
        entry = nil;
    }
    
    if (![topTracksController isSearchInProgress]) {
        if (entry)
            [topTracksController addObject:entry];
        [topTracksController rearrangeObjects];
    } else if (entry) {
        // Can't alter the arrangedObjects array when a search is active
        // So manually enter the item in the content array
        NSMutableArray *contents = [topTracksController content];
        [contents addObject:entry];
        [topTracksController setContent:contents];
    }
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    if ((self = [super initWithWindowNibName:windowNibName])) {
        startDate = [[NSDate date] retain];
        
        //So stats are tracked while the window is close, load the nib to create our Array Controllers
        (void)[super window];
        
        // Register for QM notes
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(songQueuedHandler:)
                name:QM_NOTIFICATION_SONG_QUEUED
                object:nil];
        
        [super setWindowFrameAutosaveName:@"Top Lists"];
    }
    return (self);
}

- (IBAction)showWindow:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH];
    
    [super showWindow:sender];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH];
}

- (void)awakeFromNib
{
    // Seems NSArrayController adds an empty object for us, remove it
    if ([[topArtistsController content] count])
        [topArtistsController removeObjects:[topArtistsController content]];
    if ([[topTracksController content] count])
        [topTracksController removeObjects:[topTracksController content]];
        
    // Setup our sort descriptors
    NSSortDescriptor *playCountSort = [[NSSortDescriptor alloc] initWithKey:@"Play Count" ascending:NO];
    NSSortDescriptor *artistSort = [[NSSortDescriptor alloc] initWithKey:@"Artist" ascending:YES];
    NSArray *sorters = [NSArray arrayWithObjects:playCountSort, artistSort, nil];
    
    [topArtistsController setSortDescriptors:sorters];
    
    NSSortDescriptor *trackSort = [[NSSortDescriptor alloc] initWithKey:@"Track" ascending:YES];
    sorters = [NSArray arrayWithObjects:playCountSort, artistSort, trackSort, nil];
    [topTracksController setSortDescriptors:sorters];
    
    [playCountSort release];
    [artistSort release];
    [trackSort release];
}

@end