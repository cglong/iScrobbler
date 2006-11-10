//
//  TopListsController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/23/05.
//  Copyright 2005 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>

@interface TopListsController : NSWindowController
{
    IBOutlet id topArtistsController;
    IBOutlet id topTracksController;
    IBOutlet NSTableView *topArtistsTable;
    IBOutlet NSTableView *topTracksTable;
    
    NSDate *startDate;
    id artistDetails;
}

+ (TopListsController*) sharedInstance;

@end

@interface TopListsController (ISProfileReportAdditions)

- (IBAction)createProfileReport:(id)sender;
- (IBAction)resetProfile:(id)sender;

- (NSData*)generateHTMLReportWithCSSURL:(NSURL*)cssURL withTitle:(NSString*)profileTitle;

- (void)writePersistentStore;
- (void)restorePersistentStore;

@end

@interface TopListsController (ISArtistDetails)

- (void)artistSelectionDidChange:(NSNotification*)note;

- (IBAction)openDetails:(id)sender;
- (IBAction)closeDetails:(id)sender;
- (void)setDetails:(NSMutableDictionary*)details;

@end

#define OPEN_TOPLISTS_WINDOW_AT_LAUNCH @"TopLists Window Open"
