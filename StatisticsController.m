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

static StatisticsController *g_sub;

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
    [selection setValue:[[pm lastSongSubmitted] breif] forKey:@"Last Track Submission"];
    
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
    
    // Raise level so the window is pretty much in front of everything.
    //[[self window] setLevel:NSModalPanelWindowLevel];
    [super setWindowFrameAutosaveName:@"iScrobbler Statistics"];
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"iScrobbler Statistics Window Open"];
    
    [super showWindow:sender];
    
    // Set current values
    [self submitCompleteHandler:nil];
    // If the handshake is not valid, change the message
    if (![[[ProtocolManager sharedInstance] lastHandshakeResult] isEqualToString:HS_RESULT_OK])
        [self handshakeCompleteHandler:nil];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"iScrobbler Statistics Window Open"];
}

@end
