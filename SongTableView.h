//
//  SongTableView.h
//
//  Created by Sam Ley on Wed Mar 19 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface SongTableView : NSTableView
{
    IBOutlet id MainController;
}

- (void) drawStripesInRect:(NSRect)clipRect;

@end
