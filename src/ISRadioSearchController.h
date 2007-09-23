//
//  ISRadioSearchController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/20/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ASXMLFile;
@class LNSSourceListView;

@interface ISRadioSearchController : NSWindowController {
    IBOutlet NSSplitView *splitView;
    IBOutlet LNSSourceListView *sourceList;
    IBOutlet id placeholderView;
    IBOutlet NSTreeController *sourceListController;
    
    IBOutlet NSView *searchView;
    IBOutlet NSTextField *searchText;
    IBOutlet NSButton *searchButton;
    IBOutlet NSProgressIndicator *searchProgress;
    
    NSMutableDictionary *search, *tags, *friends, *neighbors, *history;
    ASXMLFile *friendsConn, *neighborsConn, *tagsConn;
    id currentSearchType;
}

+ (ISRadioSearchController*)sharedController;

- (IBAction)search:(id)sender;

@end
