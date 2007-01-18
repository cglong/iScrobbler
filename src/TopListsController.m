//
//  TopListsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/18/04.
//  Copyright 2004-2007 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "iScrobblerController.h"
#import "TopListsController.h"
#import "QueueManager.h"
#import "SongData.h"
#import "ISSearchArrayController.h"
#import "ISProfileDocumentController.h"
#import "ScrobLog.h"
#import "ISArtistDetailsController.h"
#import "ProtocolManager.h"
#import "ASXMLRPC.h"
#import "ISRecommendController.h"
#import "ISTagController.h"
#import "ISLoveBanListController.h"

enum {
    kTBItemRequiresSelection      = 0x00000001,
    kTBItemRequiresTrackSelection = 0x00000002,
    kTBItemNoMultipleSelection    = 0x00000004,
    kTBItemDisabledForFeedback    = 0x00000008,
};

// From iScrobblerController.m
void ISDurationsFromTime(unsigned int, unsigned int*, unsigned int*, unsigned int*, unsigned int*);

static TopListsController *g_topLists = nil;
static NSMutableDictionary *topAlbums = nil;
static NSCountedSet *topRatings = nil;

// This is the ASCII Record Separator char code
#define TOP_ALBUMS_KEY_TOKEN @"\x1e"

#define TOP_LISTS_PERSISTENT_STORE \
[@"~/Library/Caches/net.sourceforge.iscrobbler.persistent.toplists.plist" stringByExpandingTildeInPath]

@interface NSString (ISHTMLConversion)
- (NSString *)stringByConvertingCharactersToHTMLEntities;
@end

@interface NSMutableDictionary (ISTopListsAdditions)
- (void)mergeValuesUsingCaseInsensitiveCompare;
- (NSComparisonResult)sortByPlayCount:(NSDictionary*)entry;
- (NSComparisonResult)sortByDuration:(NSDictionary*)entry;
@end

@implementation TopListsController

+ (TopListsController*)sharedInstance
{
    if (g_topLists)
        return (g_topLists);
    
    return ((g_topLists = [[TopListsController alloc] initWithWindowNibName:@"TopLists"]));
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if (g_topLists == nil) {
            return ([super allocWithZone:zone]);
        }
    }

    return (g_topLists);
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

#define PLAY_TIME_FORMAT @"%u:%02u:%02u:%02u"
- (void)songQueuedHandler:(NSNotification*)note
{
    SongData *song = [[note userInfo] objectForKey:QM_NOTIFICATION_USERINFO_KEY_SONG];
    NSString *artist = [song artist], *track = [song title], *playTime;
    NSMutableDictionary *entry;
    NSEnumerator *en;
    NSNumber *count;
    unsigned int time, days, hours, minutes, seconds;
    
    
    // Top Artists
    en = [[topArtistsController content] objectEnumerator];
    while ((entry = [en nextObject])) {
        if (NSOrderedSame == [artist caseInsensitiveCompare:[entry objectForKey:@"Artist"]]) {
            count = [entry objectForKey:@"Play Count"];
            count = [NSNumber numberWithUnsignedInt:
                [count unsignedIntValue] + 1];
            [entry setValue:count forKeyPath:@"Play Count"];
            
            time = [[entry objectForKey:@"Total Duration"] unsignedIntValue];
            time += [[song duration] unsignedIntValue];
            ISDurationsFromTime(time, &days, &hours, &minutes, &seconds);
            playTime = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
            [entry setValue:[NSNumber numberWithUnsignedInt:time] forKeyPath:@"Total Duration"];
            [entry setValue:playTime forKeyPath:@"Play Time"];
            break;
        }
    }

    if (!entry) {
        time = [[song duration] unsignedIntValue];
        ISDurationsFromTime(time, &days, &hours, &minutes, &seconds);
        playTime = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    [song artist], @"Artist", [NSNumber numberWithUnsignedInt:1], @"Play Count",
                    [song duration], @"Total Duration", playTime, @"Play Time", nil];
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
    id lastPlayedDate = [[song startTime] addTimeInterval:[[song duration] doubleValue]];
    
    if ([startDate isGreaterThan:lastPlayedDate]) {
        // This can occur when iScrobbler is launched after the last played date of tracks on an iPod
        [self setValue:lastPlayedDate forKey:@"startDate"];
    }
    
    en = [[topTracksController content] objectEnumerator];
    while ((entry = [en nextObject])) {
        if (NSOrderedSame == [artist caseInsensitiveCompare:[entry objectForKey:@"Artist"]] &&
             NSOrderedSame == [track caseInsensitiveCompare:[entry objectForKey:@"Track"]]) {
            count = [entry objectForKey:@"Play Count"];
            count = [NSNumber numberWithUnsignedInt:
                [count unsignedIntValue] + 1];
            [entry setValue:count forKeyPath:@"Play Count"];
            [entry setValue:lastPlayedDate forKeyPath:@"Last Played"];
            break;
        }
    }

    if (!entry) {
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    artist, @"Artist", [NSNumber numberWithUnsignedInt:1], @"Play Count",
                    track, @"Track", lastPlayedDate, @"Last Played", nil];
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
    
    // The following are currently only used for Profile generation
    NSString *album;
    if ((album = [song album]) && [album length] > 0) {
        if (!topAlbums)
            topAlbums = [[NSMutableDictionary alloc] init];
        NSString *key = [NSString stringWithFormat:@"%@" TOP_ALBUMS_KEY_TOKEN @"%@",
            artist, album];
        if ((entry = [topAlbums objectForKey:key])) {
            time = [[song duration] unsignedIntValue] + [[entry objectForKey:@"Total Duration"] unsignedIntValue];
            count = [entry objectForKey:@"Play Count"];
            count = [NSNumber numberWithUnsignedInt:[count unsignedIntValue] + 1];
            [entry setObject:count forKey:@"Play Count"];
            [entry setObject:[NSNumber numberWithUnsignedInt:time] forKey:@"Total Duration"];
        } else {
            count = [NSNumber numberWithUnsignedInt:1];
            entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                        count, @"Play Count",
                        [song duration], @"Total Duration",
                        nil];
            [topAlbums setObject:entry forKey:key];
        }
    }
    
    NSNumber *rating;
    if (!topRatings) {
        // 0 - 5 stars == 6 items
        topRatings = [[NSCountedSet alloc] initWithCapacity:6];
    }
    rating = [song rating] ? [song rating] : [NSNumber numberWithInt:0];
    [topRatings addObject:rating];
    
    [self writePersistentStore];
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    if ((self = [super initWithWindowNibName:windowNibName])) {
        startDate = [[NSDate date] retain];
        
        // So stats are tracked while the window is closed, load the nib to create our Array Controllers
        // [super window] should be calling setDelegate itself, but it's not doing it for some reason.
        // It works correctly in [StatisticsController showWindow:].
        [[super window] setDelegate:self];
        
        // Register for QM notes
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(songQueuedHandler:)
                name:QM_NOTIFICATION_SONG_QUEUED
                object:nil];
    }
    return (self);
}

- (void)selectionDidChange:(NSNotification*)note
{
    @try {
    NSString *artist = [[[note object] dataSource] valueForKeyPath:@"selection.Artist"];
    [artistDetails setArtist:artist];
    } @catch (id e) {}
}

#if 0
- (BOOL)detailsOpen
{
    return ([[artistDetails valueForKey:@"detailsOpen"] boolValue]);
}
#endif

- (IBAction)hideDetails:(id)sender
{
    [topArtistsTable deselectAll:nil];
    [topTracksTable deselectAll:nil];
}

- (void)loadDetails
{
    if ([ISArtistDetailsController canLoad]) {
        id details;
        if ((details = [[ISArtistDetailsController artistDetailsWithDelegate:self] retain])) {
            [self setValue:details forKey:@"artistDetails"];
            ISASSERT(nil != artistDetails, "setValue failed!");
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectionDidChange:)
                name:NSTableViewSelectionDidChangeNotification object:topArtistsTable];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectionDidChange:)
                name:NSTableViewSelectionDidChangeNotification object:topTracksTable];
        }
    }
}

- (IBAction)showWindow:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH];
    
    [super showWindow:sender];
    
    if (!artistDetails)
        [self loadDetails];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    //[rpcreqs removeAll];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH];
    [self hideDetails:nil];
}

- (void)handleDoubleClick:(NSTableView*)sender
{
    NSIndexSet *indices;
    if ([sender respondsToSelector:@selector(selectedRowIndexes)])
        indices = [sender selectedRowIndexes];
    else
        return;
    
    if (indices) {
        NSArray *data;
        
        @try {
            data = [[sender dataSource] arrangedObjects];
        } @catch (NSException *exception) {
            return;
        }
        
        NSURL *url;
        NSMutableArray *urls = [NSMutableArray arrayWithCapacity:[indices count]];
        unsigned idx = [indices firstIndex];
        for (; NSNotFound != idx; idx = [indices indexGreaterThanIndex:idx]) {
            @try {
                NSDictionary *entry = [data objectAtIndex:idx];
                NSString *artist = [entry objectForKey:@"Artist"];
                NSString *track  = [entry objectForKey:@"Track"];
                if (!artist)
                    continue;
                
                url = [[NSApp delegate] audioScrobblerURLWithArtist:artist trackTitle:track];
                [urls addObject:url]; 
            } @catch (NSException *exception) {
                ScrobLog (SCROB_LOG_TRACE, @"Exception generating URL: %@", exception);
            }
        } // for
        
        NSEnumerator *en = [urls objectEnumerator];
        while ((url = [en nextObject])) {
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
    }
}

- (void)awakeFromNib
{
    [super setWindowFrameAutosaveName:@"Top Lists"];
    
    NSString *title = [NSString stringWithFormat:@"%@ - %@", [[super window] title],
        [[NSUserDefaults standardUserDefaults] objectForKey:@"version"]];
    [[self window] setTitle:title];
    
    // Seems NSArrayController adds an empty object for us, remove it
    if ([[topArtistsController content] count])
        [topArtistsController removeObjects:[topArtistsController content]];
    if ([[topTracksController content] count])
        [topTracksController removeObjects:[topTracksController content]];
        
    // Setup our sort descriptors
    NSSortDescriptor *playCountSort = [[NSSortDescriptor alloc] initWithKey:@"Play Count" ascending:NO];
    NSSortDescriptor *artistSort = [[NSSortDescriptor alloc] initWithKey:@"Artist" ascending:YES];
    NSSortDescriptor *playTimeSort = [[NSSortDescriptor alloc] initWithKey:@"Play Time" ascending:YES];
    NSArray *sorters = [NSArray arrayWithObjects:playCountSort, artistSort, playTimeSort, nil];
    
    [topArtistsController setSortDescriptors:sorters];
    
    NSSortDescriptor *trackSort = [[NSSortDescriptor alloc] initWithKey:@"Track" ascending:YES];
    sorters = [NSArray arrayWithObjects:playCountSort, artistSort, trackSort, nil];
    [topTracksController setSortDescriptors:sorters];
    
    [playCountSort release];
    [artistSort release];
    [playTimeSort release];
    [trackSort release];
    
    [topArtistsTable setTarget:self];
    [topArtistsTable setDoubleAction:@selector(handleDoubleClick:)];
    [topTracksTable setTarget:self];
    [topTracksTable setDoubleAction:@selector(handleDoubleClick:)];
    
    [self restorePersistentStore];
    [self hideDetails:nil];
    
    if ([ASXMLRPC isAvailable]) {
        // Create toolbar
        toolbarItems = [[NSMutableDictionary alloc] init];
        
        NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"toplists"];
        [tb setDisplayMode:NSToolbarDisplayModeLabelOnly]; // XXX
        [tb setSizeMode:NSToolbarSizeModeSmall];
        [tb setDelegate:self];
        [tb setAllowsUserCustomization:NO];
        [tb setAutosavesConfiguration:NO];
        #ifdef looksalittleweird
        [tb setShowsBaselineSeparator:NO]; // 10.4 only, but ASXMLRPC won't load w/o it
        #endif
        
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:@"love"];
        title = [NSString stringWithFormat:@"%C ", 0x2665];
        [item setLabel:[title stringByAppendingString:NSLocalizedString(@"Love", "")]];
        [item setToolTip:NSLocalizedString(@"Love the currently playing track.", "")];
        [item setPaletteLabel:[item label]];
        [item setTarget:self];
        [item setAction:@selector(loveTrack:)];
        // [item setImage:[NSImage imageNamed:@""]];
        [item setTag:kTBItemRequiresSelection|kTBItemRequiresTrackSelection];
        [toolbarItems setObject:item forKey:@"love"];
        [item release];
        
        item = [[NSToolbarItem alloc] initWithItemIdentifier:@"ban"];
        title = [NSString stringWithFormat:@"%C ", 0x2298];
        [item setLabel:[title stringByAppendingString:NSLocalizedString(@"Ban", "")]];
        [item setToolTip:NSLocalizedString(@"Ban the currently playing track from last.fm.", "")];
        [item setPaletteLabel:[item label]];
        [item setTarget:self];
        [item setAction:@selector(banTrack:)];
        // [item setImage:[NSImage imageNamed:@""]];
        [item setTag:kTBItemRequiresSelection|kTBItemRequiresTrackSelection];
        [toolbarItems setObject:item forKey:@"ban"];
        [item release];
        
        item = [[NSToolbarItem alloc] initWithItemIdentifier:@"recommend"];
        title = [NSString stringWithFormat:@"%C ", 0x2709];
        [item setLabel:[title stringByAppendingString:NSLocalizedString(@"Recommend", "")]];
        [item setToolTip:NSLocalizedString(@"Recommend the currently playing track to another last.fm user.", "")];
        [item setPaletteLabel:[item label]];
        [item setTarget:self];
        [item setAction:@selector(recommend:)];
        // [item setImage:[NSImage imageNamed:@""]];
        [item setTag:kTBItemRequiresSelection|kTBItemNoMultipleSelection];
        [toolbarItems setObject:item forKey:@"recommend"];
        [item release];
        
        item = [[NSToolbarItem alloc] initWithItemIdentifier:@"tag"];
        title = [NSString stringWithFormat:@"%C ", 0x270E];
        [item setLabel:[title stringByAppendingString:NSLocalizedString(@"Tag", "")]];
        [item setToolTip:NSLocalizedString(@"Tag the currently playing track.", "")];
        [item setPaletteLabel:[item label]];
        [item setTarget:self];
        [item setAction:@selector(tag:)];
        // [item setImage:[NSImage imageNamed:@""]];
        [item setTag:kTBItemRequiresSelection];
        [toolbarItems setObject:item forKey:@"tag"];
        [item release];
        
        item = [[NSToolbarItem alloc] initWithItemIdentifier:@"showloveban"];
        [item setLabel:NSLocalizedString(@"Show Loved/Banned", "")];
        [item setToolTip:NSLocalizedString(@"Show recently Loved or Banned tracks.", "")];
        [item setPaletteLabel:[item label]];
        [item setTarget:self];
        [item setAction:@selector(showLovedBanned:)];
        // [item setImage:[NSImage imageNamed:@""]];
        [item setTag:0];
        [toolbarItems setObject:item forKey:@"showloveban"];
        [item release];
        
        [toolbarItems setObject:[NSNull null] forKey:NSToolbarSeparatorItemIdentifier];
        [toolbarItems setObject:[NSNull null] forKey:NSToolbarFlexibleSpaceItemIdentifier];
        [toolbarItems setObject:[NSNull null] forKey:NSToolbarSpaceItemIdentifier];
        
        [[self window] setToolbar:tb];
        [tb release];
        
        rpcreqs = [[NSMutableArray alloc] init];
    } // [ASXMLRPC isAvailable])
}

// ================= Toolbar support ================= //

- (void)clearUserFeedbackForItem:(NSString*)key
{
    NSToolbarItem *item = [toolbarItems objectForKey:key];
    int flags = [item tag] & ~kTBItemDisabledForFeedback;
    [item setTag:flags];
    [[[self window] toolbar] validateVisibleItems];
}

- (void)clearUserFeedbackDelayed:(NSTimer*)timer
{
    [self clearUserFeedbackForItem:[timer userInfo]];
}

- (void)setUserFeedbackForItem:(NSString*)key
{
    NSToolbarItem *item = [toolbarItems objectForKey:key];
    int flags = [item tag] | kTBItemDisabledForFeedback;
    [item setTag:flags];
    [[[self window] toolbar] validateVisibleItems];
    [NSTimer scheduledTimerWithTimeInterval:0.65 target:self selector:@selector(clearUserFeedbackDelayed:) userInfo:key repeats:NO];
}

- (void)loveBan:(NSString*)method track:(NSDictionary*)track
{
    NSString *artist = [track objectForKey:@"Artist"];
    NSString *title = [track objectForKey:@"Track"];
    if (!artist || !title)
        return;
    
    ASXMLRPC *req = [[ASXMLRPC alloc] init];
    [req setMethod:method];
    NSMutableArray *p = [req standardParams];
    [p addObject:artist];
    [p addObject:title];
    [req setParameters:p];
    [req setDelegate:self];
    [req setRepresentedObject:track];
    [req sendRequest];
    [rpcreqs addObject:req];
}

- (IBAction)loveTrack:(id)sender
{
    @try {
        NSArray *tracks = [topTracksController selectedObjects];
        NSEnumerator *en = [tracks objectEnumerator];
        NSDictionary *track;
        while ((track = [en nextObject])) {
            if (![track isKindOfClass:[NSDictionary class]])
                continue;
            [self loveBan:@"loveTrack" track:track];
        }
        
        [self setUserFeedbackForItem:@"love"];
    } @catch (id e) {}
}

- (IBAction)banTrack:(id)sender
{
    @try {
        NSArray *tracks = [topTracksController selectedObjects];
        NSEnumerator *en = [tracks objectEnumerator];
        NSDictionary *track;
        while ((track = [en nextObject])) {
            if (![track isKindOfClass:[NSDictionary class]])
                continue;
            [self loveBan:@"banTrack" track:track];
        }
        
        [self setUserFeedbackForItem:@"ban"];
    } @catch (id e) {}
}

- (void)recommendSheetDidEnd:(NSNotification*)note
{
    ISRecommendController *rc = [note object];
    NSDictionary *song = [rc representedObject];
    if ([rc send] && song && [song isKindOfClass:[NSDictionary class]]) {
        NSString *artist = [song objectForKey:@"Artist"];
        if (!artist)
            goto exit;
        
        ASXMLRPC *req = [[ASXMLRPC alloc] init];
        NSMutableArray *p = [req standardParams];
        switch ([rc type]) {
            case rt_track: {
                NSString *title = [song objectForKey:@"Track"];
                if (!title) {
                    [req release];
                    goto exit;
                }
                [req setMethod:@"recommendTrack"];
                [p addObject:artist];
                [p addObject:title];
            } break;
            
            case rt_artist:
                [req setMethod:@"recommendArtist"];
                [p addObject:artist];
            break;
            
            case rt_album:
            default:
                [req release];
                goto exit;
            break;
        }
        [p addObject:[rc who]];
        [p addObject:[rc message]];
        
        [req setParameters:p];
        [req setDelegate:self];
        [req setRepresentedObject:song];
        [req sendRequest];
        [rpcreqs addObject:req];
    }
    
exit:
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISRecommendDidEnd object:rc];
    [rc release];
}

- (IBAction)recommend:(id)sender
{
    NSTabViewItem *activeTab;
    id data, obj;
    @try {
    activeTab = [tabView selectedTabViewItem];
    data = [[activeTab identifier] isEqualToString:@"Tracks"] ? topTracksController : topArtistsController;
    obj = [[data selectedObjects] objectAtIndex:0];
    } @catch (id e) {
        return;
    }
    if (!obj || ![obj isKindOfClass:[NSDictionary class]])
        return;
    
    ISRecommendController *rc = [[ISRecommendController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recommendSheetDidEnd:)
        name:ISRecommendDidEnd object:rc];
    [rc setAlbumEnabled:NO];
    if (data == topArtistsController) {
        [rc setTrackEnabled:NO];
        [rc setType:rt_artist];
    }
    [rc setRepresentedObject:obj];
    [rc showWindow:[self window]];
}

- (void)tagSheetDidEnd:(NSNotification*)note
{
    ISTagController *tc = [note object];
    NSArray *tracks = [tc representedObject];
    NSArray *tags = [tc tags];
    if (tags && [tc send] && tracks && [tracks isKindOfClass:[NSArray class]]) {
        NSEnumerator *en = [tracks objectEnumerator];
        NSDictionary *song;
        while ((song = [en nextObject])) {
            if (![song isKindOfClass:[NSDictionary class]])
                continue;
            NSString *artist = [song objectForKey:@"Artist"];
            if (!artist)
                continue;
            
            ASXMLRPC *req = [[ASXMLRPC alloc] init];
            NSMutableArray *p = [req standardParams];
            NSString *mode = [tc editMode] == tt_overwrite ? @"set" : @"append";
            switch ([tc type]) {
                case tt_track: {
                    NSString *title = [song objectForKey:@"Track"];
                    if (!title) {
                        [req release];
                        continue;
                    }
                    [req setMethod:@"tagTrack"];
                    [p addObject:artist];
                    [p addObject:title];
                } break;
                
                case tt_artist:
                    [req setMethod:@"tagArtist"];
                    [p addObject:artist];
                break;
                
                case tt_album:                
                default:
                    [req release];
                    continue;
                break;
            }
            [p addObject:tags];
            [p addObject:mode];
            
            [req setParameters:p];
            [req setDelegate:self];
            [req setRepresentedObject:song];
            [req sendRequest];
            [rpcreqs addObject:req];
        } // while(song)
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISTagDidEnd object:tc];
    [tc release];
}

- (IBAction)tag:(id)sender
{
    NSTabViewItem *activeTab;
    id data, obj;
    @try {
    activeTab = [tabView selectedTabViewItem];
    data = [[activeTab identifier] isEqualToString:@"Tracks"] ? topTracksController : topArtistsController;
    obj = [data selectedObjects];
    } @catch (id e) {
        return;
    }
    
    ISTagController *tc = [[ISTagController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tagSheetDidEnd:)
        name:ISTagDidEnd object:tc];
    [tc setAlbumEnabled:NO];
    if (data == topArtistsController) {
        [tc setTrackEnabled:NO];
        [tc setType:tt_artist];
    }
    [tc setRepresentedObject:obj];
    [tc showWindow:[self window]];
}

- (IBAction)showLovedBanned:(id)sender
{
    [[ISLoveBanListController sharedController] showWindow:[self window]];
}

// ASXMLRPC
- (void)responseReceivedForRequest:(ASXMLRPC*)request
{
    if (NSOrderedSame != [[request response] compare:@"OK" options:NSCaseInsensitiveSearch]) {
        NSError *err = [NSError errorWithDomain:@"iScrobbler" code:-1 userInfo:
            [NSDictionary dictionaryWithObject:[request response] forKey:@"Response"]];
        [self error:err receivedForRequest:request];
        return;
    }
    
    NSString *method = [request method];
    NSString *tag = nil;
    if ([method isEqualToString:@"loveTrack"]) {
        tag = @"loved";
    } else if ([method isEqualToString:@"banTrack"]) {
        tag = @"banned";
    }
    
    id obj = [request representedObject];
    ScrobLog(SCROB_LOG_TRACE, @"RPC request '%@' successful (%@)",
        method, obj);
    
    NSString *artist, *title;
    if (tag && [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTagLovedBanned"]
        && [obj isKindOfClass:[NSDictionary class]]
        && (artist = [obj objectForKey:@"Artist"])
        && (title = [obj objectForKey:@"Track"])) {
        ASXMLRPC *tagReq = [[ASXMLRPC alloc] init];
        NSMutableArray *p = [tagReq standardParams];
        [tagReq setMethod:@"tagTrack"];
        [p addObject:artist];
        [p addObject:title];
        [p addObject:[NSArray arrayWithObject:tag]];
        [p addObject:@"append"];
        
        [tagReq setParameters:p];
        [tagReq setDelegate:self];
        [tagReq setRepresentedObject:obj];
        [tagReq performSelector:@selector(sendRequest) withObject:nil afterDelay:0.0];
        
        [request retain];
        [rpcreqs removeObject:request];
        [request autorelease];
        
        [rpcreqs addObject:tagReq];
    } else {
        [request retain];
        [rpcreqs removeObject:request];
        [request autorelease];
        
        [[[self window] toolbar] validateVisibleItems];
    }
}

- (void)error:(NSError*)error receivedForRequest:(ASXMLRPC*)request
{
    ScrobLog(SCROB_LOG_ERR, @"RPC request '%@' for '%@' returned error: %@",
        [request method], [request representedObject], error);
    
    [request retain];
    [rpcreqs removeObject:request];
    [request autorelease];
    [[[self window] toolbar] validateVisibleItems];
}

// NSToolbar
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier
    willBeInsertedIntoToolbar:(BOOL)flag 
{
    return [toolbarItems objectForKey:itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return [toolbarItems allKeys];
}

// Called once during toolbar init
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    return [NSArray arrayWithObjects:
        NSToolbarFlexibleSpaceItemIdentifier,
        @"showloveban",
        NSToolbarSeparatorItemIdentifier,
        @"recommend",
        @"tag",
        NSToolbarSeparatorItemIdentifier,
        @"ban",
        @"love",
        //NSToolbarSpaceItemIdentifier,
        nil];
}

- (BOOL)validateToolbarItem:(NSToolbarItem*)item
{
    NSTabViewItem *activeTab;
    id data;
    
    @try {
    activeTab = [tabView selectedTabViewItem];
    data = [[activeTab identifier] isEqualToString:@"Tracks"] ? topTracksController : topArtistsController;
    } @catch (id e) {
        return (NO);
    }
    int flags = [item tag];
    if ((flags & kTBItemDisabledForFeedback))
        return (NO);
    
    unsigned ct = [[data selectedObjects] count];
    BOOL valid = YES;
    if ((flags & kTBItemRequiresSelection))
        valid = (ct > 0);
    if (valid && (flags & kTBItemRequiresTrackSelection))
        valid = (data == topTracksController);
    if (valid && (flags & kTBItemNoMultipleSelection))
        valid = (1 == ct);
    
    //ScrobTrace(@"flags = %x, ct = %u, valid = %d", flags, ct, valid);
    return (valid);
}

#if 0
- (void)toolbarWillAddItem:(NSNotification *) notification
{
}

- (void)toolbarDidRemoveItem:(NSNotification *)notification
{
}
#endif


@end

#define PROFILE_DATE_FORMAT @"%Y-%m-%d %I:%M:%S %p"
@implementation TopListsController (ISProfileReportAdditions)

- (void)writePersistentStore 
{
    NSDictionary *d = nil;
    @try {
    // An NSSet is not a valid plist object, so create an archive
    NSMutableData *rdata = [NSMutableData data];
    NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:rdata] autorelease];
    [archiver encodeObject:topRatings forKey:@"object"];
    [archiver finishEncoding];
    
    d = [[NSDictionary alloc] initWithObjectsAndKeys:
        [topArtistsController content], @"artists",
        [topTracksController content], @"tracks",
        topAlbums, @"albums",
        rdata, @"ratings",
        startDate, @"since",
        [NSNumber numberWithUnsignedInt:[[ProtocolManager sharedInstance] successfulSubmissionsCount]],
            @"subcount",
        nil];

    NSData *data = [NSPropertyListSerialization dataFromPropertyList:d
        format:NSPropertyListBinaryFormat_v1_0
        errorDescription:nil];
    [data writeToFile:TOP_LISTS_PERSISTENT_STORE atomically:YES];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while saving persistent profile: %@.", e);
    }
    
    [d release];
}

- (void)restorePersistentStore
{
    NSData *d = nil;
    @try {
    d = [[NSData alloc] initWithContentsOfFile:TOP_LISTS_PERSISTENT_STORE];
    if (d) {
        NSPropertyListFormat format;
        NSDictionary *store;
        store = [NSPropertyListSerialization propertyListFromData:d
            mutabilityOption:NSPropertyListMutableContainersAndLeaves
            format:&format
            errorDescription:nil];
        if (NO == [store isKindOfClass:[NSDictionary class]]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                reason:@"Top Lists store is not of the correct object type." userInfo:nil];
        }
        
        id obj;
        if ((obj = [store objectForKey:@"artists"]))
            [topArtistsController setContent:obj];
        if ((obj = [store objectForKey:@"tracks"]))
            [topTracksController setContent:obj];
        if ((obj = [store objectForKey:@"since"]))
            [self setValue:obj forKey:@"startDate"];
        if ((obj = [store objectForKey:@"albums"])) {
            [topAlbums release];
            topAlbums = [obj retain];
        }
        if ((obj = [store objectForKey:@"ratings"])) {
            NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingWithData:obj] autorelease];
            [topRatings release];
            topRatings = [[unarchiver decodeObjectForKey:@"object"] retain];
            
        }
        if ((obj = [store objectForKey:@"subcount"])) {
        }
    }
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while restoring persistent profile: %@.", e);
    }
    [d release];
}

- (IBAction)createProfileReport:(id)sender
{
    // Create html
    NSString *cssPath = [@"~/Documents/iScrobblerProfile.css" stringByExpandingTildeInPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cssPath])
        cssPath = [[NSBundle mainBundle] pathForResource:@"ProfileReport" ofType:@"css"];
    
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%@'s iScrobbler Profile (%@)", ""),
        NSFullUserName(), [[NSDate date] descriptionWithCalendarFormat:PROFILE_DATE_FORMAT timeZone:nil locale:nil]];
    
    NSData *data = nil;
    @try {
        data = [self generateHTMLReportWithCSSURL:[NSURL fileURLWithPath:cssPath]
            withTitle:title];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while generating profile report: %@.", e);
        return;
    }
    
    ISProfileDocumentController *report =
        [[ISProfileDocumentController alloc] initWithWindowNibName:@"ISProfileReport"];
    @try {
        [report showWindowWithHTMLData:data withWindowTitle:title];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while creating profile report: %@.", e);
        [report release];
        return;
    }
}

- (void)resetAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    if (NSOKButton != returnCode)
        return;
   
   [self hideDetails:nil];
    
    @try {
    if ([[topArtistsController content] count])
        [topArtistsController removeObjects:[topArtistsController content]];
    if ([[topTracksController content] count])
        [topTracksController removeObjects:[topTracksController content]];
    
    [topAlbums removeAllObjects];
    [topRatings removeAllObjects];
    [self setValue:[NSDate date] forKey:@"startDate"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:RESET_PROFILE object:nil];
    
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while resetting profile: %@.", e);
        return;
    }
    
    (void)[[NSFileManager defaultManager] removeFileAtPath:TOP_LISTS_PERSISTENT_STORE handler:nil];
}

- (IBAction)resetProfile:(id)sender
{
     NSAlert *alert = [NSAlert
        alertWithMessageText:NSLocalizedString(@"Reset Profile?", "")
        defaultButton:NSLocalizedString(@"Reset", "")
        alternateButton:NSLocalizedString(@"Cancel", "")
        otherButton:nil
        informativeTextWithFormat:
            NSLocalizedString(@"Resetting your profile will clear all local Top List data (your online Last.FM profile is not touched).", "")];
    [alert setAlertStyle:NSInformationalAlertStyle];
    [alert beginSheetModalForWindow:[self window] modalDelegate:self
        didEndSelector:@selector(resetAlertDidEnd:returnCode:contextInfo:) contextInfo:nil];
    return;
}

#define HEAD @"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n" \
@"\t\t\"http://www.w3.org/TR/2000/REC-xhtml1-20000126/DTD/xhtml1-strict.dtd\">" \
@"<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">" \
@"<head>\n<meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\" />\n"
#define STYLE @"<link rel=\"stylesheet\" type=\"text/css\" href=\"%@\" title=\"iScrobbler stylesheet\" />\n"
#define HEAD_CLOSE @"</head>\n"
#define BODY @"<body><div class=\"content\">\n"
#define DOCCLOSE @"</div></body></html>"
#define TBLCLOSE @"</table>\n"
#define TBLTITLE(t) [NSString stringWithFormat:@"<h4>%@</h4>\n", (t)]
#define TR @"<tr>\n"
#define TRALT @"<tr class=\"alt\">"
#define TRCLOSE @"</tr>\n"
#define TD @"<td>"
#define TDTITLE @"<td class=\"title\">"
#define TDGRAPH @"<td class=\"smallgraph\">"
#define TDPOS @"<td class=\"position\">"
#define TDCLOSE @"</td>\n"

static inline NSString* TH(int span, NSString *title)
{
    return ( [NSString stringWithFormat:@"<th colspan=\"%d\" align=\"left\">%@</th>\n", span, title] );
}

static inline void HAdd(NSMutableData *d, NSString *str)
{
    [d appendData:[str dataUsingEncoding:NSUTF8StringEncoding]];
}

static inline NSString* TDEntry(NSString *type, id obj)
{
    return ( [NSString stringWithFormat:@"%@%@%@", type, obj, TDCLOSE] );
}

static inline NSString* DIVEntry(NSString *type, float width, NSString *title, id obj)
{
    return ( [NSString stringWithFormat:@"<div class=\"%@\" %@style=\"width:%u%%;\">%@</div>",
       type,  (title ? [NSString stringWithFormat:@"title=\"%@\" ", title] : @""),
       (unsigned)width, obj] );
}

- (NSData*)generateHTMLReportWithCSSURL:(NSURL*)cssURL withTitle:(NSString*)profileTitle
{
    NSMutableData *d = [NSMutableData data];
    
    HAdd(d, HEAD);
    HAdd(d, [NSString stringWithFormat:@"<title>%@</title>\n", profileTitle]);
    HAdd(d, [NSString stringWithFormat:STYLE, [NSString stringWithFormat:@"file://%@", [cssURL path]]]);
    HAdd(d, HEAD_CLOSE BODY);
    
    NSArray *artists = [[topArtistsController valueForKey:@"arrangedObjects"]
        sortedArrayUsingSelector:@selector(sortByPlayCount:)];
    NSArray *tracks = [[topTracksController valueForKey:@"arrangedObjects"]
        sortedArrayUsingSelector:@selector(sortByPlayCount:)];
    
    NSNumber *totalTime = [artists valueForKeyPath:@"Total Duration.@sum.unsignedIntValue"];
    NSNumber *totalPlays = [artists valueForKeyPath:@"Play Count.@sum.unsignedIntValue"];
    
    unsigned int days, hours, minutes, seconds;
    ISDurationsFromTime([totalTime unsignedIntValue], &days, &hours, &minutes, &seconds);
    NSString *time = [NSString stringWithFormat:@"%u %@, %u:%02u:%02u",
        days, (1 == days ? NSLocalizedString(@"day","") : NSLocalizedString(@"days", "")),
        hours, minutes, seconds];
    
    NSTimeInterval elapsedSeconds =  [[NSDate date] timeIntervalSince1970] - [startDate timeIntervalSince1970];
    ISDurationsFromTime(elapsedSeconds, &days, &hours, &minutes, &seconds);
    NSString *elapsedTime = [NSString stringWithFormat:@"%u %@, %u:%02u:%02u",
        days, (1 == days ? NSLocalizedString(@"day","") : NSLocalizedString(@"days", "")),
        hours, minutes, seconds];
    
    HAdd(d, @"<table style=\"width:100%; border:0; margin:0; padding:0;\">\n<tr><td valign=\"top\">\n");
    
    HAdd(d, @"<div class=\"modbox\" style=\"vertical-align:top;\">\n" @"<table class=\"topn\">\n" TR);
    HAdd(d, TH(2, TBLTITLE(NSLocalizedString(@"Totals", ""))));
    HAdd(d, TRCLOSE TR);
    HAdd(d, TDEntry(@"<td class=\"att\">", NSLocalizedString(@"Tracks Played:", "")));
    HAdd(d, TDEntry(TD, [NSString stringWithFormat:@"%@ (%@ %@)", totalPlays,
        NSLocalizedString(@"since", ""),
        [startDate descriptionWithCalendarFormat:@"%B %e, %Y %I:%M %p" timeZone:nil locale:nil]]));
    HAdd(d, TRCLOSE TRALT);
    HAdd(d, TDEntry(@"<td class=\"att\">", NSLocalizedString(@"Time Played:", "")));
    HAdd(d, TDEntry(TD, [NSString stringWithFormat:@"%@ (%0.2f%% %@ %@ %@)", time,
        ([totalTime floatValue] / elapsedSeconds) * 100.0,
        NSLocalizedString(@"of", ""), elapsedTime, NSLocalizedString(@"elapsed", "")]));
    HAdd(d, TRCLOSE TBLCLOSE @"</div>");
    
    HAdd(d, TDCLOSE TRCLOSE TBLCLOSE);
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"topartists\">\n" TR);
    HAdd(d, TH(4, TBLTITLE(NSLocalizedString(@"Top Artists", ""))));
    HAdd(d, TRCLOSE);
    
    NSEnumerator *en = [artists reverseObjectEnumerator]; // high->low
    NSDictionary *entry;
    NSString *artist, *track, *tmp;
    NSNumber *playCount;
    unsigned position = 1; // ranking
    float width = 100.0 /* bar width */, percentage,
    basePlayCount = [[artists valueForKeyPath:@"Play Count.@max.unsignedIntValue"] floatValue],
    basePlayTime = [[artists valueForKeyPath:@"Total Duration.@max.unsignedIntValue"] floatValue];
    while ((entry = [en nextObject])) {
        artist = [[entry objectForKey:@"Artist"] stringByConvertingCharactersToHTMLEntities];
        playCount = [entry objectForKey:@"Play Count"];
        time = [entry objectForKey:@"Play Time"];
        
        HAdd(d, (position & 0x0000001) ? TR : TRALT);
        
        HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
        HAdd(d, TDEntry(TDTITLE, artist));
        // Total Plays bar
        width = rintf(([playCount floatValue] / basePlayCount) * 100.0);
        percentage = ([playCount floatValue] / [totalPlays floatValue]) * 100.0;
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, playCount)));
        // Total time bar
        width = rintf(([[entry objectForKey:@"Total Duration"] floatValue] / basePlayTime) * 100.0);
        percentage = ([[entry objectForKey:@"Total Duration"] floatValue] / [totalTime floatValue]) * 100.0;
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, time)));
        
        HAdd(d, TRCLOSE);
        ++position;
    }
    
    HAdd(d, TBLCLOSE @"</div>");
    [pool release];
    
    pool = [[NSAutoreleasePool alloc] init];
    HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"toptracks\">\n" TR);
    HAdd(d, TH(4, TBLTITLE(NSLocalizedString(@"Top Tracks", ""))));
    HAdd(d, TRCLOSE);
    
    en = [tracks reverseObjectEnumerator]; // high->low
    position = 1;
    basePlayCount = [[tracks valueForKeyPath:@"Play Count.@max.unsignedIntValue"] floatValue];
    while ((entry = [en nextObject])) {
        artist = [[entry objectForKey:@"Artist"] stringByConvertingCharactersToHTMLEntities];
        playCount = [entry objectForKey:@"Play Count"];
        time = [[entry objectForKey:@"Last Played"]
            descriptionWithCalendarFormat:PROFILE_DATE_FORMAT timeZone:nil locale:nil];
        track = [[entry objectForKey:@"Track"] stringByConvertingCharactersToHTMLEntities];
        
        HAdd(d, (position & 0x0000001) ? TR : TRALT);
        
        HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
        tmp = [NSString stringWithFormat:@"%@ - %@", track, artist];
        HAdd(d, TDEntry(TDTITLE, tmp));
        HAdd(d, TDEntry(TDGRAPH, time)); // Last play time
        // Total Plays bar
        width = rintf(([playCount floatValue] / basePlayCount) * 100.0);
        percentage = ([playCount floatValue] / [totalPlays floatValue]) * 100.0;
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, playCount)));
        
        HAdd(d, TRCLOSE);
        ++position;
    }
    
    HAdd(d, TBLCLOSE @"</div>");
    [pool release];

    NSArray *keys;
    if (topAlbums) {
        pool = [[NSAutoreleasePool alloc] init];
        [topAlbums mergeValuesUsingCaseInsensitiveCompare];
        
        HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"topalbums\">\n" TR);
        HAdd(d, TH(4, TBLTITLE(NSLocalizedString(@"Top Albums", ""))));
        HAdd(d, TRCLOSE);
        
        keys = [topAlbums keysSortedByValueUsingSelector:@selector(sortByDuration:)];
        // The keys are ordered from smallest to largest, therefore we want the last one
        tmp = [keys objectAtIndex:[keys count]-1];
        playCount = [[topAlbums objectForKey:tmp] objectForKey:@"Total Duration"];
        basePlayTime = [playCount floatValue];
        
        keys = [topAlbums keysSortedByValueUsingSelector:@selector(sortByPlayCount:)];
        tmp = [keys objectAtIndex:[keys count]-1];
        playCount = [[topAlbums objectForKey:tmp] objectForKey:@"Play Count"];
        basePlayCount = [playCount floatValue];
        en = [keys reverseObjectEnumerator]; // Largest to smallest
        position = 1;
        while ((tmp = [en nextObject])) { // tmp is our key into the topAlbums dict
            NSArray *items = [tmp componentsSeparatedByString:TOP_ALBUMS_KEY_TOKEN];
            if (items && 2 == [items count]) {
                artist = [[items objectAtIndex:0] stringByConvertingCharactersToHTMLEntities];
                NSString *album = [[items objectAtIndex:1] stringByConvertingCharactersToHTMLEntities];
                entry = [topAlbums objectForKey:tmp];
                
                HAdd(d, (position & 0x0000001) ? TR : TRALT);
                
                HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
                tmp = [NSString stringWithFormat:@"%@ - %@", album, artist];
                HAdd(d, TDEntry(TDTITLE, tmp));
                // Total Plays bar
                playCount = [entry objectForKey:@"Play Count"];
                width = rintf(([playCount floatValue] / basePlayCount) * 100.0);
                percentage = ([playCount floatValue] / [totalPlays floatValue]) * 100.0;
                tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
                HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, playCount)));
                // Total time bar
                playCount = [entry objectForKey:@"Total Duration"];
                width = rintf(([playCount floatValue] / basePlayTime) * 100.0);
                percentage = ([playCount floatValue] / [totalTime floatValue]) * 100.0;
                tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
                ISDurationsFromTime([playCount unsignedIntValue], &days, &hours, &minutes, &seconds);
                time = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
                HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, time)));
                
                HAdd(d, TRCLOSE);
                ++position;
            }
        }
        
        HAdd(d, TBLCLOSE @"</div>");
        [pool release];
    }
    
    if (topRatings) {
        pool = [[NSAutoreleasePool alloc] init];
        
        HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"topratings\">\n" TR);
        HAdd(d, TH(2, TBLTITLE(NSLocalizedString(@"Top Ratings", ""))));
        HAdd(d, TRCLOSE);
        
        NSNumber *rating;
        // Determine max count
        unsigned maxCount = 0;
        en = [topRatings objectEnumerator];
        while ((rating = [en nextObject])) {
            if ([topRatings countForObject:rating] > maxCount)
                maxCount = [topRatings countForObject:rating];
        }
        basePlayCount = (float)maxCount;
        keys = [topRatings allObjects];
        position = 1;
        en = [[keys sortedArrayUsingSelector:@selector(compare:)] reverseObjectEnumerator];
        SongData *dummy = [[SongData alloc] init];
        while ((rating = [en nextObject])) {
            HAdd(d, (position & 0x0000001) ? TR : TRALT);
            
            //HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
            // Get the rating string to display
            [dummy setRating:rating];
            tmp = [dummy fullStarRating];
            
            HAdd(d, TDEntry(TDTITLE, tmp));
            // Total Plays bar
            float ratingCount = (float)[topRatings countForObject:rating];
            width = rintf((ratingCount / basePlayCount) * 100.0);
            percentage = (ratingCount / [totalPlays floatValue]) * 100.0;
            tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
            playCount = [NSNumber numberWithFloat:ratingCount];
            HAdd(d, TDEntry(@"<td class=\"graph\">", DIVEntry(@"bar", width, tmp, playCount)));
            
            HAdd(d, TRCLOSE);
            ++position;
        }
        [dummy release];
        
        HAdd(d, TBLCLOSE @"</div>");
        [pool release];
    }
    
    HAdd(d, DOCCLOSE);
    
    return (d);
}

@end

@implementation NSString (ISHTMLConversion)

- (NSString *)stringByConvertingCharactersToHTMLEntities
{
    NSMutableString *s = [self mutableCopy];
    NSRange r;
    // This has to be the most inefficient way to do this, but it works
    
    // Replace all ampersands (must be first!)
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:r];
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:r];
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:r];
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:r];
#ifdef notyet
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@"\xa0" withString:@"&nbsp;" options:0 range:r];
#endif
    return ([s autorelease]);
}

@end

@implementation NSMutableDictionary (ISTopListsAdditions)

- (void)mergeValuesUsingCaseInsensitiveCompare
{
    NSMutableArray *keys = [[self allKeys] mutableCopy];
    unsigned i, j, count, value;
    
    count = [keys count];
    for (i=0; i < count; ++i) {
        NSString *key = [keys objectAtIndex:i], *key2 = nil;
        NSMutableDictionary *entry, *entry2;
        for (j = i+1; [key length] > 0 && j < count; ++j) {
            key2 = [keys objectAtIndex:j];
            if (NSOrderedSame == [key caseInsensitiveCompare:key2]) {
                (void)[key2 retain];
                [keys replaceObjectAtIndex:j withObject:@""];
                
                entry = [self objectForKey:key];
                entry2 = [self objectForKey:key2];
                // Merge the counts with key 1
                value = [[entry objectForKey:@"Play Count"] unsignedIntValue] +
                    [[entry2 objectForKey:@"Play Count"] unsignedIntValue];
                [entry setObject:[NSNumber numberWithUnsignedInt:value] forKey:@"Play Count"];
                value = [[entry objectForKey:@"Total Duration"] unsignedIntValue] +
                    [[entry2 objectForKey:@"Total Duration"] unsignedIntValue];
                [entry setObject:[NSNumber numberWithUnsignedInt:value] forKey:@"Total Duration"];
                // Remove the second key
                [self removeObjectForKey:key2];
                [key2 release];
                // Can't break since there may be another alt. spelling
            }
        }
    }
    [keys release];
}

- (NSComparisonResult)sortByPlayCount:(NSDictionary*)entry
{
    return ( [(NSNumber*)[self objectForKey:@"Play Count"] compare:(NSNumber*)[entry objectForKey:@"Play Count"]] );
}

- (NSComparisonResult)sortByDuration:(NSDictionary*)entry
{
    return ( [(NSNumber*)[self objectForKey:@"Total Duration"] compare:(NSNumber*)[entry objectForKey:@"Total Duration"]] );
}

@end
