//
//  StatisticsController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/18/04.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>

@interface StatisticsController : NSWindowController
{
    IBOutlet id values;
}

+ (StatisticsController*) sharedInstance;

@end

#define OPEN_STATS_WINDOW_AT_LAUNCH @"iScrobbler Statistics Window Open"
