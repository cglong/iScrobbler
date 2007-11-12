//
//  ISSearchArrayController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/27/2005.
//  Copyright 2005,2007 Brian Bergstrand.
//
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

@end
