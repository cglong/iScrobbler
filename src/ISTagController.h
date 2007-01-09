//
//  ISTagController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/9/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Cocoa/Cocoa.h>

typedef enum {
    tt_track = 0,
    tt_artist,
    tt_album
} ISTypeToTag_t;

typedef enum {
    tt_append = 0,
    tt_overwrite,
} ISTaggingMode_t;

#define ISTagDidEnd @"ISTagDidEnd" 

@interface ISTagController : NSWindowController {
    IBOutlet NSArrayController *userTags;
    IBOutlet NSArrayController *globalTags;
    IBOutlet NSProgressIndicator *progress;
    
    int what, mode, lastGlobalTags;
    NSString *tagData;
    NSMutableData *responseData;
    NSURLConnection *userConn, *globalConn;
    id representedObj;
    BOOL send;
}

- (IBAction)ok:(id)sender;

- (NSArray*)tags;
- (ISTypeToTag_t)type;
- (ISTaggingMode_t)editMode;
- (BOOL)send;

// Object is retained and possibly interpreted as SongData
- (id)representedObject;
- (void)setRepresentedObject:(id)obj;

@end
