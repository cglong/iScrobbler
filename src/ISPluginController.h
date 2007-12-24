//
//  ISPluginCopntroller.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/1/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>
#import "ISPlugin.h"

@interface ISPluginController : NSObject <ISPluginProxy> {

}

+ (ISPluginController*)sharedInstance;

- (id)loadCorePlugin:(NSString*)name;

@end
