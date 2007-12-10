//
//  ISTagController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/9/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

enum {
    tt_track = 0,
    tt_artist,
    tt_album
};
typedef NSInteger ISTypeToTag_t;

typedef enum {
    tt_append = 0,
    tt_overwrite,
} ISTaggingMode_t;

#define ISTagDidEnd @"ISTagDidEnd" 

@class ASXMLFile;

@interface ISTagController : NSWindowController {
    IBOutlet NSArrayController *userTags;
    IBOutlet NSArrayController *globalTags;
    IBOutlet NSProgressIndicator *progress;
    
    int what, mode, lastGlobalTags;
    NSString *tagData;
    ASXMLFile *userConn, *globalConn;
    id representedObj;
    BOOL send, artistEnabled, trackEnabled, albumEnabled;
}

- (IBAction)ok:(id)sender;

- (NSArray*)tags;
- (ISTypeToTag_t)type;
- (void)setType:(ISTypeToTag_t)newtype;
- (ISTaggingMode_t)editMode;
- (BOOL)send;

- (void)setArtistEnabled:(BOOL)enabled;
- (void)setTrackEnabled:(BOOL)enabled;
- (void)setAlbumEnabled:(BOOL)enabled;

// Object is retained and possibly interpreted as SongData
- (id)representedObject;
- (void)setRepresentedObject:(id)obj;

@end
