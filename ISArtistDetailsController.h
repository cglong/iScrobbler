//
//  ISArtistDetailsController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 3/5/04.
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
    
    NSURLConnection *detailsProfile, *detailsTopArtists, *detailsTopFans, *detailsSimArtists;
    NSMutableDictionary *detailsData;
    NSURLDownload *imageRequest;
    NSString *imagePath;
    int detailsToLoad, detailsLoaded;
    BOOL detailsOpen;
    id delegate;
}

+ (BOOL)canLoad; // Determine if this class can be used on the current system
+ (ISArtistDetailsController*)artistDetailsWithDelegate:(id)obj;

- (IBAction)openDetails:(id)sender;
- (IBAction)closeDetails:(id)sender;

- (void)setArtist:(NSString*)artist;

@end

@interface ISArtistDetailsController (ISDetailsDelegate)

- (NSWindow*)window; // must respond

@end
