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
    NSDate *startDate;
}

+ (TopListsController*) sharedInstance;

@end

#define OPEN_TOPLISTS_WINDOW_AT_LAUNCH @"TopLists Window Open"
