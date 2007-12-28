//
//  PlayHistoryController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/28/07.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@interface PlayHistoryController : NSWindowController {
    IBOutlet NSView *contentView;
    IBOutlet NSArrayController *historyController;
    IBOutlet NSProgressIndicator *progress;
    
    NSManagedObjectContext *moc;
}

+ (PlayHistoryController*)sharedController;

- (void)loadHistoryForTrack:(NSDictionary*)trackInfo;

- (IBAction)performClose:(id)sender;

@end
