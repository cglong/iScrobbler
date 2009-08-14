//
//  PlayHistoryController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/28/07.
//  Copyright 2007-2009 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@interface PlayHistoryController : NSWindowController
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
<NSWindowDelegate>
#endif
{
    IBOutlet NSView *contentView;
    IBOutlet NSTextField *totalPlayCount;
    IBOutlet NSArrayController *historyController;
    IBOutlet NSProgressIndicator *progress;
    
    NSManagedObjectContext *moc;
    NSDictionary *npTrackInfo;
    NSDictionary *currentTrackInfo;
    BOOL editMode;
}

+ (PlayHistoryController*)sharedController;

- (void)loadHistoryForTrack:(NSDictionary*)trackInfo;

- (IBAction)performClose:(id)sender;
- (IBAction)addHistoryEvent:(id)sender;
- (IBAction)removeHistoryEvent:(id)sender;

@end
