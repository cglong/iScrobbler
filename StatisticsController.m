//
//  StatisticsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/18/04.
//  Copyright 2004-2006 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "StatisticsController.h"
#import "ProtocolManager.h"
#import "QueueManager.h"
#import "iScrobblerController.h"
#import "ISArtistDetailsController.h"

static StatisticsController *g_sub = nil;
static SongData *g_nowPlaying = nil;
static NSTimer *g_cycleTimer = nil, *g_SubUpdateTimer = nil;
static NSDate *g_subDate = nil;
static enum {title, album, artist, subdate} g_cycleState = title;

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
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"iScrobbler Statistics Details Open"]) {
        [detailsText setStringValue:NSLocalizedString(@"Hide submission details", "")];
        [detailsDisclosure setState:NSOnState];
    } else
        [self showDetails:nil];
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

@end
