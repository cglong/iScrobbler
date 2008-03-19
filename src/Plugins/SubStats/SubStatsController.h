//
//  SubStatsController.h
//  iScrobbler Plugin
//
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import <Cocoa/Cocoa.h>

@interface SubStatsController : NSWindowController {
    IBOutlet NSView *statsView;
    IBOutlet NSTextField *subCount;
    IBOutlet NSTextField *lastTrack;
    IBOutlet NSTextField *queueCount;
    IBOutlet NSTextField *lastfmResponse;
}

+ (SubStatsController*)sharedInstance;

@end

#define ISSUBSTATS_WINDOW_OPEN @"builtin.SubStats.WindowOpen"
