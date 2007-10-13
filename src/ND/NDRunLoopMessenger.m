/*
 *  NDRunLoopMessenger.m
 *  RunLoopMessenger
 *
 *  Created by Nathan Day on Fri Feb 08 2002.
 *  Copyright (c) 2002 Nathan Day. All rights reserved.
 */

#import "NDRunLoopMessenger.h"

static NSString		* kThreadDictionaryKey = @"NDRunLoopMessengerInstance";
static NSString		* kSendMessageException = @"NDRunLoopMessengerSendException",
							* kConnectionDoesNotExistsException = @"NDRunLoopMessengerConnectionNoLongerExistsException";
/*
 * struct message
 */
struct message
{
	NSConditionLock		* resultLock;
	NSInvocation			* invocation;
};

/*
 * function sendData
 */
void sendData( NSData * aData, NSPort * aPort );

/*
 * interface NDRunLoopMessengerForwardingProxy
 */
@interface NDRunLoopMessengerForwardingProxy : NSProxy
{
	id								targetObject;
	NDRunLoopMessenger		* owner;
	BOOL							withResult;
}
- (id)_initWithTarget:(id)aTarget withOwner:(NDRunLoopMessenger *)anOwner withResult:(BOOL)aFlag;
- (void)forwardInvocation:(NSInvocation *)anInvocation;
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
@end

/*
 * interface NDRunLoopMessenger
 */
@interface NDRunLoopMessenger (Private)
- (void)createPortForRunLoop:(NSRunLoop *)aRunLoop;
- (void)registerNotificationObservers;
@end

/*
 * class NDRunLoopMessenger
 */
@implementation NDRunLoopMessenger

void sendData( NSData * aData, NSPort * aPort );

/*
 * +runLoopMessengerForThread
 */
+ (NDRunLoopMessenger *)runLoopMessengerForThread:(NSThread *)aThread
{
	return [[aThread threadDictionary] objectForKey:kThreadDictionaryKey];
}

/*
 * +runLoopMessengerForCurrentRunLoop
 */
+ (id)runLoopMessengerForCurrentRunLoop
{
	NDRunLoopMessenger		* theCurentRunLoopMessenger;
	
	theCurentRunLoopMessenger = [self runLoopMessengerForThread:[NSThread currentThread]];
	if( theCurentRunLoopMessenger == nil )
		theCurentRunLoopMessenger = [[NDRunLoopMessenger alloc] init];

	return theCurentRunLoopMessenger;
}

/*
 * init
 */
- (id)init
{
	if( self = [super init] )
	{
		NSMutableDictionary		* theThreadDictionary;
		id								theOneForThisThread;

		theThreadDictionary = [[NSThread currentThread] threadDictionary];
		if( theOneForThisThread = [theThreadDictionary objectForKey:kThreadDictionaryKey] )
		{
			[self release];
			self = theOneForThisThread;
		}
		else
		{
			[self createPortForRunLoop:[NSRunLoop currentRunLoop]];
			[theThreadDictionary setObject:self forKey:kThreadDictionaryKey];
			[self registerNotificationObservers];
		}
	}

	return self;
}

/*
 * registerNotificationObservers
 */
- (void)registerNotificationObservers
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(threadWillExit:) name:NSThreadWillExitNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(portDidBecomeInvalid:) name:NSPortDidBecomeInvalidNotification object:port];
}

/*
 * dealloc
 */
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[[NSThread currentThread] threadDictionary] removeObjectForKey:kThreadDictionaryKey];
	[port removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[port release];
	[super dealloc];
}

/*
 * threadWillExit:
 */
- (void)threadWillExit:(NSNotification *)notification
{
	NSThread		* thread = [notification object];

	if( [[thread threadDictionary] objectForKey:kThreadDictionaryKey] == self )
	{
		[[thread threadDictionary] removeObjectForKey:kThreadDictionaryKey];
		[port removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		port = nil;
		[[NSNotificationCenter defaultCenter] removeObserver:self];
	}
}

/*
 * portDidBecomeInvalid:
 */
- (void)portDidBecomeInvalid:(NSNotification *)notification
{
	if( [notification object] == port )
	{
		[[[NSThread currentThread] threadDictionary] removeObjectForKey:kThreadDictionaryKey];
		[port removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		port = nil;
		[[NSNotificationCenter defaultCenter] removeObserver:self];
	}
}

/*
 * target:performSelector:
 */
- (void)target:(id)aTarget performSelector:(SEL)aSelector
{
	[self target:aTarget performSelector:aSelector withResult:NO];
}

/*
 * target:selector:withObject:
 */
- (void)target:(id)aTarget performSelector:(SEL)aSelector withObject:(id)anObject
{
	[self target:aTarget performSelector:aSelector withObject:anObject withResult:NO];
}

/*
 * target:performSelector:withObject:withObject:
 */
- (void)target:(id)aTarget performSelector:(SEL)aSelector withObject:(id)anObject withObject:(id)anotherObject
{
	[self target:aTarget performSelector:aSelector withObject:anObject withObject:anotherObject withResult:NO];

}

/*
 * target:performSelector:withResult:
 */
- (id)target:(id)aTarget performSelector:(SEL)aSelector withResult:(BOOL)aFlag
{
	NSInvocation		* theInvocation;
	id						theResult = nil;

	theInvocation = [NSInvocation invocationWithMethodSignature:[aTarget methodSignatureForSelector:aSelector]];

	[theInvocation setSelector:aSelector];
	[theInvocation setTarget:aTarget];
	[self messageInvocation: theInvocation withResult:aFlag];

	if( aFlag )
		[theInvocation getReturnValue:&theResult];

	return theResult;
}

/*
 * target:performSelector:withObject:withResult:
 */
- (id)target:(id)aTarget performSelector:(SEL)aSelector withObject:(id)anObject withResult:(BOOL)aFlag
{
	NSInvocation		* theInvocation;
	id						theResult = nil;

	theInvocation = [NSInvocation invocationWithMethodSignature:[aTarget methodSignatureForSelector:aSelector]];

	[theInvocation setSelector:aSelector];
	[theInvocation setTarget:aTarget];
	[theInvocation setArgument:&anObject atIndex:2];
	[self messageInvocation: theInvocation withResult:aFlag];

	if( aFlag )
		[theInvocation getReturnValue:&theResult];

	return theResult;
}

/*
 * target:performSelector:withObject:withObject:withResult:
 */
- (id)target:(id)aTarget performSelector:(SEL)aSelector withObject:(id)anObject withObject:(id)anotherObject withResult:(BOOL)aFlag
{
	NSInvocation		* theInvocation;
	id						theResult = nil;

	theInvocation = [NSInvocation invocationWithMethodSignature:[aTarget methodSignatureForSelector:aSelector]];

	[theInvocation setSelector:aSelector];
	[theInvocation setTarget:aTarget];
	[theInvocation setArgument:&anObject atIndex:2];
	[theInvocation setArgument:&anotherObject atIndex:3];
	[self messageInvocation:theInvocation withResult:aFlag];

	if( aFlag )
		[theInvocation getReturnValue:&theResult];
	
	return theResult;
}

/*
 * messageInvocation:
 */
- (void)postNotification:(NSNotification *)aNotification
{
	NSInvocation		* theInvocation;

	theInvocation = [NSInvocation invocationWithMethodSignature:[NSNotificationCenter instanceMethodSignatureForSelector:@selector(postNotification:)]];

	[theInvocation setSelector:@selector(postNotification:)];
	[theInvocation setTarget:[NSNotificationCenter defaultCenter]];
	[theInvocation setArgument:&aNotification atIndex:2];
	[self messageInvocation:theInvocation withResult:NO];
}

/*
 * messageInvocation:object:
 */
- (void)postNotificationName:(NSString *)aNotificationName object:(id)anObject
{
	[self postNotification:[NSNotification notificationWithName:aNotificationName object:anObject]];
}

/*
 * postNotificationName:object:userInfo:
 */
- (void)postNotificationName:(NSString *)aNotificationName object:(id)anObject userInfo:(NSDictionary *)aUserInfo
{
	[self postNotification:[NSNotification notificationWithName:aNotificationName object:anObject userInfo:aUserInfo]];
}

/*
 * messageInvocation:
 */
- (void)messageInvocation:(NSInvocation *)anInvocation withResult:(BOOL)aResultFlag
{
	struct message		* theMessage;
	NSMutableData		* theData;

	[anInvocation retainArguments];

	theData = [NSMutableData dataWithLength:sizeof(struct message)];
	theMessage = (struct message *)[theData mutableBytes];

	theMessage->invocation = [anInvocation retain];		// will be released by handlePortMessage
	theMessage->resultLock = aResultFlag ? [[NSConditionLock alloc] initWithCondition:NO] : nil;
	sendData( theData, port );

	if( aResultFlag )
	{
		[theMessage->resultLock lockWhenCondition:YES];
		[theMessage->resultLock unlock];
		[theMessage->resultLock release];
	}
}

/*
 * target:
 */
- (id)target:(id)aTarget;
{
	return [[[NDRunLoopMessengerForwardingProxy alloc] _initWithTarget:aTarget withOwner:self withResult:NO] autorelease];
}

/*
 * target:withResult:
 */
- (id)target:(id)aTarget withResult:(BOOL)aResultFlag;
{
	return [[[NDRunLoopMessengerForwardingProxy alloc] _initWithTarget:aTarget withOwner:self withResult:aResultFlag] autorelease];
}

/*
 * handlePortMessage:
 */
- (void)handlePortMessage:(NSPortMessage *)aPortMessage
{
	struct message 	* theMessage;
	NSData				* theData;
	void					handlePerformSelectorMessage( struct message * aMessage );
	void					handleInvocationMessage( struct message * aMessage );

	theData = [[aPortMessage components] lastObject];

	theMessage = (struct message *)[theData bytes];
	
	[theMessage->invocation invoke];
	if( theMessage->resultLock )
	{
		[theMessage->resultLock lock];
		[theMessage->resultLock unlockWithCondition:YES];
	}

	[theMessage->invocation release];	// to balance messageInvocation:withResult:
}

/*
 * createPortForRunLoop:
 */
- (void)createPortForRunLoop:(NSRunLoop *)aRunLoop
{
	port = [NSPort port];
	[port setDelegate:self];
	[port scheduleInRunLoop:aRunLoop forMode:NSDefaultRunLoopMode];
}

/*
 * sendData
 */
void sendData( NSData * aData, NSPort * aPort )
{
	NSPortMessage		* thePortMessage;

	if( aPort )
	{
		thePortMessage = [[NSPortMessage alloc] initWithSendPort:aPort receivePort:nil components:[NSArray arrayWithObject:aData]];

		if( ![thePortMessage sendBeforeDate:[NSDate distantFuture]] )
			[NSException raise:kSendMessageException format:@"An error occured will trying to send the message data %@", [aData description]];

		[thePortMessage release];
	}
	else
	{
		[NSException raise:kConnectionDoesNotExistsException format:@"The connection to the runLoop does not exist"];
	}
}


@end

/*
 * class NDRunLoopMessengerForwardingProxy
 */
@implementation NDRunLoopMessengerForwardingProxy

/*
 * _initWithTarget:withOwner:withResult:
 */
- (id)_initWithTarget:(id)aTarget withOwner:(NDRunLoopMessenger *)anOwner withResult:(BOOL)aFlag
{
	if( aTarget && anOwner )
	{
		targetObject = [aTarget retain];
		owner = [anOwner retain];
		withResult = aFlag;
	}
	else
	{
		[self release];
		self = nil;
	}

	return self;
}

/*
 * dealloc
 */
- (void)dealloc
{
	[targetObject release];
	[owner release];
}

/*
 * forwardInvocation:
 */
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
	[anInvocation setTarget:targetObject];
	[owner messageInvocation:anInvocation withResult:withResult];
}

/*
 * methodSignatureForSelector:
 */
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
	return [[targetObject class] instanceMethodSignatureForSelector:aSelector];
}

@end