//
//  ISThreadMessenger.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/16/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISThreadMessenger.h"

typedef struct ISThreadMsg {
    SEL selector;
    id arg1;
} ISThreadMsg;

@implementation ISThreadMessenger

- (ISThreadMessenger*)initScheduledWithDelegate:(id)mDelegate
{
    [super init];
    delegate = mDelegate;
    
    port = [[NSPort port] retain];
    [port setDelegate:self];
    [[NSRunLoop currentRunLoop] addPort:port forMode:NSDefaultRunLoopMode];
    
    return (self);
}

+ (ISThreadMessenger*)scheduledMessengerWithDelegate:(id)mDelegate
{
    return ([[[ISThreadMessenger alloc] initScheduledWithDelegate:mDelegate] autorelease]);
}

+ (void)makeTarget:(ISThreadMessenger*)target performSelector:(SEL)selector withObject:(id)object
{
    NSPortMessage *portMsg;
    NSData *msg;
    
    ISThreadMsg *thm = calloc(1, sizeof(ISThreadMsg));
    thm->selector = selector;
    thm->arg1 = object ? [object retain] : nil;
    msg = [NSData dataWithBytes:&thm length:sizeof(void*)];
    portMsg = [[NSPortMessage alloc] initWithSendPort:[target port] receivePort:nil
        components:[NSMutableArray arrayWithObject:msg]];
    
    [portMsg sendBeforeDate:[NSDate distantFuture]];
	[portMsg release];
}

- (NSPort*)port
{
    return (port);
}

- (void)handlePortMessage:(NSPortMessage*)portMsg
{
    ISASSERT([portMsg sendPort] == port, "invalid port!");
    
    NSData *msg = [[portMsg components] objectAtIndex:0];
    ISThreadMsg *thm = *((ISThreadMsg**)[msg bytes]);

    // make the delivery
    [delegate performSelector:thm->selector withObject:thm->arg1];

    [thm->arg1 release];
    free(thm); // release our message that we malloc'd in [makeTarget:...]
}

- (void)dealloc
{
    [port release];
    [super dealloc];
}

@end

