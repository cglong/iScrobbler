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
#import "QueueManager.h"ur

// UTF16 barred eigth notes
#define MENU_TITLE_CHAR 0x266B
// UTF16 sharp note 
#define MENU_TITLE_SUB_DISABLED_CHAR 0x266F

@implementation ISStatusItem

- (NSColor*)primaryColor
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
    NSAttributedString *newTitle =
        [[NSAttributedString alloc] initWithString:[statusItem title]
            attributes:[NSDictionary dictionaryWithObjectsAndKeys:color, NSForegroundColorAttributeName,
            // If we don't specify this, the font defaults to Helvitica 12
            [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName, nil]];
    [statusItem setAttributedTitle:newTitle];
    [newTitle release];
    
    unsigned tracksQueued;
    if (msg) {
        // Get rid of extraneous protocol information
        NSArray *items = [msg componentsSeparatedByString:@"\n"];
        if (items && [items count] > 0)
            msg = [items objectAtIndex:0];
    } else {
        msg = [NSString stringWithFormat:@"%@: %u",
                NSLocalizedString(@"Tracks Sub'd", "Tracks Submitted Abbreviation"), [[QueueManager sharedInstance] totalSubmissionsCount]];
        if (tracksQueued = [[QueueManager sharedInstance] count]) {
            msg = [msg stringByAppendingFormat:@", %@: %u",
                NSLocalizedString(@"Q'd", "Tracks Queued Abbreviation"), tracksQueued];
        }
    }
    [statusItem setToolTip:msg];
}

- (void)updateStatus:(BOOL)opSuccess withOperation:(BOOL)opBegin withMsg:(NSString*)msg
{
    NSColor *color;
    if (opBegin)
        color = [NSColor greenColor];
    else {
        if (opSuccess)
            color = [self primaryColor];
        else {
            color = [NSColor redColor];
        }
    }
    
    [self updateStatusWithColor:color withMsg:msg];
}

- (NSColor*)color
{
    NSColor *color = [[statusItem attributedTitle] attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil];
    if (!color)
        color = [self primaryColor];
    return (color);
}

- (void)setSubmissionsEnabled:(BOOL)enabled
{
    unichar ch;
    if (enabled)
        ch = MENU_TITLE_SUB_DISABLED_CHAR;
    else
        ch = MENU_TITLE_CHAR;
    NSColor *color = [[statusItem attributedTitle] attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil];
    
    NSAttributedString *newTitle =
        [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&ch length:1]
            attributes:[NSDictionary dictionaryWithObjectsAndKeys:color, NSForegroundColorAttributeName,
            // If we don't specify this, the font defaults to Helvitica 12
            [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName, nil]];
    [statusItem setAttributedTitle:newTitle];
    [newTitle release];
}

- (id)initWithMenu:(NSMenu*)menu
{
    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
            
    NSAttributedString *newTitle =
        [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%C", MENU_TITLE_CHAR]
            attributes:[NSDictionary dictionaryWithObjectsAndKeys:[self primaryColor], NSForegroundColorAttributeName,
            // If we don't specify this, the font defaults to Helvitica 12
            [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName, nil]];
    [statusItem setAttributedTitle:newTitle];
    [newTitle release];
    
    [statusItem setHighlightMode:YES];
    [statusItem setMenu:menu];
    [statusItem setEnabled:YES];
    return (self);
}

- (void)dealloc
{
    [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
    [statusItem setMenu:nil];
    [super dealloc];
}

@end
