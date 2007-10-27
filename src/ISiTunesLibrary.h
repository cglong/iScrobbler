//
//  ISiTunesLibrary.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/27/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ISThreadMessenger;

@interface ISiTunesLibrary : NSObject {
    ISThreadMessenger *thMsgr;
}

+ (ISiTunesLibrary*)sharedInstance;

- (NSDictionary*)load;
- (NSDictionary*)loadFromPath:(NSString*)path;
// didFinishSelector 1 arg of type (NSDictionary*). The iTunes lib is keyd on @"iTunesLib" and the context keyed on @"context"
- (void)loadInBackgroundWithDelegate:(id)delegate didFinishSelector:(SEL)selector context:(id)context;
- (void)loadInBackgroundFromPath:(NSString*)path withDelegate:(id)delegate didFinishSelector:(SEL)selector context:(id)context;

- (BOOL)copyToPath:(NSString*)path;

@end
