//
//  ISArtistDetailsController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 3/5/06.
//  Copyright 2006 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>

@interface ISArtistDetailsController : NSObject {
    IBOutlet id artistController, similarArtistsController;
    IBOutlet NSDrawer *detailsDrawer;
    IBOutlet NSProgressIndicator *detailsProgress;
    IBOutlet NSImageView *artistImage;
    IBOutlet NSTableView *similarArtistsTable;
    
    NSURLConnection *detailsProfile, *detailsTopArtists,
        *detailsTopFans, *detailsSimArtists, *detailsArtistData, *detailsArtistTags;
    NSMutableDictionary *detailsData;
    NSURLDownload *imageRequest;
    NSString *imagePath;
    int detailsToLoad, detailsLoaded;
    BOOL detailsOpen;
    id delegate;
}

+ (ISArtistDetailsController*)artistDetailsWithDelegate:(id)obj;

- (IBAction)openDetails:(id)sender;
- (IBAction)closeDetails:(id)sender;

- (void)setArtist:(NSString*)artist;

@end

@interface ISArtistDetailsController (ISDetailsDelegate)

- (NSWindow*)window; // must respond

@end
