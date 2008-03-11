//
//  main.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>
#import <sandbox.h>
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
#pragma weak sandbox_init
#endif

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
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    if (sandbox_init)
    #endif
    {
        const char *sbf = [[[NSBundle mainBundle] pathForResource:@"iScrobbler" ofType:@"sb"] fileSystemRepresentation];
        if (sbf) {
            char *sberr = NULL;
            (void)sandbox_init(sbf, SANDBOX_NAMED_EXTERNAL, &sberr);
            if (sberr) {
                #ifdef ISDEBUG
                if (strlen(sberr) > 0)
                    NSLog(@"sandbox error: '%s'\n", sberr);
                #endif
                sandbox_free_error(sberr);
            }
        }
    }

    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber10_4) {
        // this allows us to use [view animator] throught out the code w/o adding a runtime check for each instance
        #ifdef ISDEBUG
        NSLog(@"ISTigerAnimationViewProxy posing as NSView\n");
        #endif
        [ISTigerAnimationViewProxy poseAsClass:[NSView class]];
    }
    #endif
    
    [pool release];
    
    return NSApplicationMain(argc, argv);
}
