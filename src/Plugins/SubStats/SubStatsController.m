//
//  SubStatsController.m
//  iScrobbler Plugin
//
//  Copyright 2008,2009 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import "SubStatsController.h"

@protocol QueueManagerStats
- (NSUInteger)count;
@end

@implementation SubStatsController

- (void)songDidQueueHandler:(NSNotification*)note
{
    [queueCount setStringValue:[NSString stringWithFormat:@"%@", [[note userInfo] objectForKey:@"queueCount"]]];
}

- (void)protocolMsgCompleteHandler:(NSNotification*)note
{
    NSNumberFormatter *format = [[[NSNumberFormatter alloc] init] autorelease];
    [format setNumberStyle:NSNumberFormatterDecimalStyle];

    NSDictionary *info = [note userInfo];
    [subCount setStringValue:[NSString stringWithFormat:@"%@ (%@)", 
        [format stringFromNumber:[info valueForKey:@"successfulSubmissions"]],
        [format stringFromNumber:[info objectForKey:@"submissionAttempts"]]]];
    [queueCount setStringValue:[NSString stringWithFormat:@"%@", [info objectForKey:@"queueCount"]]];
    [lastfmResponse setStringValue:[info objectForKey:@"lastServerRepsonse"]];
    NSString *s = [info objectForKey:@"lastSongSubmitted"];
    if (s)
        [lastTrack setStringValue:s];
}

- (id)init
{
    return ((self = [super initWithWindowNibName:@"SubStats"]));
}

+ (SubStatsController*)sharedInstance
{
    static SubStatsController *sc = nil;
    return (sc ? sc : (sc = [[SubStatsController alloc] init]));
}

- (BOOL)windowShouldClose:(NSNotification*)note
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:ISSUBSTATS_WINDOW_OPEN];

    return ([self scrobWindowShouldClose]);
}

- (void)showWindow:(id)sender
{
    if (![[self window] isVisible]) {
        [NSApp activateIgnoringOtherApps:YES];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:ISSUBSTATS_WINDOW_OPEN];
    }

    [super showWindow:sender];
}

- (void)awakeFromNib
{
    NSUInteger style = NSTitledWindowMask|NSClosableWindowMask|NSUtilityWindowMask;
    style |= NSHUDWindowMask;
    NSWindow *w = [[NSPanel alloc] initWithContentRect:[statsView frame] styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [w setHidesOnDeactivate:NO];
    [w setLevel:NSNormalWindowLevel];
    
    [w setReleasedWhenClosed:NO];
    [w setContentView:statsView];
    [w setMinSize:[[w contentView] frame].size];
    [w setMaxSize:[[w contentView] frame].size];
    [w setTitle:NSLocalizedString(@"Last.fm Submission Statistics", "")];
    [self setWindowFrameAutosaveName:@"SubStatsPlugin"];
    
    [self setWindow:w];
    [w setDelegate:self]; // setWindow: does not do this for us (why?)
    [w autorelease];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(protocolMsgCompleteHandler:)
        name:@"PMHandshakeComplete"
        object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(protocolMsgCompleteHandler:)
        name:@"PMSubmitComplete"
        object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(songDidQueueHandler:)
        name:@"QMNotificationSongQueued"
        object:nil];
    
    [subCount setStringValue:@"0 (0)"];
    [lastTrack setStringValue:@""];
    [queueCount setStringValue:@"0"];
    [lastfmResponse setStringValue:@""];
}

- (NSColor*)textFieldColor
{
    #if 0
    return (([[self window] styleMask] & NSHUDWindowMask) ? [NSColor lightGrayColor] : [NSColor blackColor]);
    #endif
    // window may not be set when the binding calls us
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    return ([NSColor lightGrayColor]);
    #else
    return ((floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_4) ? [NSColor lightGrayColor] : [NSColor blackColor]);
    #endif
}

@end
