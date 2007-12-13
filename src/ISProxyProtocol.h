//
//  ISProxyProtocol.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 11/6/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

// There are serious Applescript bugs in 10.5.0 for 64bit apps.
// ISProxy is simply a 32 bit proxy to run problematic scripts until the issues are fixed.
// (Hopefully in 10.5.2, but I'm not counting on it.)

#import <Cocoa/Cocoa.h>

#define ISProxyName @"org.bergstrand.iscrobbler.proxy"

@protocol ISProxyProtocol

- (NSDictionary*)runScriptWithURL:(in NSURL*)url handler:(in NSString*)handler args:(in NSArray*)args;
- (oneway void)kill;

@end

// This defines how long the DO connection will wait before timing out and as a side effect how long a script can run
#define ISPROXY_TIMEOUT 60.0
