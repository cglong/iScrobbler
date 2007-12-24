//
//  ISPluginCopntroller.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/1/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
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
    [allPlugins addObjectsFromArray:[plugs retain]];
}

- (id)loadPlugin:(NSString*)path
{
    NSBundle *bundle;
    id plug = nil;
    @try {
        if ((bundle = [NSBundle bundleWithPath:path])) {
            if ([bundle isLoaded) {
                ScrobLog(SCROB_LOG_ERR, @"exception loading plugin '%@': %@", path, @"Bundle already loaded");
                return (nil);
            }
            
            Class c = [bundle principalClass];
            if ([c conformsToProtocol:@protocol(ISPlugin)]) {
                if ((plug = [[c alloc] initWithAppProxy:self])) {
                    ScrobLog(SCROB_LOG_INFO, @"Loaded plugin '%@' from '%@'", [plug description], [path lastPathComponent]);
                    (void)[plug autorelease];
                } else
                    @throw ([NSException exceptionWithName:NSObjectInaccessibleException reason:@"Failed to instantiate plugin" userInfo:nil]);
            } else
                @throw ([NSException exceptionWithName:NSObjectNotAvailableException reason:@"Plugin does not conform to protocol" userInfo:nil]);
        } else
            @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"Not a valid bundle" userInfo:nil]);
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception loading plugin '%@': %@", path, e);
    }
    
    return  (plug);
}

- (void)loadPlugins:(id)arg
{
    NSMutableArray *plugs = [NSMutableArray array];
    
    NSString *pluginsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    NSDirectoryEnumerator *den = [[NSFileManager defaultManager] enumeratorAtPath:pluginsPath];
    NSString *path;
    id plug;
    while ((path = [den nextObject])) {
        [den skipDescendents];
        if ((plug = [self loadPlugin:[pluginsPath stringByAppendingPathComponent:path]])) {
            [plugs addObject:plug];
            [plug release];
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
    allPlugins = [[NSMutableArray alloc] init];
    
#ifdef THREADED_LOAD
    [NSThread detachNewThreadSelector:@selector(loadPlugins:) toTarget:self withObject:nil];
#else
    [self loadPlugins:nil];
#endif

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerm:)
        name:NSApplicationWillTerminateNotification object:NSApp];
    return (self);
}

- (id)loadCorePlugin:(NSString*)name
{
    name = [[[[[NSBundle mainBundle] builtInPlugInsPath] stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Core Plugins"] stringByAppendingPathComponent:name];
 
    [self performSelectorOnMainThread:@selector(pluginsDidLoad:) withObject:[NSArray arrayWithObject:plug] waitUntilDone:NO];
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

- (NSUInteger)retainCount
{
    return (NSUIntegerMax);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end
