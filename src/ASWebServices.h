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

- (NSString*)station:(NSString*)type forUser:(NSString*)user;
- (NSString*)stationForCurrentUser:(NSString*)type;
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
