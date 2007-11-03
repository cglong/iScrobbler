//
//  ISStatusItemView.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/25/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISStatusItemView.h"
#import "ISStatusItem.h"

// UTF16 barred eigth notes
#define MENU_TITLE_CHAR 0x266B
// UTF16 sharp note 
#define MENU_TITLE_SUB_DISABLED_CHAR 0x266F

@interface ISStatusItem (ISStatusItemViewEx)
- (NSStatusItem*)nsStatusItem;
- (void)itemMenuWillShow:(id)context;
@end

@implementation ISStatusItemView

- (void)mouseDown:(NSEvent *)ev
{
	//[[NSNotificationCenter defaultCenter] postNotificationName:@"StatusItemMenuWillShow" object:self];
    [sitem itemMenuWillShow:nil];
    menuIsShowing = YES;
	[self display];
    [[sitem nsStatusItem] popUpStatusItemMenu:menu];
	menuIsShowing = NO;
	[self setNeedsDisplay:YES];
}

- (id)initWithController:(ISStatusItem*)item menu:(NSMenu*)m
{
    self = [super initWithFrame:NSMakeRect(0.0f,0.0f,0.0f,0.0f)];
    sitem = item;
    menu = [m retain];
    return (self);
}

- (NSString*)title
{
    return (title);
}

- (NSDictionary*)titleAttributes
{
    return (attrs);
}

- (void)setTitle:(NSString*)s
{
    if (s != title) {
        [title release];
        title = [s retain];
        
        [attrs release];
        attrs = [[NSDictionary dictionaryWithObjectsAndKeys:
            // If we don't specify this, the font defaults to Helvitica 12
            [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
            [sitem defaultStatusColor], NSForegroundColorAttributeName,
            nil] retain];
        [self display];
    }
}

- (void)setAttributedTitle:(NSAttributedString*)s
{
    if ([s string] != title) {
        [title release];
        title = [[s string] retain];
    }
    
    [attrs autorelease];
    attrs = [[s attributesAtIndex:0 effectiveRange:nil] retain];
    [self display];
}

- (BOOL)menuIsShowing
{
    return (menuIsShowing);
}

- (void)drawRect:(NSRect)r
{
    NSDictionary *d;
    [[sitem nsStatusItem] drawStatusBarBackgroundInRect:[self frame] withHighlight:menuIsShowing];
    if (!menuIsShowing)
        d = attrs;
    else {
        d = [attrs mutableCopy];
        [(NSMutableDictionary*)d setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
        [d autorelease];
    }
    [title drawAtPoint:NSMakePoint(8.0,3.0) withAttributes:d];
}

-(void)dealloc
{
    [menu release];
    [title release];
    [attrs release];
    [super dealloc];
}

@end

@implementation ISStatusItem (ISStatusItemViewEx)

- (NSStatusItem*)nsStatusItem
{
    return (statusItem);
}

- (void)itemMenuWillShow:(id)context
{
    [displayTimer invalidate];
    displayTimer = nil;
}

@end

