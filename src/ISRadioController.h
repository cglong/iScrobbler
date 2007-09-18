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
}

+ (ISRadioController*)sharedInstance;

- (void)setRootMenu:(NSMenuItem*)menu;

//- (BOOL)isPlaying;
- (void)skip;
- (void)ban;
- (void)stop;

@end
