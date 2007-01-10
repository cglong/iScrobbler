//
//  StatisticsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/18/04.
//  Copyright 2004-2007 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "StatisticsController.h"
#import "ProtocolManager.h"
#import "QueueManager.h"
#import "iScrobblerController.h"
#import "ISArtistDetailsController.h"
#import "ASXMLRPC.h"
#import "ISRecommendController.h"
#import "ISTagController.h"

static StatisticsController *g_sub = nil;
static SongData *g_nowPlaying = nil;
static NSTimer *g_cycleTimer = nil, *g_SubUpdateTimer = nil;
static NSDate *g_subDate = nil;
static enum {title, album, artist, subdate} g_cycleState = title;

enum {
    kTBItemRequiresSong = 0x00000001,
    kTBItemSongNotLovedBanned = 0x00000002,
};

@implementation StatisticsController

+ (StatisticsController*)sharedInstance
{
    if (g_sub)
        return (g_sub);
    
    return ((g_sub = [[StatisticsController alloc] initWithWindowNibName:@"StatisticsController"]));
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if (g_sub == nil) {
            return ([super allocWithZone:zone]);
        }
    }

    return (g_sub);
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

- (void)handshakeCompleteHandler:(NSNotification*)note
{
    [submissionProgress stopAnimation:nil];
    
    ProtocolManager *pm = [ProtocolManager sharedInstance];
    id selection = [values selection];

    if ([[pm lastHandshakeResult] isEqualToString:HS_RESULT_OK])
        [selection setValue:[NSColor blackColor] forKey:@"Server Response Color"];
    else
        [selection setValue:[NSColor redColor] forKey:@"Server Response Color"];
    
    [selection setValue:[pm lastHandshakeMessage] forKey:@"Server Response"];
}

- (void)submitCompleteHandler:(NSNotification*)note
{
    [submissionProgress stopAnimation:nil];
    
    if (g_SubUpdateTimer) {
        [g_SubUpdateTimer invalidate];
        g_SubUpdateTimer = nil;
    }
    if (subdate == g_cycleState)
        [g_cycleTimer fire];
    
    ProtocolManager *pm = [ProtocolManager sharedInstance];
    QueueManager *qm = [QueueManager sharedInstance];
    id selection = [values selection];
    
    if ([[pm lastSubmissionResult] isEqualToString:HS_RESULT_OK]) {
        [selection setValue:[NSColor blackColor] forKey:@"Server Response Color"];
    } else
        [selection setValue:[NSColor redColor] forKey:@"Server Response Color"];
    
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm totalSubmissionsCount]]
        forKey:@"Tracks Submitted"];
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm count]]
        forKey:@"Tracks Queued"];
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm submissionAttemptsCount]]
        forKey:@"Submission Attempts"];
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm successfulSubmissionsCount]]
        forKey:@"Successful Submissions"];
    unsigned int time = [[qm totalSubmissionsPlayTimeInSeconds] unsignedIntValue];
    unsigned int days, hours, minutes, seconds;
    ISDurationsFromTime(time, &days, &hours, &minutes, &seconds);
    NSString *timeString = [NSString stringWithFormat:@"%u %@, %u:%02u:%02u",
        days, (1 == days ? NSLocalizedString(@"day", "") : NSLocalizedString(@"days", "")),
        hours, minutes, seconds];
    [selection setValue:timeString forKey:@"Tracks Submitted Play Time"];
    [selection setValue:[pm lastSubmissionMessage] forKey:@"Server Response"];
    [selection setValue:[[pm lastSongSubmitted] brief] forKey:@"Last Track Submission"];
    
}

- (void)handshakeStartHandler:(NSNotification*)note
{
    [submissionProgress startAnimation:nil];
}

- (void)submitStartHandler:(NSNotification*)note
{
    [submissionProgress startAnimation:nil];
}

- (void)songQueuedHandler:(NSNotification*)note
{
    QueueManager *qm = [QueueManager sharedInstance];
    id selection = [values selection];
    
    if (g_nowPlaying && [g_nowPlaying isEqualToSong:[[note userInfo] objectForKey:QM_NOTIFICATION_USERINFO_KEY_SONG]])
        [checkImage setHidden:NO];
    
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm count]]
        forKey:@"Tracks Queued"];
}

static NSImage *prevIcon = nil;
- (void)iPodSyncBeginHandler:(NSNotification*)note
{
    NSImage *icon = [[note userInfo] objectForKey:IPOD_SYNC_KEY_ICON];
    if (icon) {
        prevIcon = [[artworkImage image] retain];
        [artworkImage setImage:icon];
    }
}

- (void)iPodSyncEndHandler:(NSNotification*)note
{
    NSImage *icon = [artworkImage image];
    ScrobLog(SCROB_LOG_TRACE, @"icon name: %@, prevIcon: %p", [icon name], prevIcon);
    if ([[icon name] isEqualToString:IPOD_ICON_NAME] && prevIcon) {
        // Restore the saved icon
        [artworkImage setImage:prevIcon];
    }
    [prevIcon release];
    prevIcon = nil;
}

- (void)updateSubTime:(NSTimer*)timer
{
    NSTimeInterval i = [g_subDate timeIntervalSince1970] - [[NSDate date] timeIntervalSince1970];
    NSString *msg = [NSString stringWithFormat:@"%@ %u:%02u",
        NSLocalizedString(@"Submitting in", ""), ((unsigned)i / 60), ((unsigned)i % 60)];
    [nowPlayingText setStringValue:msg];
}

- (void)cycleNowPlaying:(NSTimer *)timer
{
    NSString *msg = nil, *rating;
    NSDate *now = [NSDate date];
    
    if (g_subDate && [g_subDate isLessThanOrEqualTo:now]) {
        [g_subDate release];
        g_subDate = nil;
        if (subdate == g_cycleState)
            g_cycleState = title;
    }
    
    if (g_SubUpdateTimer) {
        [g_SubUpdateTimer invalidate];
        g_SubUpdateTimer = nil;
    }
    
    switch (g_cycleState) {
        case title:
            rating = [g_nowPlaying starRating];
            if ([rating length] > 0)
                msg = [[g_nowPlaying title] stringByAppendingFormat:@" (%@)", rating];
            else
                msg = [g_nowPlaying title];
            g_cycleState = album;
            break;
        case album:
            msg = [g_nowPlaying album];
            g_cycleState = artist;
            break;
        case artist:
            msg = [g_nowPlaying artist];
            g_cycleState = g_subDate ? subdate : title;
            break;
        case subdate: {
            [self updateSubTime:nil];
            g_SubUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                selector:@selector(updateSubTime:) userInfo:nil repeats:YES];
            g_cycleState = title;
            return;
        };
    }
    
    // It would be cool if we could do some text alpha fading when the msg changes,
    // but that's too much work...
    [nowPlayingText setStringValue:msg];
}

- (void)nowPlaying:(NSNotification*)note
{
    SongData *song = [note object];
    
    if (!song || ![g_nowPlaying isEqualToSong:song]) {
        BOOL queued = (song && [song hasQueued]);
        [checkImage setHidden:(NO == queued)];
        [g_nowPlaying release];
        g_nowPlaying = [song retain];
        g_cycleState = title;
        
        [g_SubUpdateTimer invalidate];
        g_SubUpdateTimer = nil;
        [g_cycleTimer invalidate];
        g_cycleTimer = nil;
        [g_subDate release];
        g_subDate = [[[note userInfo] objectForKey:@"sub date"] retain]; 
        if (g_nowPlaying) {
            // Create the timer
            g_cycleTimer = [NSTimer scheduledTimerWithTimeInterval:8.0 target:self
                selector:@selector(cycleNowPlaying:) userInfo:nil repeats:YES];
            [g_cycleTimer fire];
        } else {
            [nowPlayingText setStringValue:
                // 0x2026 == Unicode elipses
                [NSLocalizedString(@"Waiting for track", "") stringByAppendingFormat:@"%C", 0x2026]];
        }
        
        // Set the ablum art image
        NSImage *art = [song artwork];
        if (art && g_nowPlaying) {
            [artworkImage setImage:art];
        } else {
            [artworkImage setImage:[NSApp applicationIconImage]];
        }
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"Now Playing Detail"]) {
            if (!artistDetails && [ISArtistDetailsController canLoad])
                artistDetails = [[ISArtistDetailsController artistDetailsWithDelegate:self] retain];
            if (artistDetails)
                [artistDetails setArtist:[g_nowPlaying artist]];
        }
    }
}

- (void)profileDidReset:(NSNotification*)note
{
    static int doreset = 0;
    if (!doreset) {
        doreset = 1;
        // make sure we run after every other observer
        [self performSelector:@selector(profileDidReset:) withObject:note afterDelay:0.0];
        return;
    }
    
    doreset = 0;
    [self submitCompleteHandler:nil];
}

- (IBAction)showWindow:(id)sender
{
    // Register for PM notifications
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    [nc addObserver:self
            selector:@selector(handshakeStartHandler:)
            name:PM_NOTIFICATION_HANDSHAKE_START
            object:nil];
    [nc addObserver:self
            selector:@selector(handshakeCompleteHandler:)
            name:PM_NOTIFICATION_HANDSHAKE_COMPLETE
            object:nil];
    [nc addObserver:self
            selector:@selector(submitCompleteHandler:)
            name:PM_NOTIFICATION_SUBMIT_COMPLETE
            object:nil];
    [nc addObserver:self
            selector:@selector(submitStartHandler:)
            name:PM_NOTIFICATION_SUBMIT_START
            object:nil];
    // And QM notes
    [nc addObserver:self
            selector:@selector(songQueuedHandler:)
            name:QM_NOTIFICATION_SONG_QUEUED
            object:nil];
    // And Now Playing
    [nc addObserver:self
            selector:@selector(nowPlaying:)
            name:@"Now Playing"
            object:nil];
    
    // iPod notes
    [nc addObserver:self
            selector:@selector(iPodSyncBeginHandler:)
            name:IPOD_SYNC_BEGIN
            object:nil];
    [nc addObserver:self
            selector:@selector(iPodSyncEndHandler:)
            name:IPOD_SYNC_END
            object:nil];
    
    [nc addObserver:self
            selector:@selector(profileDidReset:) name:RESET_PROFILE object:nil];
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OPEN_STATS_WINDOW_AT_LAUNCH];
    
    [super showWindow:sender];

    SongData *song;
    if ((song = [[NSApp delegate] nowPlaying])) {
        NSNotification *note = [NSNotification notificationWithName:@"" object:song];
        [self nowPlaying:note];
    }
    
    // Set current values
    [self submitCompleteHandler:nil];
    // If the handshake is not valid, change the message
    if (![[[ProtocolManager sharedInstance] lastHandshakeResult] isEqualToString:HS_RESULT_OK])
        [self handshakeCompleteHandler:nil];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    // We don't simply call [[NSNotificationCenter defaultCenter] removeObserver:self] because
    // that seems to destroy our delegate link to the window (setDelegate: must register us as
    // an observer for window notifications instead of calling windowWillClose: directly).
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:PM_NOTIFICATION_HANDSHAKE_START object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:PM_NOTIFICATION_HANDSHAKE_COMPLETE object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:PM_NOTIFICATION_SUBMIT_COMPLETE object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:PM_NOTIFICATION_SUBMIT_START object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:QM_NOTIFICATION_SONG_QUEUED object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:@"Now Playing" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:IPOD_SYNC_BEGIN object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:IPOD_SYNC_END object:nil];
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:OPEN_STATS_WINDOW_AT_LAUNCH];
    ScrobTrace(@"received\n");
    
    // Close details drawer
    [artistDetails setArtist:nil];
    
    [g_cycleTimer invalidate];
    g_cycleTimer = nil;
    [g_nowPlaying release];
    g_nowPlaying = nil;
    [g_subDate release];
    g_subDate = nil;
    [g_SubUpdateTimer invalidate];
    g_SubUpdateTimer = nil;
    [rpcreq release];
    rpcreq = nil;
}

- (void)windowDidLoad
{
    [super setWindowFrameAutosaveName:@"iScrobbler Statistics"];
    
    NSString *title = [NSString stringWithFormat:@"%@ - %@", [[super window] title],
        [[NSUserDefaults standardUserDefaults] objectForKey:@"version"]];
    [[self window] setTitle:title];
    
    [submissionProgress setDisplayedWhenStopped:NO];
    [submissionProgress setUsesThreadedAnimation:YES];
    [nowPlayingText setStringValue:
        // 0x2026 == Unicode elipses
        [NSLocalizedString(@"Waiting for track", "") stringByAppendingFormat:@"%C", 0x2026]];
    
    [checkImage setHidden:YES];
    [artworkImage setImage:[NSApp applicationIconImage]];
    
    if ([ASXMLRPC isAvailable]) {
        // Create toolbar
        toolbarItems = [[NSMutableDictionary alloc] init];
        
        NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"stats"];
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
        [item setTag:kTBItemRequiresSong|kTBItemSongNotLovedBanned];
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
        [item setTag:kTBItemRequiresSong|kTBItemSongNotLovedBanned];
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
        [item setTag:kTBItemRequiresSong];
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
        [item setTag:kTBItemRequiresSong];
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
    } // [ASXMLRPC isAvailable])
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"iScrobbler Statistics Details Open"]) {
        [detailsText setStringValue:NSLocalizedString(@"Hide submission details", "")];
        [detailsDisclosure setState:NSOnState];
    } else
        [self showDetails:nil];
    
    [super windowDidLoad];
}

#define AQUA_SPACING 8.0

- (IBAction)showDetails:(id)sender
{
    NSWindow *win = [self window];
    NSRect wframe = [win frame], dvframe = [detailsView frame];
    if (sender && NSOnState == [sender state]) {
        wframe.size.height += dvframe.size.height + AQUA_SPACING;
        wframe.origin.y -= dvframe.size.height + AQUA_SPACING;
        [win setFrame:wframe display:YES animate:YES];
        [detailsView setHidden:NO];
        [detailsText setStringValue:NSLocalizedString(@"Hide submission details", "")];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"iScrobbler Statistics Details Open"];
    } else {
        // Remove details view
        [detailsView setHidden:YES];
        // Re-size window
        wframe.size.height -= dvframe.size.height + AQUA_SPACING;
        wframe.origin.y += dvframe.size.height + AQUA_SPACING;
        [win setFrame:wframe display:YES animate:YES];
        [detailsText setStringValue:NSLocalizedString(@"Show submission details", "")];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"iScrobbler Statistics Details Open"];
    }
}

- (IBAction)loveTrack:(id)sender
{
    ASXMLRPC *req = [[ASXMLRPC alloc] init];
    [req setMethod:@"loveTrack"];
    NSMutableArray *p = [req standardParams];
    [p addObject:[g_nowPlaying artist]];
    [p addObject:[g_nowPlaying title]];
    [req setParameters:p];
    [req setDelegate:self];
    [req setRepresentedObject:g_nowPlaying];
    [req sendRequest];
    rpcreq = req;
}

- (IBAction)banTrack:(id)sender
{
    ASXMLRPC *req = [[ASXMLRPC alloc] init];
    [req setMethod:@"banTrack"];
    NSMutableArray *p = [req standardParams];
    [p addObject:[g_nowPlaying artist]];
    [p addObject:[g_nowPlaying title]];
    [req setParameters:p];
    [req setDelegate:self];
    [req setRepresentedObject:g_nowPlaying];
    [req sendRequest];
    rpcreq = req;
}

- (void)recommendSheetDidEnd:(NSNotification*)note
{
    ISRecommendController *rc = [note object];
    if ([rc send]) {
        ASXMLRPC *req = [[ASXMLRPC alloc] init];
        NSMutableArray *p = [req standardParams];
        SongData *song = [rc representedObject];
        switch ([rc type]) {
            case rt_track:
                [req setMethod:@"recommendTrack"];
                [p addObject:[song artist]];
                [p addObject:[song title]];
            break;
            
            case rt_artist:
                [req setMethod:@"recommendArtist"];
                [p addObject:[song artist]];
            break;
            
            case rt_album:
                [req setMethod:@"recommendAlbum"];
                [p addObject:[song artist]];
                [p addObject:[song album]];
            break;
            
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
        rpcreq = req;
    }
    
exit:
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISRecommendDidEnd object:rc];
    [rc release];
}

- (IBAction)recommend:(id)sender
{
    ISRecommendController *rc = [[ISRecommendController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recommendSheetDidEnd:)
        name:ISRecommendDidEnd object:rc];
    [rc setRepresentedObject:g_nowPlaying];
    [rc showWindow:[self window]];
}

- (void)tagSheetDidEnd:(NSNotification*)note
{
    ISTagController *tc = [note object];
    if ([tc send]) {
        ASXMLRPC *req = [[ASXMLRPC alloc] init];
        NSMutableArray *p = [req standardParams];
        SongData *song = [tc representedObject];
        NSString *mode = [tc editMode] == tt_overwrite ? @"set" : @"append";
        switch ([tc type]) {
            case tt_track:
                [req setMethod:@"tagTrack"];
                [p addObject:[song artist]];
                [p addObject:[song title]];
            break;
            
            case tt_artist:
                [req setMethod:@"tagArtist"];
                [p addObject:[song artist]];
            break;
            
            case tt_album:
                [req setMethod:@"tagAlbum"];
                [p addObject:[song artist]];
                [p addObject:[song album]];
            break;
            
            default:
                [req release];
                goto exit;
            break;
        }
        [p addObject:[tc tags]];
        [p addObject:mode];
        
        [req setParameters:p];
        [req setDelegate:self];
        [req setRepresentedObject:song];
        [req sendRequest];
        rpcreq = req;
    }

exit:
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISTagDidEnd object:tc];
    [tc release];
}

- (IBAction)tag:(id)sender
{
    ISTagController *tc = [[ISTagController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tagSheetDidEnd:)
        name:ISTagDidEnd object:tc];
    [tc setRepresentedObject:g_nowPlaying];
    [tc showWindow:[self window]];
}

- (IBAction)showLovedBanned:(id)sender
{

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
        [[request representedObject] setLoved:YES];
        tag = @"loved";
    } else if ([method isEqualToString:@"banTrack"]) {
        [[request representedObject] setBanned:YES];
        tag = @"banned";
    }
    
    ScrobLog(SCROB_LOG_TRACE, @"RPC request '%@' successful (%@)",
        method, [request representedObject]);
    
    if (tag && [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTagLovedBanned"]) {
        ASXMLRPC *tagReq = [[ASXMLRPC alloc] init];
        NSMutableArray *p = [tagReq standardParams];
        SongData *song = [request representedObject];
        NSString *mode = @"append";
        [tagReq setMethod:@"tagTrack"];
        [p addObject:[song artist]];
        [p addObject:[song title]];
        [p addObject:[NSArray arrayWithObject:tag]];
        [p addObject:mode];
        
        [tagReq setParameters:p];
        [tagReq setDelegate:self];
        [tagReq setRepresentedObject:song];
        [tagReq performSelector:@selector(sendRequest) withObject:nil afterDelay:0.0];
        
        [rpcreq release];
        rpcreq = tagReq;
    } else {
        [rpcreq release];
        rpcreq = nil;
    }
}

- (void)error:(NSError*)error receivedForRequest:(ASXMLRPC*)request
{
    ScrobLog(SCROB_LOG_ERR, @"RPC request '%@' for '%@' returned error: %@",
        [request method], [request representedObject], error);
    
    [rpcreq release];
    rpcreq = nil;
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
        #ifdef notyet
        @"showloveban",
        NSToolbarSeparatorItemIdentifier,
        #endif
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
    int flags = [item tag];
    BOOL valid = YES;
    if ((flags & kTBItemRequiresSong))
        valid = (g_nowPlaying && !rpcreq ? YES : NO);
    if (valid && (flags & kTBItemSongNotLovedBanned))
        valid = (![g_nowPlaying loved] && ![g_nowPlaying banned]);
    
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
