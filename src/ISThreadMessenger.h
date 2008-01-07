//
//  ISThreadMessenger.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/16/2007.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

ISEXPORT_CLASS
@interface ISThreadMessenger : NSObject {
    NSPort *port;
    id delegate;
}

// delegate will receive all thread messages
+ (ISThreadMessenger*)scheduledMessengerWithDelegate:(id)mDelegate;

+ (void)makeTarget:(ISThreadMessenger*)target performSelector:(SEL)selector withObject:(id)object;

- (NSPort*)port;

@end
