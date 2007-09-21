//
//  ISRadioController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/16/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@interface ISRadioController : NSObject {
    NSMenuItem *rootMenu;
    NSDictionary *stationBeingTuned;
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
