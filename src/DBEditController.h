//
//  DBEditController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/05/08.
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@interface DBEditController : NSWindowController {
    IBOutlet NSView *renameView;
    IBOutlet NSTextField *renameText;
    IBOutlet NSProgressIndicator *progress;
    
    NSManagedObjectContext *moc;
    NSManagedObjectID *moid;
    BOOL isBusy;
}

- (void)setTrack:(NSDictionary*)trackInfo;

- (IBAction)showRenameWindow:(id)sender;

- (IBAction)performClose:(id)sender;
- (IBAction)performRename:(id)sender;

@end
