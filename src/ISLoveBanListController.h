//
//  ISLoveBanListController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/11/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ASXMLFile;

#define ISLoveBanListDidEnd @"ISLoveBanListDidEnd"

@interface ISLoveBanListController : NSWindowController {
    IBOutlet NSArrayController *loved;
    IBOutlet NSArrayController *banned;
    IBOutlet NSTableView *lovedTable;
    IBOutlet NSTableView *bannedTable;
    IBOutlet NSProgressIndicator *progress;
    IBOutlet NSButton *reverse;
    
    ASXMLFile *loveConn, *banConn;
    id rpcreq;
}

+ (ISLoveBanListController*)sharedController;

- (IBAction)performClose:(id)sender;
- (IBAction)unLoveBanTrack:(id)sender;

@end
