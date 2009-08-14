//
//  ISArtistDetailsController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 3/5/06.
//  Copyright 2006,2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ASXMLFile;

@interface ISArtistDetailsController : NSObject
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
<NSWindowDelegate>
#endif
{
    IBOutlet id artistController, similarArtistsController;
    IBOutlet NSDrawer *detailsDrawer;
    IBOutlet NSProgressIndicator *detailsProgress;
    IBOutlet NSImageView *artistImage;
    IBOutlet NSTableView *similarArtistsTable;
    NSWindow *window;
    
    ASXMLFile *detailsProfile, *detailsTopArtists,
        *detailsTopFans, *detailsSimArtists, *detailsArtistTags;
    NSMutableDictionary *detailsData;
    NSURLConnection *detailsArtistData;
    NSURLDownload *imageRequest;
    NSString *imagePath;
    int detailsToLoad, detailsLoaded;
    int requestCacheSeconds;
    unsigned delayedLoadSeed;
    id delegate;
    BOOL detailsOpen, songDetails;
}

+ (ISArtistDetailsController*)artistDetailsWithDelegate:(id)obj;
#ifdef notyet
+ (ISArtistDetailsController*)songDetailsWithDelegate:(id)obj;
#endif

- (IBAction)openDetails:(id)sender;
- (IBAction)closeDetails:(id)sender;

- (void)setArtist:(NSString*)artist;
#ifdef notyet
- (void)setSong:(SongData*)song;
#endif

@end

@interface ISArtistDetailsController (ISDetailsDelegate)

- (NSString*)detailsFrameSaveName; //must respond
- (NSString*)detailsWindowTitlePrefix; // optional

@end
