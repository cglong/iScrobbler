//
//  ASXMLRPC.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/7/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

// Audioscrobbler XML RPC kernel

#import "ASXMLRPC.h"
#import "ProtocolManager.h"
#import "iScrobblerController.h"
#import "keychain.h"

@implementation ASXMLRPC

- (NSString*)method
{
    @try {
        return ([[[[request rootElement] elementsForName:@"methodName"] objectAtIndex:0] stringValue]);
    } @catch (id e) {
    
    }
    return (nil);
}

- (void)setMethod:(NSString*)method
{
    NSXMLElement *root = [request rootElement];
    [root addChild:[NSXMLNode elementWithName:@"methodName" stringValue:method]];
}

- (NSMutableArray*)standardParams
{
    NSMutableArray *params = [[NSMutableArray alloc] initWithCapacity:4];
    [params addObject:[[NSUserDefaults standardUserDefaults] stringForKey:@"username"]];
    [params addObject:[NSString stringWithFormat:@"%llu", (u_int64_t)[[NSDate date] timeIntervalSince1970]]];
    
    NSString *challenge = [[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler"
        account:[[NSUserDefaults standardUserDefaults] stringForKey:@"username"]];
    challenge = [[[NSApp delegate] md5hash:challenge] stringByAppendingString:[params objectAtIndex:1]];
    [params addObject:[[NSApp delegate] md5hash:challenge]];
    
    return ([params autorelease]);
}

- (void)setParameters:(NSMutableArray*)params
{
    NSXMLElement *root = [request rootElement];
    NSXMLElement *xparams = [NSXMLNode elementWithName:@"params"];
    
    NSEnumerator *en = [params objectEnumerator];
    id p;
    while ((p = [en nextObject])) {
        NSXMLElement *e = [NSXMLNode elementWithName:@"param"];
        NSXMLElement *v = [NSXMLNode elementWithName:@"value"];
        NSXMLElement *a;
        if ([p isKindOfClass:[NSArray class]]) {
            a = [NSXMLNode elementWithName:@"array"];
            NSXMLElement *d = [NSXMLNode elementWithName:@"data"];
            NSEnumerator *aen = [p objectEnumerator];
            id obj;
            while ((obj = [aen nextObject])) {
                NSXMLElement *v2 = [NSXMLNode elementWithName:@"value"];
                [v2 addChild:[NSXMLNode elementWithName:@"string" stringValue:obj]];
                [d addChild:v2];
            }
            [a addChild:d];
        } else
            a = [NSXMLNode elementWithName:@"string" stringValue:p];
        
        [v addChild:a];
        [e addChild:v];
        [xparams addChild:e];
    }
    
    [root addChild:xparams];
}

- (NSString*)response
{
    @try {
        return ([[[[[[response rootElement] elementsForName:@"params"] objectAtIndex:0]
            elementsForName:@"param"] objectAtIndex:0] stringValue]);
    } @catch (id e) {
        ScrobLog(SCROB_LOG_TRACE, @"ASXMLRPC: -Invalid repsonse- %@", response);
    }
    return (nil);
}

- (id)delegate
{
    return (adelegate);
}

- (void)setDelegate:(id)delegate
{
    if (adelegate != delegate) {
        [adelegate release];
        adelegate = [delegate retain];
    }
}

- (void)sendRequest
{
    if (!request) {
        [self connection:nil didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil]];
        return;
    }
    
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
        stringByAppendingString:@"rw/xmlrpc.php"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"text/xml" forHTTPHeaderField:@"content-type"];
    [req setHTTPMethod:@"POST"];
	[req setHTTPBody:[request XMLData]];
    
    ISASSERT(conn == nil, "connection active!");
    conn = [[NSURLConnection connectionWithRequest:req delegate:self] retain];
    ScrobLog(SCROB_LOG_TRACE, @"RPC request: %@", [[[NSString alloc] initWithData:[request XMLData] encoding:NSUTF8StringEncoding] autorelease]);
}

- (id)representedObject
{
    return (representedObj);
}

- (void)setRepresentedObject:(id)obj
{
    if (obj != representedObj) {
        [representedObj release];
        representedObj = [obj retain];
    }
}

// URLConnection callbacks

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)uresponse
{
    NSInteger code = [(NSHTTPURLResponse*)uresponse statusCode];
    if (200 != code) {
        [conn cancel];
        [conn autorelease];
        conn = nil;
        NSError *err = [NSError errorWithDomain:@"HTTPErrorDomain" code:code  userInfo:nil];
        [self connection:connection didFailWithError:err];
 
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (!responseData) {
        responseData = [[NSMutableData alloc] initWithData:data];
    } else {
        [responseData appendData:data];
    }
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)reason
{
    ScrobLog(SCROB_LOG_TRACE, @"Connection failure: %@\n", reason);
    [responseData release];
    responseData = nil;
    [response release];
    response = nil;
    
    [adelegate error:reason receivedForRequest:self];
    [conn autorelease];
    conn = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSError *err = nil;
    if (responseData) {
        response = [[NSXMLDocument alloc] initWithData:responseData
            options:0 //(NSXMLNodePreserveWhitespace|NSXMLNodePreserveCDATA)
            error:&err];
    } else
        err = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
    if (err) {
        [self connection:connection didFailWithError:err];
        return;
    }
    ScrobTrace(@"%@", [self response]);
    [responseData release];
    responseData = nil;
    
    [adelegate responseReceivedForRequest:self];
    [conn autorelease];
    conn = nil;
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return (nil);
}

- (id)init
{
    self = [super init];
    
    NSXMLElement *root = [[NSXMLElement alloc] initWithName:@"methodCall"];
    request = [[NSXMLDocument alloc] initWithRootElement:root];
    [root release];
    
    [request setVersion:@"1.0"];
    [request setCharacterEncoding:@"UTF-8"];
    
    return (self);
}

- (void)dealloc
{
    [conn cancel];
    [conn autorelease];
    [request release];
    [responseData release];
    [response release];
    [representedObj release];
    [adelegate release];
    [super dealloc];
}

@end
