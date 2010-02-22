//
//  ISPlugin.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/1/2007.
//  Copyright 2007,2008,2010 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

ISEXPORT_CLASS
@protocol ISPluginProxy

- (NSBundle*)applicationBundle;
- (NSString*)applicationVersion;
- (NSString*)nowPlayingNotificationName;

- (void)addMenuItem:(NSMenuItem*)item;

- (BOOL)isNetworkAvailable;

@end

ISEXPORT_CLASS
@protocol ISPlugin

- (id)initWithAppProxy:(id<ISPluginProxy>)proxy;
- (NSString*)description;
- (void)applicationWillTerminate;

@end
