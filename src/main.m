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

@interface ISLogLevelToBool : NSValueTransformer {
}
@end

@interface ISDateToString : NSValueTransformer {
}
@end

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [NSValueTransformer setValueTransformer:[[[ISLogLevelToBool alloc] init] autorelease]
        forName:@"ISLogLevelIsTrace"];
    
    [NSValueTransformer setValueTransformer:[[[ISDateToString alloc] init] autorelease]
        forName:@"ISDateToString"];
    
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

@implementation ISLogLevelToBool

+ (Class)transformedValueClass
{
    return [NSNumber class];
}

+ (BOOL)allowsReverseTransformation
{
    return (YES);   
}

- (id)transformedValue:(id)value
{
    return ([NSNumber numberWithBool:[value isEqualTo:@"TRACE"]]);
}

- (id)reverseTransformedValue:(id)value
{
    if ([value boolValue])
        return (@"TRACE");
    
    return (@"VERB");
}

@end

@implementation ISDateToString

+ (Class)transformedValueClass
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation
{
    return (NO);   
}

- (id)transformedValue:(id)value
{
    return ([value description]);
}

@end
