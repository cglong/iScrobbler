//
//  ASWebServices.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 2/8/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "ASWebServices.h"
#import "ProtocolManager.h"
#import "iScrobblerController.h"
#import "keychain.h"
#import "ASXMLFile.h"

static BOOL needHandshake = YES;
static float handshakeDelay = 60.0f;

#define sessionid [sessionvars objectForKey:@"session"]

static NSURLConnection *hsConn = nil, *tuneConn = nil, *execConn = nil;
static NSMutableDictionary *connData = nil;
static ASXMLFile *xspfReq = nil;

#define POSE_AS_LASTFM

#ifdef POSE_AS_LASTFM
#define WS_VERSION @"1.4.1.57486"
#define WS_PLATFORM @"mac"
#else
#define WS_VERSION [[NSUserDefaults standardUserDefaults] stringForKey:@"version"]
#define WS_PLATFORM [[NSUserDefaults standardUserDefaults] stringForKey:@"clientid"]
#endif
// XXX "jp" somehow indicates the radio is hidden?
// [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode]
#define WS_LANG @"en"

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
        stringByAppendingFormat:@"radio/handshake.php?version=%@&platform=%@&username=%@&passwordmd5=%@&language=%@",
            WS_VERSION,
            WS_PLATFORM,
            escapedusername,
            [[NSApp delegate] md5hash:pass],
            WS_LANG];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    ScrobTrace(@"%@", req);
    
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    
    [hsConn cancel];
    [hsConn autorelease];
    hsConn = [[NSURLConnection connectionWithRequest:req delegate:self] retain];
}

- (BOOL)needHandshake
{
    return (needHandshake);
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
    [hsConn autorelease];
    hsConn = nil;

    NSDictionary *d = [self parseWSResponse:result];
    [sessionvars release];
    sessionvars = [d retain];
    
    NSString *session = sessionid;
    if (!session || NSOrderedSame == [session caseInsensitiveCompare:@"failed"] || 32 != [session length]) {
        ScrobLog(SCROB_LOG_ERR, @"ASWS missing handshake session: (%@)", result);
        [self scheduleNextHandshakeAttempt];
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSFailedHandshake object:self];
        return;
    }
    
    needHandshake = NO;
    handshakeDelay = 60.0f;
    ScrobLog(SCROB_LOG_TRACE, @"ASWS Handshake succeeded: (%@)", sessionvars);
    [[NSNotificationCenter defaultCenter] postNotificationName:ASWSDidHandshake object:self];
}

- (NSURL*)playlistURLWithService:(NSString*)service
{
    if (!service)
        return (nil);
    
    NSString *path = [NSString stringWithFormat:@"http://%@/1.0/webclient/getresourceplaylist.php?sk=%@&url=%@&desktop=1",
        [sessionvars objectForKey:@"base_url"], sessionid, service];
   NSURL *url;
    @try {
        url = [NSURL URLWithString:path];
    } @catch (NSException *e) {
        url = nil;
        ScrobLog(SCROB_LOG_ERR, @"Exception creating URL with service '%@': %@", service, e);
    }
    
    return (!needHandshake ? url : nil);
}

- (NSURL*)radioURLWithService:(NSString*)service
{
    if (!service)
        return (nil);
    
    NSString *path = [NSString stringWithFormat:@"http://%@%@/adjust.php?session=%@&url=%@&lang=%@",
        [sessionvars objectForKey:@"base_url"], [sessionvars objectForKey:@"base_path"],
        sessionid, service, WS_LANG];
    NSURL *url;
    @try {
        url = [NSURL URLWithString:path];
    } @catch (NSException *e) {
        url = nil;
        ScrobLog(SCROB_LOG_ERR, @"Exception creating URL with service '%@': %@", service, e);
    }
    
    return (!needHandshake ? url : nil);
}

- (BOOL)isPlaylistService:(NSString*)service
{
    return (NSNotFound != [service rangeOfString:@"lastfm://playlist" options:NSCaseInsensitiveSearch].location
        || NSNotFound != [service rangeOfString:@"lastfm://track" options:NSCaseInsensitiveSearch].location
        || NSNotFound != [service rangeOfString:@"lastfm://preview" options:NSCaseInsensitiveSearch].location
        || NSNotFound != [service rangeOfString:@"lastfm://play" options:NSCaseInsensitiveSearch].location);
}

- (void)tuneStation:(NSString*)station
{
    [self stop];
    
    if (needHandshake)
        return;
    
    NSURL *url;
    if (NO == [self isPlaylistService:station]) {
        // normal radio station, we can ask for more playlist content
        canGetMoreTracks = YES;
        url = [self radioURLWithService:station];
    } else {
        // playlist or preview track - this returns xspf data immediately and we cannot ask for more content
        canGetMoreTracks = NO;
        url = [self playlistURLWithService:station];
    }
    
    if (!url) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationTuneFailed object:self];
        ScrobLog(SCROB_LOG_ERR, @"ASWS tuning failure: nil URL");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    
    ScrobLog(SCROB_LOG_TRACE, @"ASWS tuning: %@", url);
    if (canGetMoreTracks)
        tuneConn = [[NSURLConnection connectionWithRequest:req delegate:self] retain];
    else
        xspfReq = [[ASXMLFile xmlFileWithURL:url delegate:self cachedForSeconds:0] retain];
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

- (NSString*)tagStation:(NSString*)tag forUser:(NSString*)user
{
    return ([NSString stringWithFormat:@"lastfm://usertags/%@/%@",
                [user stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],
                [tag stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]);
}

- (NSString*)tagStationForCurrentUser:(NSString*)tag
{
    return ([self tagStation:tag forUser:[[ProtocolManager sharedInstance] userName]]);
}

- (NSString*)stationForGlobalTag:(NSString*)tag
{
    return ([NSString stringWithFormat:@"lastfm://globaltags/%@",
                [tag stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]);
}

- (NSString*)stationForArtist:(NSString*)artist
{
    return ([NSString stringWithFormat:@"lastfm://artist/%@",
                [artist stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]);
}

- (NSString*)stationForGroup:(NSString*)group
{
    return ([NSString stringWithFormat:@"lastfm://group/%@",
                [group stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]);
}

#ifdef notyet
- (BOOL)discovery
{
    return (discovery);
}
#endif

- (void)setDiscovery:(BOOL)state
{
    discovery = state;
}

- (BOOL)subscriber
{
    return (!needHandshake && [[sessionvars objectForKey:@"subscriber"] intValue]);
}

- (void)exec:(NSString*)command
{
    [execConn cancel];
    [execConn autorelease];
    execConn = nil;
    
    NSURL *url;
    NSString *s = [NSString stringWithFormat:@"http://%@%@/control.php?session=%@&command=%@&lang=%@",
        [sessionvars objectForKey:@"base_url"], [sessionvars objectForKey:@"base_path"], sessionid, command, WS_LANG];
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
        execConn = [[NSURLConnection connectionWithRequest:req delegate:self] retain];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSExecFailed object:self];
        ScrobLog(SCROB_LOG_ERR, @"ASWS 'exec command' failure: nil URL");
    }
}

- (void)stop
{
    [xspfReq cancel];
    [xspfReq autorelease];
    xspfReq = nil;
    
    [tuneConn cancel];
    [tuneConn autorelease];
    tuneConn = nil;
    
    [execConn cancel];
    [execConn autorelease];
    execConn = nil;
    
    [connData removeAllObjects];
    
    stopped = YES;
    canGetMoreTracks = YES;
    skipsLeft = 0;
}

- (BOOL)stopped
{
    return (stopped);
}

// radio playlist
- (void)updatePlaylist
{
    if (xspfReq) {
        ScrobLog(SCROB_LOG_TRACE, @"ASWS: xspf request already in progress");
        return;
    }
    if (!canGetMoreTracks) {
        ScrobLog(SCROB_LOG_TRACE, @"ASWS: playlist does not allow track refresh");
        return;
    }
    
    NSURL *url = [NSURL URLWithString:
        [NSString stringWithFormat:@"http://%@%@/xspf.php?sk=%@&discovery=%d&desktop=%@",
        [sessionvars objectForKey:@"base_url"], [sessionvars objectForKey:@"base_path"], sessionid,
        discovery, WS_VERSION]];
    ScrobLog(SCROB_LOG_TRACE, @"ASWS: fetching xspf");
    xspfReq = [[ASXMLFile xmlFileWithURL:url delegate:self cachedForSeconds:0] retain];
}

/*
xspf format as of 2007/11:

<playlist version="1" xmlns:lastfm="http://www.audioscrobbler.net/dtd/xspf-lastfm">
<title>+metal+Tag+Radio</title>
<creator>Last.fm</creator>
<link rel="http://www.last.fm/skipsLeft">6</link>
<trackList>
    <track>
        <location>http://play.last.fm/user/e7c6219b87c03a7f27df36dc4806ac82.mp3</location>
        <title>Living Dead Girl</title>
        <id>1070141</id>
        <album>Hellbilly Deluxe</album>
        <creator>Rob Zombie</creator>
        <duration>201000</duration>
        <image>http://images.amazon.com/images/P/B00000AEFH.01._SCMZZZZZZZ_.jpg</image>
        <lastfm:trackauth>15950</lastfm:trackauth>
        <lastfm:albumId>1414353</lastfm:albumId>
        <lastfm:artistId>5734</lastfm:artistId>        
        <link rel="http://www.last.fm/artistpage">http://www.last.fm/music/Rob+Zombie</link>
        <link rel="http://www.last.fm/albumpage">http://www.last.fm/music/Rob+Zombie/Hellbilly+Deluxe</link>
        <link rel="http://www.last.fm/trackpage">http://www.last.fm/music/Rob+Zombie/_/Living+Dead+Girl</link>
        <link rel="http://www.last.fm/buyTrackURL"></link>
        <link rel="http://www.last.fm/buyAlbumURL">http://www.last.fm/affiliate_sendto.php?link=catch&amp;prod=1414353&amp;pos=65633c2c6d40fbe9c8bf27ce82d2ca5a</link>
        <link rel="http://www.last.fm/freeTrackURL"></link>
    </track>
    ... more tracks
</tracklist>
</playlist>
*/
- (void)createRadioPlaylist:(NSXMLDocument*)xml
{
    NSMutableArray *playlist = [NSMutableArray array];
    NSArray *tracks = nil;
    NSString *errMsg = nil;
    int error = 0;
    @try {
        NSArray *trackList = [[xml rootElement] elementsForName:@"trackList"];
        if (!trackList || 1 != [trackList count]) {
            errMsg = @"ASWS: invalid xspf: missing or more than one trackList element";
        }
        tracks = [[trackList objectAtIndex:0] elementsForName:@"track"];
        if (!tracks || ![tracks count]) {
            errMsg = @"ASWS: invalid xspf: no tracks to play";
            error = 1;
        }
    } @catch (NSException *ex) {
        errMsg = [NSString stringWithFormat:@"ASWS: Exception processing xml data as xspf reply: %@", ex];
    }
    if (errMsg)
        goto playlist_error;
    
    NSEnumerator *en;
    NSXMLElement *e;
    id value;
    @try {
        en = [[[xml rootElement] elementsForName:@"link"] objectEnumerator];
        while ((e = [en nextObject])) {
            if (NSOrderedSame == [[[e attributeForName:@"rel"] stringValue]
                caseInsensitiveCompare:@"http://www.last.fm/skipsLeft"]) {
                skipsLeft = [e integerValue];
                break;
            }
        }
    } @catch (NSException *ex) {
        errMsg = [NSString stringWithFormat:@"ASWS: Exception obtaining skip count from xspf reply: %@", ex];
        goto playlist_error;
    }
    ScrobLog(SCROB_LOG_TRACE, @"ASWS: xspf loaded with %li skips left", skipsLeft);
    
    en = [tracks objectEnumerator];
    while ((e = [en nextObject])) {
        NSMutableDictionary *trackData = [NSMutableDictionary dictionary];
        @try {
        // apparently, there can be more than one location, we just take the first
        value = [[[e elementsForName:@"location"] objectAtIndex:0] stringValue];
        [trackData setObject:value forKey:ISR_TRACK_URL];
        value = [[[e elementsForName:@"title"] objectAtIndex:0] stringValue];
        [trackData setObject:value forKey:ISR_TRACK_TITLE];
        #ifdef notyet
        value = [NSNumber numberWithLong:[[[e elementsForName:@"id"] objectAtIndex:0] integerValue]];
        [trackData setObject:value forKey:ISR_TRACK_LFMID];
        #endif
        value = [e elementsForName:@"album"];
        if (value && [value count] > 0) {
            value = [[value objectAtIndex:0] stringValue];
            [trackData setObject:value forKey:ISR_TRACK_ALBUM];
        }
        value = [[[e elementsForName:@"creator"] objectAtIndex:0] stringValue];
        [trackData setObject:value forKey:ISR_TRACK_ARTIST];
        value = [NSNumber numberWithLong:[[[e elementsForName:@"duration"] objectAtIndex:0] integerValue]];
        // some tracks can have an invalid 0 duration, just set them to 3 minutes (avg of most songs)
        if (0 == [value intValue]) {
            value = [NSNumber numberWithInt:60*1000];
            ScrobLog(SCROB_LOG_WARN, @"Duration for '%@ by %@' is 0, set to 60 seconds automatically (which may be completely wrong).",
                [trackData objectForKey:ISR_TRACK_TITLE], [trackData objectForKey:ISR_TRACK_ARTIST]);
        }
        [trackData setObject:value forKey:ISR_TRACK_DURATION];
        value = [e elementsForName:@"image"];
        if (value && [value count] > 0) {
            value = [[value objectAtIndex:0] stringValue];
            [trackData setObject:value forKey:ISR_TRACK_IMGURL];
        }
        value = [[[e elementsForName:@"lastfm:trackauth"] objectAtIndex:0] stringValue];
        [trackData setObject:value forKey:ISR_TRACK_LFMAUTH];
        
        #ifdef notyet
        @try {
        value = [NSNumber numberWithLong:[[[e elementsForName:@"lastfm:albumId"] objectAtIndex:0] integerValue]];
        [trackData setObject:value forKey:ISR_TRACK_LFMALBUMID];
        value = [NSNumber numberWithLong:[[[e elementsForName:@"lastfm:artistId"] objectAtIndex:0] integerValue]];
        [trackData setObject:value forKey:ISR_TRACK_LFMARTISTID];
        // other lastfm elements we just ignore currently:
        // lastfm:sponsored
        } @catch (NSException *exAttr) {
            ScrobLog(SCROB_LOG_TRACE, @"exception parsing xpsf lastfm attributes: %@", exAttr);
        }
        #endif
        
        [playlist addObject:trackData];
        
        } @catch (NSException *ex) {
            ScrobLog(SCROB_LOG_ERR, @"ASWS: Exception processing xspf track entry: %@ (%@)", e, ex);
        }
    }
    
    if ([playlist count] > 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSNowPlayingDidUpdate object:self userInfo:
            [NSDictionary dictionaryWithObject:playlist forKey:ISR_PLAYLIST]];
        return;
    } else
        error = 1;
    
playlist_error:
    stopped = YES;
    if (!errMsg)
        errMsg = @"ASWS xspf failure: no tracks to play!";
    ScrobLog(SCROB_LOG_ERR, errMsg);
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt:error], @"error", nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:ASWSNowPlayingFailed object:self userInfo:d];
}

- (NSInteger)playlistSkipsLeft
{
    return (skipsLeft);
}

- (void)decrementPlaylistSkipsLeft
{
    if (skipsLeft > 0)
        --skipsLeft;
}

// XML file callbacks - only used for playlist support currently
- (void)xmlFileDidFinishLoading:(ASXMLFile*)connection
{
    if (xspfReq == connection) {
        [xspfReq autorelease];
        xspfReq = nil;
        
        if (!canGetMoreTracks) {
            // we have to send a tune notification
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationDidTune object:self userInfo:nil];
            stopped = NO;
        }
        
        [self createRadioPlaylist:[connection xml]];
    }
}

- (void)xmlFile:(ASXMLFile*)connection didFailWithError:(NSError *)reason
{
    if (xspfReq == connection) {
        [xspfReq autorelease];
        xspfReq = nil;
        stopped = YES;
        
        if (!canGetMoreTracks) {
            [self stop];
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationTuneFailed object:self];
        } else
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSNowPlayingFailed object:self];
    }
}

// Connection callbacks
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)uresponse
{
    if (needHandshake) {
        NSInteger code = [(NSHTTPURLResponse*)uresponse statusCode];
        if (200 != code) {
            [connection cancel];
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSFailedHandshake object:self];
            
            NSError *err = [NSError errorWithDomain:@"HTTPErrorDomain" code:code  userInfo:nil];
            if (401 == code || 503 == code) {
                ScrobLog(SCROB_LOG_ERR, @"ASWS handshake failure: %@; retry scheduled", err);
                [self scheduleNextHandshakeAttempt];
            } else {
                ScrobLog(SCROB_LOG_ERR, @"ASWS handshake failure: %@", err);
            }
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
    ScrobLog(SCROB_LOG_ERR, @"ASWS Connection failure: %@", reason);
    [connData removeObjectForKey:[NSValue valueWithPointer:connection]];
    
    if (needHandshake) {
        stopped = YES;
        [self scheduleNextHandshakeAttempt];
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSFailedHandshake object:self];
        return;
    }
    
    if (connection == tuneConn) {
        [self stop];
        [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationTuneFailed object:self];
        ScrobLog(SCROB_LOG_ERR, @"ASWS tuning connection failure: %@", reason);
    } else if (connection == execConn) {
        [execConn autorelease];
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
        stopped = !needHandshake;
        return;
    }
    
    NSDictionary *d = [self parseWSResponse:result];
    ScrobDebug(@"((%@)) == %@", result, d);
    if (connection == tuneConn) {
        [tuneConn autorelease];
        tuneConn = nil;
        
        int err = [[d objectForKey:@"error"] intValue];
        if (!err) {
            ScrobLog(SCROB_LOG_TRACE, @"ASWS station tuned");
            stopped = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationDidTune object:self userInfo:d];
        } else {
            stopped = YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:ASWSStationTuneFailed object:self userInfo:
                [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:err], @"error", nil]];
            ScrobLog(SCROB_LOG_ERR, @"ASWS tuning failure: %@", d);
        }
        return;
    }
    
    if (connection == execConn) {
        [execConn autorelease];
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
    stopped = YES;
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

+ (NSURL*)currentUserTagsURL
{
    NSString *user = [[[ProtocolManager sharedInstance] userName]
        stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
        stringByAppendingFormat:@"user/%@/tags.xml", user];
    return ([NSURL URLWithString:url]);
}
+ (NSURL*)currentUserFriendsURL
{
    NSString *user = [[[ProtocolManager sharedInstance] userName]
        stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
        stringByAppendingFormat:@"user/%@/friends.xml", user];
    return ([NSURL URLWithString:url]);
}

+ (NSURL*)currentUserNeighborsURL
{
    NSString *user = [[[ProtocolManager sharedInstance] userName]
        stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
        stringByAppendingFormat:@"user/%@/neighbours.xml", user];
    return ([NSURL URLWithString:url]);
}

// Singleton support
- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (NSUInteger)retainCount
{
    return (NSUIntegerMax);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end
