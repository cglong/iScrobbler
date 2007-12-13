//
//  ISStatusItemView.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/25/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ISStatusItem;

@interface ISStatusItemView : NSView {
    NSString *title;
    NSDictionary *attrs;
    ISStatusItem *sitem;
    NSMenu *menu;
    BOOL menuIsShowing;
}

- (id)initWithController:(ISStatusItem*)item menu:(NSMenu*)m;

- (NSString*)title;
- (NSDictionary*)titleAttributes;
- (void)setTitle:(NSString*)s;
- (void)setAttributedTitle:(NSAttributedString*)s;
- (BOOL)menuIsShowing;

@end
