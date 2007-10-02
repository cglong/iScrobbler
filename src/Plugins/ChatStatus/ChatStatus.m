//
//  iChatStatus.m
//
//  Created by Brian Bergstrand on 10/2/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <InstantMessage/IMService.h>

#import "ISPlugin.h"
#import "SongData.h"

// Private Class
@interface IMServiceAgent : NSObject {}

+ (void)setServiceAgentCapabilities:(int)fp8;
+ (int)serviceAgentCapabilities;
+ (id)sharedAgent;
+ (id)imageURLForStatus:(int)fp8;
- (id)allServices;
- (id)serviceWithName:(id)fp8;
- (id)notificationCenter;
- (void)loginAllServices;
- (void)logoutAllServices;
- (void)setMyStatus:(int)fp8 message:(id)fp12;
- (int)myStatus;
- (id)myStatusMessage;
- (void)setMyPictureData:(id)fp8;
- (id)myPictureData;
- (id)myIdleTime;
- (void)setMyProfile:(id)fp8;
- (id)myProfile;
- (id)myAvailableMessages;
- (id)myAwayMessages;
- (id)preferredClientSignature;
- (id)currentAVChatInfo;
- (unsigned int)requestAudioReflectorStart;
- (unsigned int)requestAudioReflectorStop;
- (unsigned int)requestVideoStillForPerson:(id)fp8;

@end

@interface ISChatStatus : NSObject <ISPlugin> {
    id mProxy;
    id currentSong;
    NSString *previousMsg;
    BOOL msgChanged;
}

@end

@implementation ISChatStatus

- (void)setStatusMessageWithSong:(SongData*)song
{
    BOOL alwaysDisplay = [[NSUserDefaults standardUserDefaults] boolForKey:@"builtin.Chat.AlwaysDisplay"];
    NSString *msg = nil;
    if (song && ([song isLastFmRadio] || alwaysDisplay) && IMPersonStatusAvailable == [IMService myStatus]) {
        msg = [NSString stringWithFormat:@"%@ - %@", [song title], [song artist]];
    } else if (!song && msgChanged && IMPersonStatusAvailable == [IMService myStatus]) {
        msg = NSLocalizedString(@"Not Listening", "");
        msgChanged = NO;
    }
    
    if (msg) {
        [previousMsg release];
        previousMsg = [[NSString alloc] initWithFormat:@"%C %@", 0x266B, msg];
        [[IMServiceAgent sharedAgent] setMyStatus:[IMService myStatus] message:previousMsg];
        msgChanged = YES;
    } else
        msgChanged = NO;
}

- (void)handleIMStatusChange:(NSNotification*)note
{
    if (currentSong)
        [self setStatusMessageWithSong:currentSong];
}

- (void)nowPlaying:(NSNotification*)note
{
    [currentSong release];
    currentSong = [note object];
    [self setStatusMessageWithSong:currentSong];
}

// ISPlugin protocol

- (id)initWithAppProxy:(id<ISPluginProxy>)proxy
{
    self = [super init];
    mProxy = proxy;
    
    // Initialize IMService
    (void)[IMService allServices];
    [[IMService notificationCenter] addObserver:self selector:@selector(handleIMStatusChange:)
        name:IMServiceStatusChangedNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowPlaying:)
        name:[proxy nowPlayingNotificationName] object:nil];
    return (self);
}

- (NSString*)description
{
    return (NSLocalizedString(@"Chat Status Plugin", ""));
}

- (void)applicationWillTerminate
{

}

@end