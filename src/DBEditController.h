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
    IBOutlet NSView *contentView;
    IBOutlet NSProgressIndicator *progress;
    
    NSManagedObjectContext *moc;
    NSManagedObjectID *moid;
    BOOL isBusy;
}

- (void)setObject:(NSDictionary*)objectInfo;

- (IBAction)performClose:(id)sender;

@end

@interface DBRenameController : DBEditController {
    IBOutlet NSTextField *renameText;
}

- (IBAction)performRename:(id)sender;

@end

@interface DBRemoveController : DBEditController {
    IBOutlet NSArrayController *playEvents;
    
    NSMutableArray *playEventsContent;
    NSMutableDictionary *playEventBeingRemoved;
}

- (IBAction)performRemove:(id)sender;

@end
