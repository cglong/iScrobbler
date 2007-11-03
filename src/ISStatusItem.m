//
//  ISStatusItem.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/25/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISStatusItem.h"
#import "ISStatusItemView.h"
#import "iScrobblerController.h"
#import "QueueManager.h"
#import "ISRadioController.h"

// UTF16 barred eigth notes
#define MENU_TITLE_CHAR 0x266B
// UTF16 sharp note 
#define MENU_TITLE_SUB_DISABLED_CHAR 0x266F

@implementation ISStatusItem

- (NSColor*)defaultStatusColor
{
    static NSSet *validColors = nil;
#if 1
    // Disable if this is ever made a GUI accessible pref
    static NSColor *color = nil;
    
    if (color)
        return (color);
#endif

    if (!validColors) {
        validColors = [[NSSet alloc] initWithArray:[NSArray arrayWithObjects:
            @"blackColor", @"darkGrayColor", @"lightGrayColor", @"whiteColor", @"grayColor", @"blueColor",
            @"cyanColor", @"yellowColor", @"magentaColor", @"purpleColor", @"brownColor", nil]];
    }
    
    NSString *method = [[NSUserDefaults standardUserDefaults] stringForKey:@"PrimaryMenuColor"];
    if (!method || ![validColors containsObject:method]) {
        if (method)
            ScrobLog(SCROB_LOG_TRACE, @"\"%@\" is not a valid menu color. Valid colors are: %@", method, validColors);
        return ([NSColor blackColor]);
    }
    
    @try {
    color = [[NSColor performSelector:NSSelectorFromString(method)] retain];
    } @catch (id e) {}
    
    
    return (color ? color : [NSColor blackColor]);
}

- (void)updateStatusWithColor:(NSColor*)color withMsg:(NSString*)msg
{
    NSUInteger tracksQueued;
    if (msg) {
        // Get rid of extraneous protocol information
        NSArray *items = [msg componentsSeparatedByString:@"\n"];
        if (items && [items count] > 0)
            msg = [items objectAtIndex:0];
    } else {
        msg = [NSString stringWithFormat:@"%@: %u",
                NSLocalizedString(@"Tracks Sub'd", "Tracks Submitted Abbreviation"), [[QueueManager sharedInstance] totalSubmissionsCount]];
        if (tracksQueued = [[QueueManager sharedInstance] count]) {
            msg = [msg stringByAppendingFormat:@", %@: %lu",
                NSLocalizedString(@"Q'd", "Tracks Queued Abbreviation"), tracksQueued];
        }
    }
    
    [tip release];
    tip = [msg retain];
    
    NSAttributedString *newTitle =
        [[NSAttributedString alloc] initWithString:[itemView title]
            attributes:[NSDictionary dictionaryWithObjectsAndKeys:color, NSForegroundColorAttributeName,
            // If we don't specify this, the font defaults to Helvitica 12
            [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName, nil]];
    [itemView setAttributedTitle:newTitle];
    [newTitle release];
}

- (void)updateStatus:(BOOL)opSuccess withOperation:(BOOL)opBegin withMsg:(NSString*)msg
{
    NSColor *color;
    if (opBegin)
        color = [NSColor greenColor];
    else {
        if (opSuccess)
            color = [self defaultStatusColor];
        else {
            color = [NSColor redColor];
        }
    }
    
    [self updateStatusWithColor:color withMsg:msg];
}

- (NSColor*)color
{
    NSColor *color = [[itemView titleAttributes] objectForKey:NSForegroundColorAttributeName];
    if (!color)
        color = [self defaultStatusColor];
    return (color);
}

- (void)setSubmissionsEnabled:(BOOL)enabled
{
    unichar ch;
    if (!enabled)
        ch = MENU_TITLE_SUB_DISABLED_CHAR;
    else
        ch = MENU_TITLE_CHAR;
    NSColor *color = [[itemView titleAttributes] objectForKey:NSForegroundColorAttributeName];
    
    NSAttributedString *newTitle =
        [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&ch length:1]
            attributes:[NSDictionary dictionaryWithObjectsAndKeys:color, NSForegroundColorAttributeName,
            // If we don't specify this, the font defaults to Helvitica 12
            [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName, nil]];
    [itemView setAttributedTitle:newTitle];
    [newTitle release];
}

- (void)displayInfo:(NSTimer*)timer
{
    displayTimer = nil;
    if (![itemView menuIsShowing]) {
        // If listening to the radio, prefer the station over the tip
        NSString *msg = [[ISRadioController sharedInstance] performSelector:@selector(currentStation)];
        if (msg)
            msg = [NSString stringWithFormat:@"%@: %@", IS_RADIO_TUNEDTO_STR, msg];
        [[NSApp delegate] displayNowPlayingWithMsg:msg ? msg : tip];
    }
}

- (void)mouseEntered:(NSEvent *)ev
{
    if (displayTimer)
        return;
    
    NSTimeInterval ti = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MenuNPInfoDelay"] / 1000.0f;
    displayTimer = [NSTimer scheduledTimerWithTimeInterval:ti target:self selector:@selector(displayInfo:) userInfo:nil repeats:NO];
}

- (void)mouseExited:(NSEvent *)ev
{
    [displayTimer invalidate];
    displayTimer = nil;
}

- (id)initWithMenu:(NSMenu*)menu
{
    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
    itemView = [[ISStatusItemView alloc] initWithController:self menu:menu];
    [statusItem setView:itemView];
    // view now has a correct frame, so we can set the tracking rect
    tag = [itemView addTrackingRect:[itemView frame] owner:self userData:nil assumeInside:NO];
    
    NSAttributedString *newTitle =
        [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%C", MENU_TITLE_CHAR]
            attributes:[NSDictionary dictionaryWithObjectsAndKeys:[self defaultStatusColor], NSForegroundColorAttributeName,
            // If we don't specify this, the font defaults to Helvitica 12
            [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName, nil]];
    [itemView setAttributedTitle:newTitle];
    [newTitle release];
    
    return (self);
}

- (void)dealloc
{
    if (tag)
		[itemView removeTrackingRect:tag];
    [displayTimer invalidate];
    
    [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
    [statusItem setMenu:nil];
    [statusItem setView:nil];
    [itemView release];
    [tip release];
    [statusItem release];
    [super dealloc];
}

@end
