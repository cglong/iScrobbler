//
//  ISBusyView.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 4/30/08.
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <QuartzCore/QuartzCore.h>

#import "ISBusyView.h"

@implementation ISBusyView

- (void)setStringValue:(NSString*)str
{
    [busyText setStringValue:str];
}

- (void)viewDidMoveToWindow
{
    if ([self window]) {
        [spinner startAnimation:self];
    } else{
        [spinner stopAnimation:self];
        [busyText setStringValue:@""];
        //[busyText hide:self];
    }
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    
    return (self);
}

- (void)awakeFromNib
{
    LEOPARD_BEGIN
    [self setWantsLayer:YES];
    [spinner setAlphaValue:.80];
    transitionDuration = .75;
    
    CIFilter *filter = [CIFilter filterWithName:@"CIDissolveTransition"];
    CATransition *inEffect = [CATransition animation];
    [inEffect setType:kCATransitionFade];
    [inEffect setFillMode:kCAFillModeForwards];
    [inEffect setFilter:filter];
    [inEffect setDuration:transitionDuration];
    CATransition *outEffect = [CATransition animation];
    [outEffect setType:kCATransitionFade];
    [outEffect setFillMode:kCAFillModeRemoved];
    [outEffect setFilter:filter];
    [outEffect setDuration:transitionDuration];
    NSDictionary *viewAnimations = [[NSDictionary alloc] initWithObjectsAndKeys:
        inEffect, NSAnimationTriggerOrderIn,
        outEffect, NSAnimationTriggerOrderOut,
        nil];
    
    [self setAnimations:viewAnimations];
    filter = [CIFilter filterWithName:@"CIGaussianBlur" keysAndValues:
        kCIInputRadiusKey, [NSNumber numberWithFloat:3.0], nil];
    
    [self setBackgroundFilters:[NSArray arrayWithObjects:filter, nil]];
    [[self layer] setNeedsDisplayOnBoundsChange:YES];
    [self setAlphaValue:1.0];
    
    gradient = [[NSGradient alloc] initWithColors:
        [NSArray arrayWithObjects:
            [NSColor colorWithCalibratedWhite:1.0 alpha:0.10],
            [NSColor colorWithCalibratedWhite:0.20 alpha:0.05],
            nil]];
    LEOPARD_END
    
    [busyText setStringValue:@""];
    [busyText setTextColor:[NSColor colorWithCalibratedWhite:0.20 alpha:0.85]];
    [busyText setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
    [busyText setAlignment:NSCenterTextAlignment];
}

- (void)dealloc
{
    [gradient release];
    [super dealloc];
}

- (void)drawRect:(NSRect)rect
{
    LEOPARD_BEGIN
    //[[NSColor colorWithCalibratedWhite:0.0 alpha:0.15] set];
    //NSRectFill(rect);
    [gradient drawInRect:rect angle:270.0];
    LEOPARD_END
}

@end
