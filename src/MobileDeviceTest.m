//
//  MobileDeviceSupport.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 7/12/2007.
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
//
// cc -gdwarf-2 -O0 -DDEBUG -framework Foundation -framework IOKit -o amds MobileDeviceTest.m MobileDeviceSupport.m

#import <Foundation/Foundation.h>
#import "MobileDeviceSupport.h"

int main(int argc, char *argv[])
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	char *path = "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice";
	int err;
	if (0 != (err = IntializeMobileDeviceSupport(path, NULL))) {
		return (err);
	}
	
	do {
        @try {
        [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        
        } @catch (NSException *e) {
            NSLog (@"[sessionManager:] uncaught exception: %@\n", e);
        }
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
    } while (1);
}
