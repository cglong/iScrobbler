//
//  StatisticsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/18/04.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "StatisticsController.h"
#import "ProtocolManager.h"
#import "QueueManager.h"
#import "iScrobblerController.h"

static StatisticsController *g_sub = nil;
static SongData *g_nowPlaying = nil;
static NSTimer *g_cycleTimer = nil;
static enum {title, album, artist} g_cycleState = title;

@implementation StatisticsController

+ (StatisticsController*)sharedInstance
{
    if (g_sub)
        return (g_sub);
    
    return ((g_sub = [[StatisticsController alloc] initWithWindowNibName:@"StatisticsController"]));
}

- (void)handshakeCompleteHandler:(NSNotification*)note
{
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
    ProtocolManager *pm = [ProtocolManager sharedInstance];
    QueueManager *qm = [QueueManager sharedInstance];
    id selection = [values selection];
    
    if ([[pm lastSubmissionResult] isEqualToString:HS_RESULT_OK])
        [selection setValue:[NSColor blackColor] forKey:@"Server Response Color"];
    else
        [selection setValue:[NSColor redColor] forKey:@"Server Response Color"];
    
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm totalSubmissionsCount]]
        forKey:@"Tracks Submitted"];
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm count]]
        forKey:@"Tracks Queued"];
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm submissionAttemptsCount]]
        forKey:@"Submission Attempts"];
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm successfulSubmissionsCount]]
        forKey:@"Successful Submissions"];
    [selection setValue:[pm lastSubmissionMessage] forKey:@"Server Response"];
    [selection setValue:[[pm lastSongSubmitted] brief] forKey:@"Last Track Submission"];
    
}

- (void)songQueuedHandler:(NSNotification*)note
{
    QueueManager *qm = [QueueManager sharedInstance];
    id selection = [values selection];
    
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm totalSubmissionsCount]]
        forKey:@"Tracks Submitted"];
    [selection setValue:[NSNumber numberWithUnsignedInt:[qm count]]
        forKey:@"Tracks Queued"];
}

- (void)cycleNowPlaying:(NSTimer *)timer
{
    NSString *msg = nil, *rating;
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
            g_cycleState = title;
            break;
    }
    
    // It would be cool if we could do some text alpha fading when the msg changes,
    // but that's too much work...
    [nowPlayingText setStringValue:msg];
}

- (void)nowPlaying:(NSNotification*)note
{
    SongData *song = [note object];
    
    if (!song || ![g_nowPlaying isEqualToSong:song]) {
        [g_nowPlaying release];
        g_nowPlaying = [song retain];
        g_cycleState = title;
        
        [g_cycleTimer invalidate];
        g_cycleTimer = nil;
        if (g_nowPlaying) {
            // Create the timer
            g_cycleTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self
                selector:@selector(cycleNowPlaying:) userInfo:nil repeats:YES];
            [g_cycleTimer fire];
        } else {
            [nowPlayingText setStringValue:
                // 0x2026 == Unicode elipses
                [NSLocalizedString(@"Waiting for track", "") stringByAppendingFormat:@"%C", 0x2026]];
        }
    }
}

- (IBAction)showWindow:(id)sender
{
    // Register for PM notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(handshakeCompleteHandler:)
            name:PM_NOTIFICATION_HANDSHAKE_COMPLETE
            object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(submitCompleteHandler:)
            name:PM_NOTIFICATION_SUBMIT_COMPLETE
            object:nil];
    // And QM notes
    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(songQueuedHandler:)
            name:QM_NOTIFICATION_SONG_QUEUED
            object:nil];
    // And Now Playing
    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(nowPlaying:)
            name:@"Now Playing"
            object:nil];
    
    [super setWindowFrameAutosaveName:@"iScrobbler Statistics"];
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OPEN_STATS_WINDOW_AT_LAUNCH];
    
    [super showWindow:sender];
    
    // This will fire off a Now Playing notification
    [[NSApp delegate] mainTimer:nil];
    
    // Set current values
    [self submitCompleteHandler:nil];
    // If the handshake is not valid, change the message
    if (![[[ProtocolManager sharedInstance] lastHandshakeResult] isEqualToString:HS_RESULT_OK])
        [self handshakeCompleteHandler:nil];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:OPEN_STATS_WINDOW_AT_LAUNCH];
    
    [g_cycleTimer invalidate];
    g_cycleTimer = nil;
    [g_nowPlaying release];
    g_nowPlaying = nil;
}

- (void)windowDidLoad
{
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
