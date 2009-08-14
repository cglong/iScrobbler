//
//  ISSearchArrayController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/27/2005.
//  Copyright 2005,2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@interface ISSearchArrayController : NSArrayController
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
<NSTableViewDataSource,NSTableViewDelegate>
#endif
{
    IBOutlet NSSearchField *searchField;
    IBOutlet id tableView;
    NSString *searchString;
}

- (IBAction)search:(id)sender;

- (NSString *)searchString;
- (void)setSearchString:(NSString *)string;
- (BOOL)isSearchInProgress;

@end
