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

@class ISThreadMessenger;

@interface TopListsController : NSWindowController
{
    IBOutlet id topArtistsController;
    IBOutlet id topTracksController;
    IBOutlet id sessionController;
    IBOutlet NSTableView *topArtistsTable;
    IBOutlet NSTableView *topTracksTable;
    IBOutlet NSTabView *tabView;
    
    NSMutableDictionary *toolbarItems;
    NSMutableArray *rpcreqs;
    id artistDetails;
    // Persistence support
    ISThreadMessenger *persistenceTh;
    NSTimer *rearrangeTimer;
    int sessionLoads, cancelLoad, wantLoad;
    BOOL windowIsVisisble;
}

+ (TopListsController*) sharedInstance;

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
