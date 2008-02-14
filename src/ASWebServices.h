//
//  ASWebServices.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 2/8/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Foundation/Foundation.h>

@interface ASWebServices : NSObject {
    NSTimer *hstimer;
    NSMutableDictionary *sessionvars;
    NSInteger skipsLeft;
    BOOL discovery, stopped, canGetMoreTracks;
}

+ (ASWebServices*)sharedInstance;

+ (NSURL*)currentUserTagsURL;
+ (NSURL*)currentUserFriendsURL;
+ (NSURL*)currentUserNeighborsURL;

- (void)handshake;
- (BOOL)needHandshake;
- (BOOL)subscriber;
#ifdef notyet
- (BOOL)discovery;
#endif
- (void)setDiscovery:(BOOL)state;
- (void)tuneStation:(NSString*)station;
- (void)exec:(NSString*)command;
- (void)stop;
- (BOOL)stopped;

// radio control
// sends ASWSNowPlayingDidUpdate or ASWSNowPlayingFailed when finished
// the ASWSNowPlayingDidUpdate userInfo is a dictionary of the track to play
- (void)updatePlaylist;
- (NSInteger)playlistSkipsLeft;
- (void)decrementPlaylistSkipsLeft;

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

#define ISR_PLAYLIST @"playlist"
// Keys for playlist entries
#define ISR_TRACK_URL @"location"
#define ISR_TRACK_TITLE @"title"
// NSInteger
#define ISR_TRACK_LFMID @"lfmTrackID"
#define ISR_TRACK_ALBUM @"album"
#define ISR_TRACK_ARTIST @"artist"
// NSInteger, millisecs
#define ISR_TRACK_DURATION @"duration"
#define ISR_TRACK_IMGURL @"imageLocation"
// All the following: NSInteger
#define ISR_TRACK_LFMAUTH @"lfmTrackAuth"
#define ISR_TRACK_LFMALBUMID @"lfmAlbumID"
#define ISR_TRACK_LFMARTISTID @"lfmArtistID"

// [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode]
#define WS_LANG @"en"
