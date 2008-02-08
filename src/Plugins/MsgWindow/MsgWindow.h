//
//  MsgWindow.h
//  iScrobbler Plugin
//
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import <Cocoa/Cocoa.h>
#import "ISPlugin.h"

@interface ISMsgWindow : NSObject <ISPlugin> {
    id mProxy;
}

- (void)message:(NSString*)msg withTitle:(NSString*)title withImage:(NSImage*)img sticky:(BOOL)sticky;
- (void)message:(NSString*)msg withTitle:(NSString*)title withImage:(NSImage*)img;

@end
