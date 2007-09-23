//
//  ASWebServices.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 2/8/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Foundation/Foundation.h>

@interface ASWebServices : NSObject {
    NSTimer *hstimer;
    NSMutableDictionary *sessionvars, *nowplaying;
}

+ (ASWebServices*)sharedInstance;

+ (NSURL*)currentUserTagsURL;
+ (NSURL*)currentUserFriendsURL;
+ (NSURL*)currentUserNeighborsURL;

- (void)handshake;
- (NSURL*)streamURL;
- (BOOL)subscriber;
- (void)updateNowPlaying;
- (NSDictionary*)nowPlayingInfo;
#ifdef notyet
- (BOOL)discovery;
#endif
- (void)setDiscovery:(BOOL)state;
- (void)tuneStation:(NSString*)station;
- (void)exec:(NSString*)command;
- (void)stop;

- (NSString*)station:(NSString*)type forUser:(NSString*)user;
- (NSString*)stationForCurrentUser:(NSString*)type;
- (NSString*)tagStation:(NSString*)tag forUser:(NSString*)user;
- (NSString*)tagStationForCurrentUser:(NSString*)tag;
- (NSString*)stationForGlobalTag:(NSString*)tag;
- (NSString*)stationForArtist:(NSString*)artist;
- (NSString*)stationForGroup:(NSString*)group;
@end

#define ASWSWillHandshake @"ASWSWillHandshake"
#define ASWSDidHandshake @"ASWSDidHandshake"
#define ASWSFailedHandshake @"ASWSFailedHandshake"
#define ASWSStationDidTune @"ASWSStationDidTune"
#define ASWSStationTuneFailed @"ASWSStationTuneFailed"
#define ASWSNowPlayingDidUpdate @"ASWSNowPlayingDidUpdate"
#define ASWSNowPlayingFailed @"ASWSNowPlayingFailed"
#define ASWSExecDidComplete @"ASWSExecDidComplete"
#define ASWSExecFailed @"ASWSExecFailed"
