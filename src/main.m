//
//  main.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
@interface ISTigerAnimationViewProxy : NSView {
}

- (id)animator;
@end

@implementation ISTigerAnimationViewProxy

- (id)animator
{
    return (self);
}

@end
#endif

int main(int argc, const char *argv[])
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber10_4) {
        // this allows us to use [view animator] throught out the code w/o adding a runtime check for each instance
        #ifdef ISDEBUG
        NSLog(@"ISTigerAnimationViewProxy posing as NSView\n");
        #endif
        [ISTigerAnimationViewProxy poseAsClass:[NSView class]];
    }
    #endif
    
    return NSApplicationMain(argc, argv);
}
