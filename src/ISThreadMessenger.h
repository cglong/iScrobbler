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
@interface ISThreadMessenger : NSObject
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
<NSPortDelegate>
#endif
{
    NSPort *port;
    NSMutableArray *msgQueue;
    NSLock *msgQLock;
    id delegate;
}

// delegate will receive all thread messages
+ (ISThreadMessenger*)scheduledMessengerWithDelegate:(id)mDelegate;

+ (void)makeTarget:(ISThreadMessenger*)target performSelector:(SEL)selector withObject:(id)object;

- (NSPort*)port;

@end
