//
//  ISSearchArrayController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/27/2005.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>

@interface ISSearchArrayController : NSArrayController
{
    IBOutlet NSSearchField *searchField;
    IBOutlet id tableView;
    NSString *searchString;
}

- (IBAction)search:(id)sender;

- (NSString *)searchString;
- (void)setSearchString:(NSString *)string;
- (BOOL)isSearchInProgress;

// Drag and Drop support
- (BOOL)tableView:(NSTableView *)tv writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard;
- (BOOL)tableView:(NSTableView*)table acceptDrop:(id <NSDraggingInfo>)info row:(int)row
    dropOperation:(NSTableViewDropOperation)op;

@end
