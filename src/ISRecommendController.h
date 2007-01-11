//
//  ISRecommendController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/8/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Cocoa/Cocoa.h>

typedef enum {
    rt_track = 0,
    rt_artist,
    rt_album
} ISTypeToRecommend_t;

#define ISRecommendDidEnd @"ISRecommendDidEnd" 

@interface ISRecommendController : NSWindowController {
    IBOutlet NSArrayController *friends;
    IBOutlet NSProgressIndicator *progress;
    
    int what;
    NSString *toUser;
    NSString *msg;
    NSMutableData *responseData;
    NSURLConnection *conn;
    id representedObj;
    BOOL send;
}

- (IBAction)ok:(id)sender;

- (NSString*)who;
- (NSString*)message;
- (ISTypeToRecommend_t)type;
- (BOOL)send;

// Object is retained, but not interpreted in anyway
- (id)representedObject;
- (void)setRepresentedObject:(id)obj;

@end