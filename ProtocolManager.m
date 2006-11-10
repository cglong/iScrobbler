//
//  ProtocolManager.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/04.
//  Copyright 2004-2006 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <notify.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import "ProtocolManager.h"
#import "ProtocolManager+Subclassers.h"
#import "ProtocolManager_v11.h"
#import "keychain.h"
#import "QueueManager.h"
#import "SongData.h"
#import "iScrobblerController.h"

#define REQUEST_TIMEOUT 60.0
#define HANDSHAKE_DEFAULT_DELAY 60.0
/* From IRC:
   Russ​​: ...The server cuts any submission off at 1000,
   I personally recommend you don't go over 50 or 100 in a single submission */
#define DEFAULT_MAX_TRACKS_PER_SUB 50
#define MAX_MISSING_VAR_ERRORS 2

@interface ProtocolManager (Private)

- (void)handshake;
- (void)resubmit:(NSTimer*)timer;
- (void)setHandshakeResult:(NSDictionary*)result;
- (void)setSubmitResult:(NSDictionary*)result;
- (void)setLastSongSubmitted:(SongData*)song;
- (NSString*)md5Challenge;
- (NSString*)submitURL;
- (void)setIsNetworkAvailable:(BOOL)available;

@end

static ProtocolManager *g_PM = nil;
static SCNetworkReachabilityRef g_networkReachRef = nil;

static void NetworkReachabilityCallback (SCNetworkReachabilityRef target, 
    SCNetworkConnectionFlags flags, void *info);

#define NETWORK_UNAVAILABLE_MSG @"Network is not available, submissions are being queued.\n"

@implementation ProtocolManager

+ (ProtocolManager*)sharedInstance
{
    if (!g_PM) {
        if ([@"1.1" isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"protocol"]])
            g_PM = [[ProtocolManager_v11 alloc] init];
        else if ([@"1.2" isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"protocol"]])
            g_PM = [[ProtocolManager_v11 alloc] init];
        else
            ScrobLog(SCROB_LOG_CRIT, @"Unknown protocol version\n");
    }
    return (g_PM);
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if (g_PM == nil) {
            return ([super allocWithZone:zone]);
        }
    }

    return (g_PM);
}

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

- (void)scheduleHandshake:(NSTimer*)timer
{
    handshakeTimer = NULL;
    if (hs_delay == hsState) {
        hsState = hs_needed;
        ScrobLog(SCROB_LOG_VERBOSE, @"Re-trying handshake after delay...\n");
        [self handshake];
    }
}

- (void)killHandshake:(NSTimer*)timer
{
    NSURLConnection *h = [[timer userInfo] objectForKey:@"Handle"];
    killTimer = nil;
    
    if (hs_inprogress == hsState) {
        // Kill handshake that seems to be stuck
        [h cancel];
        // Reset state and try again
        hsState = hs_needed;
        ScrobLog(SCROB_LOG_INFO, @"Stopped runaway handshake. Trying again...\n");
        [self handshake];
    }
}

- (void)completeHandshake:(NSData *)data
{
	NSMutableString *result = [[[NSMutableString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    // Remove any carriage returns (such as HTTP style \r\n -- which killed us during a server upgrade)
    (void)[result replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0,[result length])];
	
    [killTimer invalidate];
    killTimer = nil;
    
	ScrobLog(SCROB_LOG_VERBOSE, @"Handshake result: %@\n", result);
	if ([result length] == 0) {
		ScrobLog(SCROB_LOG_WARN, @"Handshake connection failed.\n");
        result = [NSMutableString stringWithString:@"FAILED Connection failed"];
	}
    
    @try {
        [self setHandshakeResult:[self handshakeResponse:result]];
    } @catch (NSException *exception) {
        result = [NSMutableString stringWithString:
            @"FAILED Internal exception caused by bad server response."];
        [self setHandshakeResult:[NSDictionary dictionaryWithObjectsAndKeys:
            HS_RESULT_FAILED, HS_RESPONSE_KEY_RESULT,
            result, HS_RESPONSE_KEY_RESULT_MSG,
            @"", HS_RESPONSE_KEY_MD5,
            @"", HS_RESPONSE_KEY_SUBMIT_URL,
            @"", HS_RESPONSE_KEY_UPDATE_URL,
            @"", HS_RESPONSE_KEY_INTERVAL,
            nil]];
    }
	
	BOOL success;
    if ((success = [self validHandshake])) {
        hsState = hs_valid;
        handshakeDelay = HANDSHAKE_DEFAULT_DELAY;
        lastAttemptBadAuth = NO; // Reset now that we have a new session.
	} else {
        if ([[self lastHandshakeResult] isEqualToString:HS_RESULT_BADAUTH]) {
            hsState = hs_needed;
            handshakeDelay = HANDSHAKE_DEFAULT_DELAY;
        } else {
            hsState = hs_delay;
            handshakeTimer = [NSTimer scheduledTimerWithTimeInterval:handshakeDelay target:self
                selector:@selector(scheduleHandshake:) userInfo:nil repeats:NO];
            handshakeDelay *= 2.0;
            if (handshakeDelay > [self handshakeMaxDelay])
                handshakeDelay = [self handshakeMaxDelay];
        }
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_HANDSHAKE_COMPLETE object:self];
    
    if (success && [[QueueManager sharedInstance] count])
        [self submit:nil];
}

- (void)handshake
{
    if (!isNetworkAvailable) {
        ScrobLog(SCROB_LOG_VERBOSE, NETWORK_UNAVAILABLE_MSG);
        return;
    }
    
    if (hs_inprogress == hsState) {
        ScrobLog(SCROB_LOG_INFO, @"Handshake already in progress...\n");
        return;
    }
    if (hs_delay == hsState) {
        ScrobLog(SCROB_LOG_VERBOSE, @"Handshake delayed. Next attempt in %0.lf seconds.\n",
            [[handshakeTimer fireDate] timeIntervalSinceNow]);
        return;
    }
    
    hsState = hs_inprogress;
    
    NSString* url = /*@"127.0.0.1"*/ [self handshakeURL];
    ScrobLog(SCROB_LOG_VERBOSE, @"Handshaking... %@", url);
    
    if (!url) {
        ScrobLog(SCROB_LOG_CRIT, @"Empty handshake URL!\n");
        hsState = hs_needed;
        return;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_HANDSHAKE_START object:self];

	NSURL *nsurl = [NSURL URLWithString:url];
	//SCrobTrace(@"nsurl: %@",nsurl);
	//ScrobTrace(@"host: %@",[nsurl host]);
	//ScrobTrace(@"query: %@", [nsurl query]);
	
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl cachePolicy:
        NSURLRequestReloadIgnoringCacheData timeoutInterval:REQUEST_TIMEOUT];
	[request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    
    NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:self];
    
    // Setup timer to kill the current handhskake and reset state
    // if we've been in progress for 5 minutes
    killTimer = [NSTimer scheduledTimerWithTimeInterval:300.0 target:self
        selector:@selector(killHandshake:)
        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:connection, @"Handle", nil]
        repeats:NO];
}

- (NSString*)clientVersion
{
    return ([prefs stringForKey:@"version"]);
}

- (NSString*)userName
{
    return ([prefs stringForKey:@"username"]);
}

- (SongData*)lastSongSubmitted
{
    return (lastSongSubmitted);
}

- (NSString *)lastHandshakeResult
{
    return ([hsResult objectForKey:HS_RESPONSE_KEY_RESULT]);
}

- (NSString *)lastHandshakeMessage
{
    return ([hsResult objectForKey:HS_RESPONSE_KEY_RESULT_MSG]);
}

- (NSString *)lastSubmissionResult
{
    return ([submitResult objectForKey:HS_RESPONSE_KEY_RESULT]);
}

- (NSString *)lastSubmissionMessage
{
    return ([submitResult objectForKey:HS_RESPONSE_KEY_RESULT_MSG]);
}

- (NSString *)updateURL
{
    return ([hsResult objectForKey:HS_RESPONSE_KEY_UPDATE_URL]);
}

- (BOOL) validHandshake
{
    NSString *result = [self lastHandshakeResult];
    
    return ([result isEqualToString:HS_RESULT_OK] ||
         [result isEqualToString:HS_RESULT_UPDATE_AVAIL]);
}

- (BOOL) updateAvailable
{
    return ([[self lastHandshakeResult] isEqualToString:HS_RESULT_UPDATE_AVAIL]);
}

- (unsigned)submissionAttemptsCount
{
    return (submissionAttempts);
}

- (unsigned)successfulSubmissionsCount
{
    return (successfulSubmissions);
}

- (void)setHandshakeResult:(NSDictionary*)result
{
    (void)[result retain];
    [hsResult release];
    hsResult = result;
}

- (void)setSubmitResult:(NSDictionary*)result
{
    (void)[result retain];
    [submitResult release];
    submitResult = result;
}

- (void)setLastSongSubmitted:(SongData*)song
{
    (void)[song retain];
    [lastSongSubmitted release];
    lastSongSubmitted = song;
    
    NSDictionary *d = [lastSongSubmitted songData];
    if (d)
        [prefs setObject:d forKey:@"LastSongSubmitted"];
}

- (NSString*)md5Challenge
{
    return ([hsResult objectForKey:HS_RESPONSE_KEY_MD5]);
}

- (NSString*)submitURL
{
    return ([hsResult objectForKey:HS_RESPONSE_KEY_SUBMIT_URL]);
}

// Defaults
- (NSString*)clientID
{
    return ([prefs stringForKey:@"clientid"]);
}

- (NSString*)userAgent
{
    static id agent = nil;
    if (agent)
        return (agent);
    
    agent = [[prefs stringForKey:@"useragent"] mutableCopy];
    
#ifdef __ppc__
    NSString *arch = @"ppc";
#elif defined(__i386__)
    NSString *arch = @"i386";
#else
#error unknown arch
#endif
    
    [agent replaceOccurrencesOfString:@"-arch-" withString:arch options:0 range:NSMakeRange(0, [agent length])];
    return (agent);
}

- (float)minPercentagePlayed
{
    return (50.0);
}

- (float)minTimePlayed
{
    return (240.0); // Four minutes
}

- (float)handshakeMaxDelay
{
    return (7200.00); // Two hours
}

- (BOOL)useBatchSubmission
{
    return ([prefs boolForKey:@"Use Batch Submission"]);
}

- (void)scheduleResubmit
{
    [resubmitTimer invalidate];
    resubmitTimer = [NSTimer scheduledTimerWithTimeInterval:nextResubmission target:self
        selector:@selector(resubmit:) userInfo:nil repeats:NO];
    // We use the handshake delay rules
    nextResubmission *= 2.0;
    if (nextResubmission > [self handshakeMaxDelay])
        nextResubmission = [self handshakeMaxDelay];
}

- (void)writeSubLogEntry:(unsigned)sid withTrackCount:(unsigned)count withData:(NSData*)data
{
    @try {
    [subLog writeData:[[NSString stringWithFormat:@"[id=%u,ct=%u,sz=%u]\n", sid, count, [data length]]
        dataUsingEncoding:NSUTF8StringEncoding]];
    [subLog writeData:data];
    [subLog writeData:[@"\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
    } @finally {}
}

// URLConnection callbacks

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	if (!myData) {
		myData = [[NSMutableData alloc] init];
	}
	[myData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)sender
{
    if (hs_inprogress == hsState) {
        [self completeHandshake:myData];
        [myData release];
        myData = nil;
        return;
    }
    
    if (hs_valid != hsState) {
        ScrobLog(SCROB_LOG_ERR, @"Internal inconsistency! Invalid Handshake state (%u)!\n", hsState);
        [self setSubmitResult:
            [NSDictionary dictionaryWithObjectsAndKeys:
            HS_RESULT_FAILED, HS_RESPONSE_KEY_RESULT,
            @"Internal inconsistency!", HS_RESPONSE_KEY_RESULT_MSG,
            nil]];
        hsState = hs_needed;
        goto didFinishLoadingExit;
    }
    
    int i;
    NSMutableString *result = [[[NSMutableString alloc] initWithData:myData encoding:NSUTF8StringEncoding] autorelease];
    // Remove any carriage returns (such as HTTP style \r\n -- which killed us during a server upgrade)
    (void)[result replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0,[result length])];
	
    //[self changeLastResult:result];
    ScrobLog(SCROB_LOG_TRACE, @"Tracks in queue after submission: %d", [[QueueManager sharedInstance] count]);
	
	ScrobLog(SCROB_LOG_VERBOSE, @"Submission result: %@", result);
    
    [self setSubmitResult:[self submitResponse:result]];
    
    // Process Body, and if OK, remove the in flight songs from the queue
    if([[self lastSubmissionResult] isEqualToString:HS_RESULT_OK])
    {
		int count = [inFlight count];
        for(i=0; i < count; i++) {
            [[QueueManager sharedInstance] removeSong:[inFlight objectAtIndex:i] sync:NO];
        }
        [[QueueManager sharedInstance] syncQueue:nil];
        ScrobLog(SCROB_LOG_TRACE, @"Queue cleaned, track count: %u", [[QueueManager sharedInstance] count]);
        nextResubmission = HANDSHAKE_DEFAULT_DELAY;
        
        // Set the new max if we detected a proxy truncation -- only done once
        if (missingVarErrorCount > MAX_MISSING_VAR_ERRORS && count > (MAX_MISSING_VAR_ERRORS * 2)
            && DEFAULT_MAX_TRACKS_PER_SUB == maxTracksPerSub)
            maxTracksPerSub = count;
        
        ++successfulSubmissions;
        missingVarErrorCount = 0;
        
        // See if there are any more entries in the queue
        if ([[QueueManager sharedInstance] count]) {
            // Schedule the next sub after a minute delay
            [self performSelector:@selector(submit:) withObject:nil afterDelay:0.5];
        }
    } else {
        ScrobLog(SCROB_LOG_INFO, @"Server error -- tracks in queue: %u", [[QueueManager sharedInstance] count]);
        if (SCROB_LOG_TRACE == ScrobLogLevel())
            [self writeSubLogEntry:submissionAttempts withTrackCount:[inFlight count] withData:myData];
        
		hsState = hs_needed;
        
		if ([[self lastSubmissionResult] isEqualToString:HS_RESULT_BADAUTH]) {
			// Send notification if we received BADAUTH twice
			if (lastAttemptBadAuth) {
				[[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_BADAUTH object:self];
			} else {
			    lastAttemptBadAuth = YES;
			}
		} else {
			lastAttemptBadAuth = NO;
            
            if ([[self lastSubmissionResult] isEqualToString:HS_RESULT_FAILED_MISSING_VARS]) {
                ++missingVarErrorCount;
            } else
                missingVarErrorCount = 0;
		}
        
        // Kick off resubmit timer
        [self scheduleResubmit];
    }
    
didFinishLoadingExit:
    [self setLastSongSubmitted:[inFlight lastObject]];
    [inFlight release];
    inFlight = nil;
    
    [myData release];
    myData = nil;
    
    myConnection = nil;
    
    if (0 != notify_post)
        notify_post("org.bergstrand.iscrobbler.didsubmit");
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self];
}

-(void)connection:(NSURLConnection *)sender didFailWithError:(NSError *)reason
{
    [myData release];
    myData = nil;
    
    // Apparently the system failure descriptions are too hard to comprehend, as every time subs go down,
    // the forum is inundated with "why did iScrobbler break?".
    NSString *why;
    switch ([reason code]) {
        case NSURLErrorTimedOut:
            why = NSLocalizedString(@"The last.fm submission server failed to respond in time.", "");
        break;
        case NSURLErrorNotConnectedToInternet:
            why = NSLocalizedString(@"Your computer does not appear to be connected to the Internet.", "");
        break;
        //NSURLErrorCannotFindHost
        //NSURLErrorCannotConnectToHost
        //NSURLErrorNetworkConnectionLost
        default:
            why = NSLocalizedString(@"The last.fm submission server failed to respond.", "");
        break;
    }
    
    if (hs_inprogress == hsState) {
        // Emulate a server error
        NSData *response = [[@"FAILED Connection failed - " stringByAppendingString:why]
            dataUsingEncoding:NSUTF8StringEncoding];
        [self completeHandshake:response];
        return;
    }
    
    [self setSubmitResult:
        [NSDictionary dictionaryWithObjectsAndKeys:
        HS_RESULT_FAILED, HS_RESPONSE_KEY_RESULT,
        why, HS_RESPONSE_KEY_RESULT_MSG,
        nil]];
	
    [self setLastSongSubmitted:[inFlight lastObject]];
    
    myConnection = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self];
    
    // Kick off resubmit timer
    [self scheduleResubmit];
    
    ScrobLog(SCROB_LOG_INFO, @"Connection error: '%@'. Tracks in queue: %u.\n",
        [reason localizedDescription], [[QueueManager sharedInstance] count]);
    if (SCROB_LOG_TRACE == ScrobLogLevel())
        [self writeSubLogEntry:submissionAttempts withTrackCount:[inFlight count]
            withData:[[reason localizedDescription] dataUsingEncoding:NSUTF8StringEncoding]];
    
    [inFlight release];
    inFlight = nil;
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return (nil); // we don't want to store any cached data on disk
}

- (void)resubmit:(NSTimer*)timer
{
    resubmitTimer = nil;
    ScrobLog(SCROB_LOG_VERBOSE, @"Trying resubmission after delay...\n");
    [self submit:nil];
}

- (void)setSubValue:(NSString*)value forKey:(NSString*)key inData:(NSMutableData*)data
{
    [data appendData:[[NSString stringWithFormat:@"%@=%@&", key, value] dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)submit:(id)sender
{	
    if (inFlight || myConnection) {
        ScrobLog(SCROB_LOG_WARN, @"Already connected to server, delaying submission...\n");
        return;
    }
    
    if (!isNetworkAvailable) {
        ScrobLog(SCROB_LOG_VERBOSE, NETWORK_UNAVAILABLE_MSG);
        return;
    }
    
    // We must execute a server handshake before
    // doing anything else. If we've already handshaked, then no
    // worries.
    if (hs_valid != hsState) {
		ScrobLog(SCROB_LOG_VERBOSE, @"Need to handshake.\n");
		[self handshake];
        return;
    }
    
    inFlight = [[[QueueManager sharedInstance] songs] sortedArrayUsingSelector:@selector(compareSongPostDate:)];
    unsigned submissionCount = [inFlight count];
    if (!submissionCount) {
        inFlight = nil;
        return;
    }
    
    if (submissionCount > 1 && ![self useBatchSubmission]) {
        submissionCount = 1;
    } else if (submissionCount > maxTracksPerSub) {
        submissionCount = maxTracksPerSub;
    }
    
    // Check if a proxy is causing problems...
    if (submissionCount > 1 && missingVarErrorCount > MAX_MISSING_VAR_ERRORS) {
        if (0 == (submissionCount /= missingVarErrorCount))
            submissionCount = 1;
            
        ScrobLog(SCROB_LOG_VERBOSE, @"Possible proxy corruption detected (%u). Batch sub reduced to %u.\n",
            missingVarErrorCount, submissionCount);
            
        ISASSERT(submissionCount <= [inFlight count], "Adjusted sub count out of range!");
    }
    
    if (submissionCount != [inFlight count])
        inFlight = [inFlight subarrayWithRange:NSMakeRange(0,submissionCount)];
    
    [resubmitTimer invalidate];
    resubmitTimer = nil;
    
    if (0 != notify_post)
        notify_post("org.bergstrand.iscrobbler.willsubmit");
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_START object:self];
    
    (void)[inFlight retain];
    NSMutableData *subData = [[NSMutableData alloc] init];

    NSString* escapedusername=[(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[prefs stringForKey:@"username"],
            NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) 	autorelease];
    
    @try {
    [self setSubValue:escapedusername forKey:@"u" inData:subData];
    
    //retrieve the password from the keychain, and hash it for sending
    NSString *pass = [[NSString alloc] initWithString:
        [myKeyChain genericPasswordForService:@"iScrobbler" account:[prefs stringForKey:@"username"]]];
    //ScrobTrace(@"pass: %@", pass);
    NSString *hashedPass = [[NSString alloc] initWithString:[[NSApp delegate] md5hash:pass]];
    [pass release];
    //ScrobTrace(@"hashedPass: %@", hashedPass);
    //ScrobTrace(@"md5Challenge: %@", md5Challenge);
    NSString *concat = [[NSString alloc] initWithString:[hashedPass stringByAppendingString:[self md5Challenge]]];
    [hashedPass release];
    //ScrobTrace(@"concat: %@", concat);
    NSString *response = [[NSString alloc] initWithString:[[NSApp delegate] md5hash:concat]];
    [concat release];
    //ScrobTrace(@"response: %@", response);
    
    [self setSubValue:response forKey:@"s" inData:subData];
    [response autorelease];
    
    // Fill the dictionary with every entry in the queue, ordering them from
    // oldest to newest.
    int i;
    for(i=0; i < submissionCount; ++i) {
        [subData appendData:[self encodeSong:[inFlight objectAtIndex:i] submissionNumber:i]];
    }
    
    NSMutableURLRequest *request =
		[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self submitURL]]
								cachePolicy:NSURLRequestReloadIgnoringCacheData
							timeoutInterval:REQUEST_TIMEOUT];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:subData];
    // Set the user-agent to something Mozilla-compatible
    [request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    
    ++submissionAttempts;
    myConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    
    ScrobLog(SCROB_LOG_INFO, @"%u song(s) submitted...\n", [inFlight count]);
    if (SCROB_LOG_TRACE == ScrobLogLevel())
        [self writeSubLogEntry:submissionAttempts withTrackCount:[inFlight count] withData:[request HTTPBody]];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception generated during submission attempt: %@\n", e);
        [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self];
        [inFlight release];
        inFlight = nil;
    } @finally {
        [subData release];
    }
}

- (NSString*)netDiagnostic
{
    NSString *msg = nil;
    if (CFNetDiagnosticCreateWithURL) { // 10.4 only
        CFNetDiagnosticRef diag = CFNetDiagnosticCreateWithURL(kCFAllocatorDefault,
            (CFURLRef)[NSURL URLWithString:[self handshakeURL]]);
        if (diag) {
            (void)CFNetDiagnosticCopyNetworkStatusPassively(diag, (CFStringRef*)&msg);
            CFRelease(diag);
        }
    }
    
    if (msg)
        (void)[msg autorelease];
    else
        msg = @"";
    return (msg);
}

- (BOOL)isNetworkAvailable
{
    return (isNetworkAvailable);
}

- (void)setIsNetworkAvailable:(BOOL)available
{
    if (isNetworkAvailable != available) {
        NSString *msg = @"", *logmsg = @"";
        if ((isNetworkAvailable = available))
            handshakeDelay = nextResubmission = HANDSHAKE_DEFAULT_DELAY;
        else {
            msg = [self netDiagnostic];
            logmsg = [NSString stringWithFormat:@" (%@)", msg];
        }
        ScrobLog(SCROB_LOG_VERBOSE, @"Network status changed. Is available? \"%@\".%@\n",
            isNetworkAvailable ? @"Yes" : @"No", logmsg);
        
        [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_NETWORK_STATUS
            object:self userInfo:
                [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithBool:available], PM_NOTIFICATION_NETWORK_STATUS_KEY,
                    msg, PM_NOTIFICATION_NETWORK_MSG_KEY,
                    nil]];
    }
}

#define IsNetworkUp(flags) \
( ((flags) & kSCNetworkFlagsReachable) && (0 == ((flags) & kSCNetworkFlagsConnectionRequired) || \
  ((flags) & kSCNetworkFlagsConnectionAutomatic)) )

- (void)didWake:(NSNotification*)note
{
    static BOOL fire = NO;
    
    if (!fire) {
        ScrobLog(SCROB_LOG_TRACE, @"Got wake event.\n");
        fire = YES;
        // network may not quite be ready yet.
        [self performSelector:@selector(didWake:) withObject:note afterDelay:7.5];
        return;
    }
    fire = NO;
    
    SCNetworkConnectionFlags connectionFlags;
    if (SCNetworkReachabilityGetFlags(g_networkReachRef, &connectionFlags) &&
         IsNetworkUp(connectionFlags)) {
        [self setIsNetworkAvailable:YES];
    } else {
        [self setIsNetworkAvailable:NO];
    }
}

- (id)init
{
    self = [super init];
    
    prefs = [[NSUserDefaults standardUserDefaults] retain];
    
    // Create raw submission log
    subLog = [ScrobLogCreate(@"iScrobblerSub.log", SCROB_LOG_OPT_SESSION_MARKER, 0x400000) retain];
    
    // We keep track of this for iPod support which uses lastSubmitted to
    // determine the timestamp used in played songs detection.
    NSDictionary *d = [prefs objectForKey:@"LastSongSubmitted"];
    if (d) {
        SongData *song = [[SongData alloc] init];
        if ([song setSongData:d]) {
            ScrobLog(SCROB_LOG_TRACE, @"Restored '%@' as last submitted song.\n", [song brief]);
            [song setStartTime:[song postDate]];
            [song setPosition:[song duration]];
            [self setLastSongSubmitted:song];
        } else
            ScrobLog(SCROB_LOG_ERR, @"Failed to restore last submitted song: %@\n", d);
        [song release];
    }
    
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"IgnoreNetworkMonitor"]) {
        g_networkReachRef = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault,
            [[[NSURL URLWithString:[self handshakeURL]] host] cString]);
        // Get the current state
        SCNetworkConnectionFlags connectionFlags;
        if (SCNetworkReachabilityGetFlags(g_networkReachRef, &connectionFlags) &&
             IsNetworkUp(connectionFlags)) {
            [self setIsNetworkAvailable:YES];
        } else {
            [self setIsNetworkAvailable:NO];
        }
        // Install a callback to get notified of iface up/down events
        SCNetworkReachabilityContext reachContext = {0};
        reachContext.info = self;
        if (!SCNetworkReachabilitySetCallback(g_networkReachRef, NetworkReachabilityCallback, &reachContext) ||
             !SCNetworkReachabilityScheduleWithRunLoop(g_networkReachRef,
                [[NSRunLoop currentRunLoop] getCFRunLoop], kCFRunLoopDefaultMode))
        {
            ScrobLog(SCROB_LOG_WARN, @"Could not create network status monitor - assuming network is always available.\n");
            isNetworkAvailable = YES;
        }
        
        // There's some bug in Tiger that cause notification events to not be sent (sometimes) on wake.
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
            selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    } else { // @"IgnoreNetworkMonitor"
        ScrobLog(SCROB_LOG_INFO, @"Ignoring network status monitor - assuming network is always available.\n");
        isNetworkAvailable = YES;
    }
    
    // Indicate that we have not yet handshaked
    hsState = hs_needed;
    handshakeDelay = nextResubmission = HANDSHAKE_DEFAULT_DELAY;
    [self setHandshakeResult:
        [NSDictionary dictionaryWithObjectsAndKeys:
        HS_RESULT_UNKNOWN, HS_RESPONSE_KEY_RESULT,
        @"No data sent yet.", HS_RESPONSE_KEY_RESULT_MSG,
        @"", HS_RESPONSE_KEY_MD5,
        @"", HS_RESPONSE_KEY_SUBMIT_URL,
        @"", HS_RESPONSE_KEY_UPDATE_URL,
        @"", HS_RESPONSE_KEY_INTERVAL,
        nil]];
    
    [self setSubmitResult:
        [NSDictionary dictionaryWithObjectsAndKeys:
        HS_RESULT_UNKNOWN, HS_RESPONSE_KEY_RESULT,
        @"No data sent yet.", HS_RESPONSE_KEY_RESULT_MSG,
        nil]];
    
    myKeyChain = [[KeyChain defaultKeyChain] retain];\
    
    maxTracksPerSub = DEFAULT_MAX_TRACKS_PER_SUB;

    // We are an abstract class, only subclasses return valid objects
    return (nil);
}

- (void)dealloc
{
    [prefs release];
    [myKeyChain release];
    [inFlight release];
    [lastSongSubmitted release];
    [hsResult release];
    [submitResult release];
    [myKeyChain release];
    [super dealloc];
}

@end

@implementation SongData (ProtocolManagerAdditions)

- (BOOL)canSubmit
{
    ProtocolManager *pm = [ProtocolManager sharedInstance];
    BOOL good = ( IsTrackTypeValid([self type])
        && ([[self duration] floatValue] >= 30.0 || [[self mbid] length] > 0)
        && ([[self percentPlayed] floatValue] > [pm minPercentagePlayed] ||
        [[self position] floatValue] > [pm minTimePlayed]) );
    if (good && !reconstituted) {
        // Make sure there was no forward seek (allowing for a little fudge time)
        // This is not perfect, so some "illegal" tracks may slip through.
        NSTimeInterval elapsed = [[self elapsedTime] doubleValue] + ([SongData songTimeFudge] * 2);
        if (elapsed < [[self position] doubleValue]) {
            good = NO;
            [self setHasQueued:YES]; // Make sure the song is not submitted
            ScrobLog(SCROB_LOG_TRACE, @"'%@' will not be submitted -- forward seek detected (e=%.0lf,p=%@,d=%@)",
                [self brief], elapsed, [self position], [self duration]);
        }
    }
    if (good && [self ignore]) {
        // Song should be ignored, but slipped through the upper layers
        [self setHasQueued:YES];
        good = NO;
    }
    
    if ([[self artist] length] > 0 && [[self title] length] > 0)
        return (good);
    else
        ScrobLog(SCROB_LOG_WARN, @"Track \"%@\" will not be submitted because it is missing "
            @"Artist, or Title information. Please correct this.", [self brief]);
    return (NO);
}

- (NSTimeInterval)submitIntervalFromNow
{
    double trackTime = [[self duration] doubleValue];
    static double minTime = -1.0;
    static double quotient;
    double fudge = 4.0;
    
    if (minTime < 0.0) {
        minTime = [[ProtocolManager sharedInstance] minTimePlayed];
        quotient = ([[ProtocolManager sharedInstance] minPercentagePlayed] / 100.0);
    }
    
    if ((trackTime = rint(trackTime * quotient)) <= (fudge * (fudge * quotient)))
        fudge = 0.0;
    if (trackTime > minTime)
        trackTime = minTime;
    trackTime -= [[self position] doubleValue]; // Adjust for elapsed time.
    
    trackTime += fudge; // Add some fudge to make sure the track gets submitted when the timer fires.
    return (trackTime);
}

@end

static void NetworkReachabilityCallback (SCNetworkReachabilityRef target, 
    SCNetworkConnectionFlags flags, void *info)
{
    ProtocolManager *pm = (ProtocolManager*)info;
    BOOL up = IsNetworkUp(flags);
    
    ScrobTrace(@"Connection flags: %x.\n", flags);
    [pm setIsNetworkAvailable:up];
    if (up && [[QueueManager sharedInstance] count])
        [pm submit:nil];
}
