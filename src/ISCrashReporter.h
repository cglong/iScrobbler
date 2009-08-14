//
//  ISCrashReporter.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 11/17/07.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@interface ISCrashReporter : NSObject
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
<NSTextViewDelegate>
#endif
{

}

+ (BOOL)crashReporter;

@end
