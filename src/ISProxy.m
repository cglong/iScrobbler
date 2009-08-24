//
//  ISProxy.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 11/6/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "ISProxy.h"
#import "KFAppleScriptHandlerAdditionsCore.h"
#import "KFASHandlerAdditions-TypeTranslation.h"

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6
#import <sandbox.h>
#endif

#import "MobileDeviceSupport.h"

@implementation ISProxy

- (NSDictionary*)runScriptWithURL:(in NSURL*)url handler:(in NSString*)handler args:(in NSArray*)args;
{
    id result = nil;
    @try {
        NSAppleScript *script = [compiledScripts objectForKey:[url path]];
        if (!script) {
            if (!(script = [[[NSAppleScript alloc] initWithContentsOfURL:url error:nil] autorelease])) {
                return ([NSDictionary dictionaryWithObject:@"script failed to initialize" forKey:@"error"]);
            }
            
            if (![script compileAndReturnError:nil]) {
                return ([NSDictionary dictionaryWithObject:@"script failed to compile" forKey:@"error"]);
            }
            
            [compiledScripts setObject:script forKey:[url path]];
        }
        
        result = [script executeHandler:handler withParametersFromArray:args];
        return ([NSDictionary dictionaryWithObject:result forKey:@"result"]);
        
    } @catch (NSException *e) {
        return ([NSDictionary dictionaryWithObject:
            [@"script exception: " stringByAppendingString:[e description]] forKey:@"error"]);
    }
    
    return (nil);
}

- (oneway void)initializeMobileDeviceSupport:(NSString*)path
{
    (void)InitializeMobileDeviceSupport([path UTF8String], NULL);
}

- (oneway void)kill
{
    [NSApp terminate:nil];
}

- (id)init
{
    self = [super init];
    compiledScripts = [[NSMutableDictionary alloc] init];
    
    [[NSConnection defaultConnection] registerName:ISProxyName];
    [[NSConnection defaultConnection] setRootObject:
        [NSProtocolChecker protocolCheckerWithTarget:self protocol:@protocol(ISProxyProtocol)]];
    [[NSConnection defaultConnection] setReplyTimeout:ISPROXY_TIMEOUT];
    [[NSConnection defaultConnection] setRequestTimeout:ISPROXY_TIMEOUT];
}

@end

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6
    // This causes LaunchServices to fail on 10.6 with a -10810 error (tested with 64-bit only).
    // (Even though we don't restrict anything except read access to InputManager paths).
    const char *sbf = [[[NSBundle mainBundle] pathForResource:@"iScrobbler" ofType:@"sb"] fileSystemRepresentation];
    if (sbf && floor(NSFoundationVersionNumber) < NSFoundationVersionNumber10_6) {
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
    #endif
    
    (void)[NSApplication sharedApplication];
    
    (void)[[ISProxy alloc] init];
    [NSApp finishLaunching];
    do {
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
        @try {
        [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        } @catch (id e) {
            //ScrobLog(SCROB_LOG_TRACE, @"[sessionManager:] uncaught exception: %@", e);
        }
    } while (1);
    
    return (0);
}
