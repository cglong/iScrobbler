//
//  ISThreadMessenger.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/16/2007.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
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
    
    msgQLock = [[NSRecursiveLock alloc] init];
    msgQueue = [[NSMutableArray alloc] init];
    port = [[NSPort port] retain];
    [port setDelegate:self];
    [[NSRunLoop currentRunLoop] addPort:port forMode:NSDefaultRunLoopMode];
    
    return (self);
}

#define MSG_TIMEOUT 0.30
- (BOOL)processMsgQueue
{
    NSMutableArray *sent = [[NSMutableArray alloc] init];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(processMsgQueue) object:nil];
    
    [msgQLock lock];
    @try {
    
    NSEnumerator *en = [msgQueue objectEnumerator];
    NSPortMessage *portMsg;
    while ((portMsg = [en nextObject])) {
        if (YES == [portMsg sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:MSG_TIMEOUT]]) {
            [sent addObject:portMsg];
        } else
            break;
    }
    
    [msgQueue removeObjectsInArray:sent];
    
    } @catch (NSException *e) {
        [msgQLock unlock];
        @throw (e);
        return (NO);
    }
    
    BOOL sentall = 0 == [msgQueue count];
    [msgQLock unlock];
    
    ScrobLog(SCROB_LOG_TRACE, @"resent %ld thread messages", [sent count]);
    [sent release];
    
    if (!sentall)
        [self performSelector:@selector(processMsgQueue) withObject:nil afterDelay:5.0];
    
    return (sentall);
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
    portMsg = nil;
    @try {
    
    portMsg = [[NSPortMessage alloc] initWithSendPort:[target port] receivePort:nil
        components:[NSMutableArray arrayWithObject:msg]];
    
    BOOL sent;
    if ([target->msgQueue count] > 0) {
        // attempt to send all outstanding messages
        sent = [target processMsgQueue];
    } else
        sent = YES;
    
    if (sent)
        sent = [portMsg sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:MSG_TIMEOUT]];
    
    if (NO == sent) {
        [target->msgQLock lock];
        [target->msgQueue addObject:portMsg];
        [target->msgQLock unlock];
        
         ScrobLog(SCROB_LOG_INFO, @"Timeout trying to send '%@' message (%p) to background thread. The message will be tried again later.",
            NSStringFromSelector(selector), portMsg);
    }
    
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception trying to send %@ message to background thread: %@. The message has been lost.",
            NSStringFromSelector(selector), e);
    }
	[portMsg release];
}

- (NSPort*)port
{
    return (port);
}

- (void)handlePortMessage:(NSPortMessage*)portMsg
{
    ISASSERT([portMsg receivePort] == port, "invalid port!");
    
    NSData *msg = [[portMsg components] objectAtIndex:0];
    ISThreadMsg *thm = *((ISThreadMsg**)[msg bytes]);

    // make the delivery
    [delegate performSelector:thm->selector withObject:thm->arg1];

    [thm->arg1 release];
    free(thm); // release our message that we malloc'd in [makeTarget:...]
}

- (void)dealloc
{
    [[NSRunLoop currentRunLoop] removePort:port forMode:NSDefaultRunLoopMode];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [port release];
    [msgQueue release];
    [msgQLock release];
    [super dealloc];
}

@end

