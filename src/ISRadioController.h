//
//  ISRadioController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/16/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ASWebServices;

@interface ISRadioController : NSObject {
    NSMenuItem *rootMenu;
    ASWebServices *asws;
    NSDictionary *stationBeingTuned;
    NSAppleScript *stopScript, *radioScript;
    NSMutableDictionary *activeRadioTracks;
    NSString *currentTrackID;
}

+ (ISRadioController*)sharedInstance;
- (void)setRootMenu:(NSMenuItem*)menu;

- (void)tuneStationWithName:(NSString*)name url:(NSString*)url;
- (void)skip;
- (void)ban;
- (void)stop;

- (BOOL)scrobbleRadioPlays;
- (NSArray*)history;

@end

#define ISRadioHistoryDidUpdateNotification @"ISRadioHistoryDidUpdateNotification"

#define IS_RADIO_TUNEDTO_STR NSLocalizedString(@"Tuned To", "")
#define OPEN_FINDSTATIONS_WINDOW_AT_LAUNCH @"Find Stations Window Open"
