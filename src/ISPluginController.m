//
//  ISPluginCopntroller.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/1/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISPluginController.h"
#import "ISPlugin.h"

static NSMutableArray *allPlugins = nil;

@implementation ISPluginController

+ (ISPluginController*)sharedInstance
{
    static ISPluginController *shared = nil;
    return (shared ? shared : (shared = [[ISPluginController alloc] init]));
}

- (void)pluginsDidLoad:(NSMutableArray*)plugs
{
    allPlugins = [plugs retain];
}

- (void)loadPlugins:(id)arg
{
    NSMutableArray *plugs = [NSMutableArray array];
    
    NSString *pluginsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    NSDirectoryEnumerator *den = [[NSFileManager defaultManager] enumeratorAtPath:pluginsPath];
    NSString *path;
    NSBundle *bundle;
    id plug;
    while ((path = [den nextObject])) {
        [den skipDescendents];
        @try {
            if ((bundle = [NSBundle bundleWithPath:[pluginsPath stringByAppendingPathComponent:path]])) {
                Class c = [bundle principalClass];
                if ([c conformsToProtocol:@protocol(ISPlugin)]) {
                    if ((plug = [[c alloc] initWithAppProxy:self])) {
                        ScrobLog(SCROB_LOG_INFO, @"Loaded plugin '%@' from '%@'", [plug description], [path lastPathComponent]);
                        [plugs addObject:plug];
                        [plug release];
                    } else
                        @throw ([NSException exceptionWithName:NSObjectInaccessibleException reason:@"Failed to instantiate plugin" userInfo:nil]);
                } else
                    @throw ([NSException exceptionWithName:NSObjectNotAvailableException reason:@"Plugin does not conform to protocol" userInfo:nil]);
            } else
                @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"Not a valid bundle" userInfo:nil]);
        } @catch (id e) {
            ScrobLog(SCROB_LOG_ERR, @"exception loading bundle '%@': %@", path, e);
        }
    }
    
    [self performSelectorOnMainThread:@selector(pluginsDidLoad:) withObject:plugs waitUntilDone:NO];
#ifdef THREADED_LOAD
    [NSThread exit];
#endif
}

- (void)appWillTerm:(NSNotification*)note
{
    [allPlugins makeObjectsPerformSelector:@selector(applicationWillTerminate)];
}

- (id)init
{
#ifdef THREADED_LOAD
    [NSThread detachNewThreadSelector:@selector(loadPlugins:) toTarget:self withObject:nil];
#else
    [self loadPlugins:nil];
#endif

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerm:)
        name:NSApplicationWillTerminateNotification object:NSApp];
    return (self);
}

// ISPluginProxy protocol

- (NSBundle*)applicationBundle
{
    return ([NSBundle mainBundle]);
}

- (NSString*)nowPlayingNotificationName
{
    return (@"Now Playing");
}

// Singleton support
- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (unsigned)retainCount
{
    return (UINT_MAX);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end
