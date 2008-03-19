//
//  SubStats.m
//  iScrobbler Plugin
//
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import "SubStats.h"
#import "SubStatsController.h"

@implementation ISSubStats

- (void)showWindow:(id)sender
{
    [[SubStatsController sharedInstance] showWindow:sender];
}

// ISPlugin protocol

- (id)initWithAppProxy:(id<ISPluginProxy>)proxy
{
    self = [super init];
    mProxy = proxy;
    
    [[SubStatsController sharedInstance] loadWindow];
    
    @try {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Submission Statistics", "")
        action:@selector(showWindow:) keyEquivalent:@""];
    [item setTarget:self];
    [item setEnabled:YES];
    [mProxy addMenuItem:item];
    [item release];
    } @catch (NSException *e) {}
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:ISSUBSTATS_WINDOW_OPEN]) {
        [self performSelector:@selector(showWindow:) withObject:nil afterDelay:.1];
    }
    
    return (self);
}

- (NSString*)description
{
    return (NSLocalizedString(@"Submission Statistics Plugin", ""));
}

- (void)applicationWillTerminate
{

}

@end
