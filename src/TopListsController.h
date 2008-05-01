//
//  TopListsController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/23/05.
//  Copyright 2005,2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ISThreadMessenger;
@class PersistentProfile;
@class ISSearchArrayController;
@class ISBusyView;

@interface TopListsController : NSWindowController
{
    IBOutlet ISSearchArrayController *topArtistsController;
    IBOutlet ISSearchArrayController *topTracksController;
    IBOutlet ISSearchArrayController *topAlbumsController;
    IBOutlet id sessionController;
    IBOutlet NSTableView *topArtistsTable;
    IBOutlet NSTableView *topTracksTable;
    IBOutlet NSTableView *topAlbumsTable;
    IBOutlet NSTabView *tabView;
    IBOutlet ISBusyView *busyView;
    IBOutlet NSProgressIndicator *busyProgress;
    
    NSMutableDictionary *toolbarItems;
    NSMutableArray *rpcreqs;
    id artistDetails;
    // Persistence support
    PersistentProfile *persistence;
    ISThreadMessenger *persistenceTh;
    int sessionLoads, cancelLoad, wantLoad, loadIssued;
    BOOL windowIsVisisble;
}

+ (TopListsController*)sharedInstance;
+ (BOOL)isActive;
+ (BOOL)willCreateNewProfile;

- (PersistentProfile*)persistence;

@end

@interface TopListsController (ISProfileReportAdditions)

- (IBAction)createProfileReport:(id)sender;
- (NSData*)generateHTMLReportWithCSSURL:(NSURL*)cssURL withTitle:(NSString*)profileTitle;

@end

@interface TopListsController (ISArtistDetails)

- (void)artistSelectionDidChange:(NSNotification*)note;

- (IBAction)openDetails:(id)sender;
- (IBAction)closeDetails:(id)sender;
- (void)setDetails:(NSMutableDictionary*)details;

@end

#define OPEN_TOPLISTS_WINDOW_AT_LAUNCH @"TopLists Window Open"
