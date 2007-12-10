//
//  ISStatusItem.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/25/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ISStatusItemView;

@interface ISStatusItem : NSObject {
    NSStatusItem *statusItem;
    ISStatusItemView *itemView;
    NSTimer *displayTimer;
    NSString *tip;
    NSTrackingRectTag tag;
}

- (id)initWithMenu:(NSMenu*)menu;

- (void)updateStatusWithColor:(NSColor*)color withMsg:(NSString*)msg;
- (void)updateStatus:(BOOL)opSuccess withOperation:(BOOL)opBegin withMsg:(NSString*)msg;

- (NSColor*)color; // current color
- (NSColor*)defaultStatusColor; // the color for the "default" state
- (void)setSubmissionsEnabled:(BOOL)enabled;

@end
