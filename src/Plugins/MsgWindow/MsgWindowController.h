//
//  MsgWindowController.h
//  iScrobbler Plugin
//
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import <Cocoa/Cocoa.h>

@interface ISMsgWindowController : NSWindowController {
    IBOutlet NSView *textView;
    IBOutlet NSView *iconView;
    IBOutlet NSImageView *iconControl;
    
    NSString *title;
    NSString *msg;
    BOOL wantsIconView;
}

+ (ISMsgWindowController*)messageWindow;
+ (ISMsgWindowController*)messageWindowWithIcon;

// bindings
- (NSString*)title;
- (void)setTitle:(NSString*)s;
- (NSString*)message;
- (void)setMessage:(NSString*)s;
- (NSImage*)icon;
- (void)setIcon:(NSImage*)ico;

@end
