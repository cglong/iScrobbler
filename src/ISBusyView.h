//
//  ISBusyView.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 4/30/08.
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@interface ISBusyView : NSView {
    IBOutlet NSProgressIndicator *spinner;
    IBOutlet NSTextField *busyText;
    
    NSGradient *gradient;
    CFTimeInterval transitionDuration;
}

- (void)setStringValue:(NSString*)str;

@end
