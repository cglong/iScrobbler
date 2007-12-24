//
//  Template.m
//  iScrobbler Plugin
//
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import "Template.h"

@implementation iScrobblerTemplatePlugin

// ISPlugin protocol

- (id)initWithAppProxy:(id<ISPluginProxy>)proxy
{
    self = [super init];
    mProxy = proxy;
    
    return (self);
}

- (NSString*)description
{
    return (NSLocalizedString(@"Temlate Plugin", ""));
}

- (void)applicationWillTerminate
{

}

@end
