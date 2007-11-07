//
//  ISProxy.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 11/6/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

// There are serious Applescript bugs in 10.5.0 for 64bit apps.
// ISProxy is simplye a 32 bit proxy to run problematic scripts until the issues are fixed (hopefully in 10.5.1, but I'm not counting on it)

#import "ISProxyProtocol.h"

@interface ISProxy : NSObject <ISProxyProtocol> {
    NSMutableDictionary *compiledScripts;
}

@end
