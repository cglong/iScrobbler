//
//  ASWebServices.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 2/8/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ASWebServices.h"
#import "ProtocolManager.h"
#import "iScrobblerController.h"
#import "keychain.h"

static BOOL needHandshake = YES;
static float handshakeDelay = 60.0;

#define sessionid [sessionvars objectForKey:@"session"]

static NSURLConnection *tuneConn = nil, *npConn = nil, *execConn = nil;
static NSMutableDictionary *connData = nil;

@implementation ASWebServices : NSObject

+ (ASWebServices*)sharedInstance
{
    static ASWebServices *shared = nil;
    return (shared ? shared : (shared = [[ASWebServices alloc] init]));
}

- (NSMutableDictionary*)parseWSResponse:(NSString*)response
{
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    
    NSArray *lines = [response componentsSeparatedByString:@"\n"];
    NSEnumerator *en = [lines objectEnumerator];
    NSString *string, *key;
    NSRange r;
    while ((string = [en nextObject])) {
        if (NSNotFound == (r = [string rangeOfString:@"=" options:0]).location)
            continue;
        key = [string substringToIndex:r.location];
        string = [string substringFromIndex:r.location+1];
        if (!key || !string)
            continue;
        [d setObject:string forKey:key];
    }
    if (0 == [d count])
        [d setObject:@"-1" forKey:@"error"];
    return ([d autorelease]);
}

- (void)handshake
{
    if (!needHandshake)
        return;
    
    [sessionvars removeAllObjects];
    [hstimer invalidate];
    hstimer = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ASWSWillHandshake object:self];
    
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
            @"en"]; // XXX "jp" somehow indicates the radio is hidden?
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    ScrobTrace(@"%@", req);
    
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    
    /*conn =*/ [NSURLConnection connectionWithRequest:req delegate:self];
}

- (void)scheduleNextHandshakeAttempt
{
    if (needHandshake && hstimer)
        return;
    
    needHandshake = YES;
    [hstimer invalidate];
    hstimer = nil;
    hstimer = [NSTimer scheduledTimerWithTimeInterval:handshakeDelay
        target:self selector:@selector(handshake) userInfo:nil repeats:NO];
    if (handshakeDelay < 3600.0f)
        handshakeDelay += 60.0f;
}

- (void)completeHandshake:(NSString*)result
{
    NSDictionary *d = [self parseWSResponse:result];
    if (d) {
        [sessionvars release];
        sessionvars = [d retain];
    }
    
    if (!sessionid || ![sessionvars objectForKey:@"stream_url"]) {
        ScrobLog(SCROB_LOG_ERR, @"ASWS missing handshake session or stream_url: (%@)\n", result);
        [self scheduleNextHandshakeAttempt];
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSFailedHandshake object:self];
        return;
    }
    
    needHandshake = NO;
    handshakeDelay = 60.0;
    ScrobLog(SCROB_LOG_TRACE, @"ASWS Handshake succeeded: (%@)", sessionvars);
    [[NSNotificationCenter defaultCenter] postNotificationName:ASWSDidHandshake object:self];
}

- (NSURL*)streamURL
{
    @try {
    return (!needHandshake ? [NSURL URLWithString:[sessionvars objectForKey:@"stream_url"]] : nil);
    } @catch (id e) {}
    
    return (nil);
}

- (NSURL*)radioURLWithService:(NSString*)service
{
    NSString *path = [NSString stringWithFormat:@"http://%@%@/adjust.php?session=%@&url=%@&debug=%d",
        [sessionvars objectForKey:@"base_url"], [sessionvars objectForKey:@"base_path"],
        sessionid, service, 0];
    @try {
    return (!needHandshake ? [NSURL URLWithString:path] : nil);
    } @catch (id e) {}
    
    return (nil);
}

- (void)updateNowPlaying
{
    [npConn cancel];
    npConn = nil;
    
    NSURL *url;
    NSString *s = [NSString stringWithFormat:@"http://%@%@/np.php?session=%@&debug=%d",
        [sessionvars objectForKey:@"base_url"], [sessionvars objectForKey:@"base_path"], sessionid, 0];
    @try {
    url = [NSURL URLWithString:s];
    } @catch (id e) {
        url = nil;
    }
    
    if (url) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
            cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
        [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
        npConn = [NSURLConnection connectionWithRequest:req delegate:self];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSNowPlayingFailed object:self];
        ScrobLog(SCROB_LOG_ERR, @"ASWS 'now playing' failure: nil URL\n");
    }
}

- (void)tuneStation:(NSString*)station
{
    [tuneConn cancel];
    tuneConn = nil;
    
    if (needHandshake)
        return;
    
    NSURL *url = [self radioURLWithService:station];
    if (!url) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationTuneFailed object:self];
        ScrobLog(SCROB_LOG_ERR, @"ASWS tuning failure: nil URL\n");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    
    ScrobLog(SCROB_LOG_TRACE, @"ASWS tuning: %@", url);
    tuneConn = [NSURLConnection connectionWithRequest:req delegate:self];
}

- (NSString*)station:(NSString*)type forUser:(NSString*)user
{
    return ([NSString stringWithFormat:@"lastfm://user/%@/%@",
                [user stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], type]);
}

- (NSString*)stationForCurrentUser:(NSString*)type
{
    return ([self station:type forUser:[[ProtocolManager sharedInstance] userName]]);
}

#ifdef notyet
- (BOOL)discovery
{
    return (!needHandshake && NSOrderedSame == [[sessionvars objectForKey:@"discovery"] caseInsensitiveCompare:@"true"]);
}
#endif

- (void)setDiscovery:(BOOL)state
{
    NSURL *url = [self radioURLWithService:[NSString stringWithFormat:@"lastfm://settings/discovery/%@",
        state ? @"on" : @"off"]];
    if (!url) {
        ScrobLog(SCROB_LOG_ERR, @"ASWS discovery failure: nil URL\n");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    
    ScrobDebug(@"%@", url);
    (void)[NSURLConnection connectionWithRequest:req delegate:self];
}

- (NSDictionary*)nowPlayingInfo
{
    return (nowplaying);
}

- (BOOL)subscriber
{
    return (!needHandshake && [[sessionvars objectForKey:@"subscriber"] intValue]);
}

- (void)exec:(NSString*)command
{
    [execConn cancel];
    execConn = nil;
    
    NSURL *url;
    NSString *s = [NSString stringWithFormat:@"http://%@%@/control.php?session=%@&command=%@&debug=%d",
        [sessionvars objectForKey:@"base_url"], [sessionvars objectForKey:@"base_path"], sessionid, command, 0];
    @try {
    url = [NSURL URLWithString:s];
    } @catch (id e) {
        url = nil;
    }
    
    if (url) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
            cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
        [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
        ScrobDebug(@"%@", url);
        execConn = [NSURLConnection connectionWithRequest:req delegate:self];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSExecFailed object:self];
        ScrobLog(SCROB_LOG_ERR, @"ASWS 'exec command' failure: nil URL\n");
    }
}

- (void)stop
{
    [nowplaying release];
    nowplaying = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ASWSNowPlayingDidUpdate object:self userInfo:
        [NSDictionary dictionaryWithObjectsAndKeys:@"false", @"streaming", nil]];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)uresponse
{
    if (needHandshake) {
        int code = [(NSHTTPURLResponse*)uresponse statusCode];
        if (200 != code) {
            [connection cancel];
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSFailedHandshake object:self];
            
            NSError *err = [NSError errorWithDomain:@"HTTPErrorDomain" code:code  userInfo:nil];
            if (!needHandshake || 401 != code) {
                ;
            } else {
                ScrobLog(SCROB_LOG_ERR, @"ASWS handshake failure: %@", err);
            }
            if (401 == code)
                [self scheduleNextHandshakeAttempt];
        }
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    NSMutableData *responseData = [connData objectForKey:[NSValue valueWithPointer:connection]];
    if (!responseData) {
        responseData = [[NSMutableData alloc] initWithData:data];
        [connData setObject:responseData forKey:[NSValue valueWithPointer:connection]];
        [responseData release];
    } else {
        [responseData appendData:data];
    }
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)reason
{
    ScrobLog(SCROB_LOG_ERR, @"ASWS Connection failure: %@\n", reason);
    [connData removeObjectForKey:[NSValue valueWithPointer:connection]];
    
    if (needHandshake) {
        [self scheduleNextHandshakeAttempt];
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSFailedHandshake object:self];
        return;
    }
    
    if (connection == tuneConn) {
        tuneConn = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationTuneFailed object:self];
        ScrobLog(SCROB_LOG_ERR, @"ASWS tuning connection failure: %@\n", reason);
    } else if (connection == npConn) {
        npConn = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSNowPlayingFailed object:self];
    } else if (connection == execConn) {
        execConn = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSExecFailed object:self];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSValue *key = [NSValue valueWithPointer:connection];
    NSMutableData *responseData = [[[connData objectForKey:key] retain] autorelease];
    [connData removeObjectForKey:key];
    
    NSMutableString *result = [[[NSMutableString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
    // Remove any carriage returns (such as HTTP style \r\n)
    (void)[result replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0,[result length])];
    
    if (needHandshake) {
        [self completeHandshake:result];
        return;
    }
    
    NSDictionary *d = [self parseWSResponse:result];
    ScrobDebug(@"((%@)) == %@", result, d);
    if (connection == tuneConn) {
        tuneConn = nil;
        
        int err = [[d objectForKey:@"error"] intValue];
        if (!err) {
            ScrobLog(SCROB_LOG_TRACE, @"ASWS station tuned\n");
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationDidTune object:self];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationTuneFailed object:self];
            ScrobLog(SCROB_LOG_ERR, @"ASWS tuning failure: %@\n", d);
        }
        return;
    }
    
    if (connection == npConn) {
        npConn = nil;
        
        [nowplaying release];
        nowplaying = nil;
        
        if (NSOrderedSame == [[d objectForKey:@"streaming"] caseInsensitiveCompare:@"true"]) {
            nowplaying = [d retain];
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSNowPlayingDidUpdate object:self userInfo:d];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSNowPlayingFailed object:self];
            ScrobLog(SCROB_LOG_ERR, @"ASWS now playing failure: not streaming\n", d);
        }
        
        return;
    }
    
    if (connection == execConn) {
        execConn = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSExecDidComplete object:self userInfo:nil];
        return;
    }
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return (nil);
}

- (id)init
{
    self = [super init];
    sessionvars = [[NSMutableDictionary alloc] init];
    connData = [[NSMutableDictionary alloc] init];
    return (self);
}

#ifdef notyet
- (void)dealloc
{
    [sessionvars release];
    [hstimer invalidate];
    [super dealloc];
}
#endif

// Singleton support
- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (unsigned)retainCount
{
    return (UINT_MAX);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end
