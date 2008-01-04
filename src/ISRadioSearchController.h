//
//  ISRadioSearchController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/20/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ASXMLFile;

@interface ISRadioSearchController : NSWindowController {
    IBOutlet NSSplitView *splitView;
    IBOutlet NSOutlineView *sourceList;
    IBOutlet id placeholderView;
    IBOutlet NSTreeController *sourceListController;
    
    IBOutlet NSView *searchView;
    IBOutlet NSTextField *searchText;
    IBOutlet NSButton *searchButton;
    IBOutlet NSProgressIndicator *searchProgress;
    IBOutlet NSButton *searchOption;
    IBOutlet NSView *busyView;
    IBOutlet NSProgressIndicator *busyIndicator;
    
    NSView *activeViewBeforeBusy;
    NSMutableDictionary *search, *tags, *friends, *neighbors, *history;
    ASXMLFile *friendsConn, *neighborsConn, *tagsConn;
    id currentSearchType;
}

+ (ISRadioSearchController*)sharedController;

- (IBAction)search:(id)sender;

@end
