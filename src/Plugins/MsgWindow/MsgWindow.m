//
//  MsgWindow.m
//  iScrobbler Plugin
//
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import "MsgWindow.h"
#import "MsgWindowController.h"

@implementation ISMsgWindow

- (void)message:(NSString*)msg withTitle:(NSString*)title withImage:(NSImage*)img sticky:(BOOL)sticky
{
    ISMsgWindowController *mwc = img ? [ISMsgWindowController messageWindowWithIcon] : [ISMsgWindowController messageWindow];
    [mwc loadWindow];
    [mwc setValue:title forKey:@"title"];
    [mwc setValue:msg forKey:@"message"];
    [mwc setValue:img forKey:@"icon"];
    [mwc showWindow:nil];
    if (!sticky)
        [[mwc window] performSelector:@selector(performClose:) withObject:nil afterDelay:4.0];
}

- (void)message:(NSString*)msg withTitle:(NSString*)title withImage:(NSImage*)img
{
    [self message:msg withTitle:title withImage:img sticky:NO];
}

// ISPlugin protocol

- (id)initWithAppProxy:(id<ISPluginProxy>)proxy
{
    self = [super init];
    mProxy = proxy;
    
    return (self);
}

- (NSString*)description
{
    return (NSLocalizedString(@"MsgWindow Plugin", ""));
}

- (void)applicationWillTerminate
{

}

@end
