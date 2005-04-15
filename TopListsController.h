//
//  TopListsController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/23/04.
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
}

+ (TopListsController*) sharedInstance;


@end

@interface TopListsController (ISProfileReportAdditions)

- (IBAction)createProfileReport:(id)sender;

- (NSData*)generateHTMLReportWithCSSURL:(NSURL*)cssURL withTitle:(NSString*)profileTitle;

@end

#define OPEN_TOPLISTS_WINDOW_AT_LAUNCH @"TopLists Window Open"
