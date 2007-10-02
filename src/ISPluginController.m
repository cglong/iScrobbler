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
    
    NSDirectoryEnumerator *den = [[NSFileManager defaultManager] enumeratorAtPath:[[NSBundle mainBundle] builtInPlugInsPath]];
    NSString *path;
    NSBundle *bundle;
    id plug;
    while ((path = [den nextObject])) {
        @try {
            if ((bundle = [NSBundle bundleWithPath:path])) {
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
    //[NSThread exit];
}

- (id)init
{
    //[NSThread detachNewThreadSelector:@selector(loadPlugins:) toTarget:self withObject:nil];
    [self loadPlugins:nil];
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
