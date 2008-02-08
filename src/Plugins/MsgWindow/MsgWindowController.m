//
//  MsgWindowController.m
//  iScrobbler Plugin
//
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import "MsgWindowController.h"

static int mwCount = 0;
static NSPoint mwLastWhere = {0.0,0.0};
#define MWPadding 10.0

@implementation ISMsgWindowController

- (id)init:(BOOL)wantsIcon
{
    self = [super initWithWindowNibName:@"MsgWindow"];
    wantsIconView = wantsIcon;
    return (self);
}

+ (ISMsgWindowController*)messageWindow
{
    return ([[ISMsgWindowController alloc] init:NO]);
}

+ (ISMsgWindowController*)messageWindowWithIcon
{
    return ([[ISMsgWindowController alloc] init:YES]);
}

// bindings
- (NSString*)title
{
    return (title);
}

- (void)setTitle:(NSString*)s
{
    if (s != title) {
        [title release];
        title = [s retain];
    }
}

- (NSString*)message
{
    return (msg);
}

- (void)setMessage:(NSString*)s
{
    if (s != msg) {
        [msg release];
        msg = [s retain];
    }
}

- (NSImage*)icon
{
    return ([iconControl image]);
}

- (void)setIcon:(NSImage*)ico
{
    [iconControl setImage:ico];
}

- (IBAction)showWindow:(id)sender
{
    NSRect wSize = [[self window] frame];
    NSRect screenSize = [[NSScreen mainScreen] visibleFrame];
    if (mwLastWhere.y < (screenSize.origin.y + MWPadding)) {
        mwLastWhere.y = screenSize.origin.y + screenSize.size.height;
        mwLastWhere.x = (screenSize.origin.x + screenSize.size.width) - wSize.size.width - MWPadding;
    }
    [[self window] setFrameTopLeftPoint:mwLastWhere];
    mwLastWhere.y -= wSize.size.height + MWPadding;
    ++mwCount;
    
    [super showWindow:sender];
}

- (BOOL)windowShouldClose:(NSNotification*)note
{
    [[self window] fadeOutAndClose];
    return (NO);
}

- (void)windowWillClose:(NSNotification*)note
{
    --mwCount;
    ISASSERT(mwCount >= 0, "count went south!");
    if (0 == mwCount) {
        mwLastWhere.x = mwLastWhere.y = 0.0;
    }
    
    [NSObject cancelPreviousPerformRequestsWithTarget:[self window]];
    [self autorelease];
}

- (void)awakeFromNib
{
    NSUInteger style = NSTitledWindowMask|NSClosableWindowMask|NSUtilityWindowMask;
    LEOPARD_BEGIN
    // this does not affect some of the window subviews (NSTableView) - how do we get HUD style controls?
    style |= NSHUDWindowMask;
    LEOPARD_END
    NSView *cv = wantsIconView ? iconView : textView;
    NSWindow *w = [[NSPanel alloc] initWithContentRect:[cv frame] styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [w setHidesOnDeactivate:NO];
    [w setLevel:NSStatusWindowLevel];
    if (0 == (style & NSHUDWindowMask))
        [w setAlphaValue:IS_UTIL_WINDOW_ALPHA];
    
    [w setReleasedWhenClosed:NO];
    [w setContentView:cv];
    [w setMinSize:[[w contentView] frame].size];
    
    [self setWindow:w];
    [w setDelegate:self]; // setWindow: does not do this for us (why?)
    [w autorelease];
    
    LEOPARD_BEGIN
    [iconControl setWantsLayer:YES];
    [iconControl setImageScaling:NSImageScaleProportionallyUpOrDown];
    LEOPARD_END
}

- (NSColor*)textFieldColor
{
    #if 0
    return (([[self window] styleMask] & NSHUDWindowMask) ? [NSColor whiteColor] : [NSColor blackColor]);
    #endif
    // window may not be set when the binding calls us
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    return ([NSColor grayColor]);
    #else
    return ((floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_4) ? [NSColor whiteColor] : [NSColor blackColor]);
    #endif
}

@end
