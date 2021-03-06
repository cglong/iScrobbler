//
//  ISPluginCopntroller.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/1/2007.
//  Copyright 2007-2010 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "ISPluginController.h"
#import "ISPlugin.h"
#import "ProtocolManager.h"

static NSMutableArray *allPlugins = nil;

@implementation ISPluginController

+ (ISPluginController*)sharedInstance
{
    static ISPluginController *shared = nil;
    return (shared ? shared : (shared = [[ISPluginController alloc] init]));
}

- (void)pluginsDidLoad:(NSMutableArray*)plugs
{
    [allPlugins addObjectsFromArray:plugs];
}

- (id)loadPlugin:(NSString*)path
{
    NSBundle *bundle;
    id plug = nil;
    @try {
        if ((bundle = [NSBundle bundleWithPath:path])) {
            if ([bundle isLoaded]) {
                /// XXX: todo - find existing instance and return it
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
            } else {
                NSString *reason;
                if (c)
                    reason = [NSString stringWithFormat:@"Plugin class %@ does not conform to protocol", NSStringFromClass(c)];
                else
                    reason = @"Failed to load bundle class.";
                @throw ([NSException exceptionWithName:NSObjectNotAvailableException reason:reason userInfo:nil]);
            }
        } else
            @throw ([NSException exceptionWithName:NSInvalidArgumentException reason:@"Not a valid bundle" userInfo:nil]);
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"exception loading plugin '%@': %@", path, e);
    }
    
    return (plug);
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
        }
    }
    
    [self performSelectorOnMainThread:@selector(pluginsDidLoad:) withObject:plugs waitUntilDone:YES];
#ifdef THREADED_LOAD
    [NSThread exit];
#endif
}

- (void)appWillTerm:(NSNotification*)note
{
    @try {
    [allPlugins makeObjectsPerformSelector:@selector(applicationWillTerminate)];
    } @catch (NSException *e) {
        ScrobDebug(@"exception: %@", e);
    }
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
    name = [[[[[[NSBundle mainBundle] builtInPlugInsPath] stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Core Plugins"] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"plugin"];
    
    id plug;
    if ((plug = [self loadPlugin:name])) {
        [self performSelectorOnMainThread:@selector(pluginsDidLoad:) withObject:[NSArray arrayWithObject:plug] waitUntilDone:YES];
    }
    return (plug);
}

// ISPluginProxy protocol

- (NSBundle*)applicationBundle
{
    return ([NSBundle mainBundle]);
}

- (NSString*)applicationVersion
{
    return ([[NSApp delegate] performSelector:@selector(versionString)]);
}

- (NSString*)nowPlayingNotificationName
{
    return (@"Now Playing");
}

#ifndef PLUGINS_MENUITEM_TAG
#define PLUGINS_MENUITEM_TAG 9999
#endif

- (void)addMenuItem:(NSMenuItem*)item
{
    NSMenu *appMenu = [[NSApp delegate] valueForKey:@"theMenu"];
    NSMenuItem *plugRoot = [appMenu itemWithTag:PLUGINS_MENUITEM_TAG];
    
    [appMenu insertItem:item atIndex:[appMenu indexOfItem:plugRoot]];
}

- (BOOL)isNetworkAvailable
{
    return ([[ProtocolManager sharedInstance] isNetworkAvailable]);
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
