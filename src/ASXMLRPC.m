//
//  ASXMLRPC.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/7/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

// Audioscrobbler XML RPC kernel

#import "ASXMLRPC.h"
#import "ProtocolManager.h"
#import "iScrobblerController.h"
#import "keychain.h"

#ifdef WSHANDSHAKE
static BOOL needHandshake = YES;
static float handshakeDelay = 60.0;
#endif

@implementation ASXMLRPC

+ (BOOL)isAvailable
{
    // 10.4+ only
    return (nil != NSClassFromString(@"NSXMLDocument"));
}

#ifdef WSHANDSHAKE
- (void)handshake:(id)obj
{
    [hstimer invalidate];
    hstimer = nil;
    
    NSString *escapedusername=[(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[[ProtocolManager sharedInstance] userName],
            NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];
    NSString *pass = [[KeyChain defaultKeyChain]  genericPasswordForService:@"iScrobbler"
        account:[[NSUserDefaults standardUserDefaults] stringForKey:@"username"]];
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS ROOT"]
        stringByAppendingFormat:@"/radio/handshake.php?version=%@&platform=%@&username=%@&passwordmd5=%@&language=%@",
            [[NSUserDefaults standardUserDefaults] stringForKey:@"version"],
            [[NSUserDefaults standardUserDefaults] stringForKey:@"clientid"],
            escapedusername,
            [[NSApp delegate] md5hash:pass],
            @"jp"]; // XXX somehow this indicates the radio is hidden?
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    ScrobTrace(@"%@", req);
    
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    
    conn = [NSURLConnection connectionWithRequest:req delegate:self];
}
#endif

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
    Class xmlNode = NSClassFromString(@"NSXMLNode");
    [root addChild:[xmlNode elementWithName:@"methodName" stringValue:method]];
}

- (NSMutableArray*)standardParams
{
    NSMutableArray *params = [[NSMutableArray alloc] initWithCapacity:4];
    [params addObject:[[NSUserDefaults standardUserDefaults] stringForKey:@"username"]];
    [params addObject:[NSString stringWithFormat:@"%qu", (u_int64_t)[[NSDate date] timeIntervalSince1970]]];
    
    NSString *challenge = [[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler"
        account:[[NSUserDefaults standardUserDefaults] stringForKey:@"username"]];
    challenge = [[[NSApp delegate] md5hash:challenge] stringByAppendingString:[params objectAtIndex:1]];
    [params addObject:[[NSApp delegate] md5hash:challenge]];
    
    return ([params autorelease]);
}

- (void)setParameters:(NSMutableArray*)params
{
    NSXMLElement *root = [request rootElement];
    Class xmlNode = NSClassFromString(@"NSXMLNode");
    NSXMLElement *xparams = [xmlNode elementWithName:@"params"];
    
    NSEnumerator *en = [params objectEnumerator];
    id p;
    while ((p = [en nextObject])) {
        NSXMLElement *e = [xmlNode elementWithName:@"param"];
        [e addChild:[xmlNode elementWithName:@"value" stringValue:p]];
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
    #ifdef WSHANDSHAKE
    if (needHandshake) {
        sendRequestAfterHS = TRUE;
        if (60.f == handshakeDelay)
            [self handshake:nil];
        return;
    }
    sendRequestAfterHS = FALSE;
    #endif
    
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
        stringByAppendingString:@"rw/xmlrpc.php"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"text/xml" forHTTPHeaderField:@"content-type"];
    [req setHTTPMethod:@"POST"];
	[req setHTTPBody:[request XMLData]];
    
    conn = [NSURLConnection connectionWithRequest:req delegate:self];
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
    int code = [(NSHTTPURLResponse*)uresponse statusCode];
    if (200 != code) {
        [connection cancel];
        conn = nil;
        NSError *err = [NSError errorWithDomain:@"HTTPErrorDomain" code:code  userInfo:nil];
        #ifdef WSHANDSHAKE
        if (!needHandshake || 401 != code) {
        #endif
            [self connection:connection didFailWithError:err];
        #ifdef WSHANDSHAKE
        } else {
            ScrobLog(SCROB_LOG_ERR, @"WS handshake failure: %@", err);
        }
        if (401 == code) {
            if (!needHandshake)
                sendRequestAfterHS = YES;
            needHandshake = YES;
            [hstimer invalidate];
            hstimer = nil;
            hstimer = [NSTimer scheduledTimerWithTimeInterval:handshakeDelay
                target:self selector:@selector(handshake:) userInfo:nil repeats:NO];
            if (handshakeDelay < 3600.0f)
                handshakeDelay += 60.0f;
        }
        #endif
    }
    #ifdef WSHANDSHAKE
    else if (needHandshake) {
        // We don't need any of the handshake session info, so just cancel
        [connection cancel];
        conn = nil;
        needHandshake = NO;
        handshakeDelay = 60.0;
        if (sendRequestAfterHS)
            [self performSelector:@selector(sendRequest) withObject:nil afterDelay:0.0];
        ScrobLog(SCROB_LOG_TRACE, @"WS Handshake succeeded");
    }
    #endif
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
    conn = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSError *err = nil;
    if (responseData) {
        Class xmlDoc = NSClassFromString(@"NSXMLDocument");
        response = [[xmlDoc alloc] initWithData:responseData
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
    conn = nil;
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return (nil);
}

- (id)init
{
    self = [super init];
    
    Class xmlElem = NSClassFromString(@"NSXMLElement");
    NSXMLElement *root = [[xmlElem alloc] initWithName:@"methodCall"];
    Class xmlDoc = NSClassFromString(@"NSXMLDocument");
    request = [[xmlDoc alloc] initWithRootElement:root];
    [root release];
    
    [request setVersion:@"1.0"];
    [request setCharacterEncoding:@"UTF-8"];
    
    return (self);
}

- (void)dealloc
{
    #ifdef WSHANDSHAKE
    [hstimer invalidate];
    #endif
    [conn cancel];
    [request release];
    [responseData release];
    [response release];
    [representedObj release];
    [adelegate release];
    [super dealloc];
}

@end
