//
//  ProtocolManager.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/04.
//  Copyright 2004-2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <notify.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import "ProtocolManager.h"
#import "ProtocolManager+Subclassers.h"
#import "ProtocolManager_v12.h"
#import "keychain.h"
#import "QueueManager.h"
#import "SongData.h"
#import "iScrobblerController.h"
#import "PreferenceController.h"

#define REQUEST_TIMEOUT 60.0
#define HANDSHAKE_DEFAULT_DELAY 60.0f
/* Russ on IRC: The server cuts any submission off at 1000,
   I personally recommend you don't go over 50 or 100 in a single submission */
#define DEFAULT_MAX_TRACKS_PER_SUB 25
#define MAX_MISSING_VAR_ERRORS 2
#define BADAUTH_WARN 5

@interface ProtocolManager (Private)

- (void)handshake;
- (void)resubmit:(NSTimer*)timer;
- (void)setHandshakeResult:(NSDictionary*)result;
- (void)setSubmitResult:(NSDictionary*)result;
- (void)setLastSongSubmitted:(SongData*)song;
- (NSString*)md5Challenge;
- (NSString*)submitURL;
- (void)setIsNetworkAvailable:(BOOL)available;
- (NSString*)protocolVersion;
- (void)sendNowPlaying;
- (void)checkNetReach:(BOOL)force;
@end

static ProtocolManager *g_PM = nil;
static SCNetworkReachabilityRef netReachRef = nil;

static void NetworkReachabilityCallback (SCNetworkReachabilityRef target, 
    SCNetworkConnectionFlags flags, void *info);

#define NETWORK_UNAVAILABLE_MSG @"Network is not available, submissions are being queued."

#define PM_VERSION [[ProtocolManager sharedInstance] protocolVersion]

@implementation ProtocolManager

+ (ProtocolManager*)sharedInstance
{
    if (!g_PM) {
        if ([@"1.1" isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"protocol"]])
            g_PM = [[ProtocolManager_v12 alloc] init];
        else if ([@"1.2" isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"protocol"]])
            g_PM = [[ProtocolManager_v12 alloc] init];
        else
            ScrobLog(SCROB_LOG_CRIT, @"Unknown protocol version");
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

- (NSDictionary*)hsNotificationUserInfo
{
    NSString *msg = [self lastHandshakeMessage];
    if (msg) {
        NSUInteger i = [msg rangeOfString:@"\n"].location;
        if (NSNotFound != i)
            msg = [msg substringToIndex:i];
    } else
        msg = NSLocalizedString(@"Handshake pending", @"");
        
    NSString *song;
    if (lastSongSubmitted)
        song = [NSString stringWithFormat:@"%@ - %@", [lastSongSubmitted artist], [lastSongSubmitted title]];
    else
        song = nil;

    return ([NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithUnsignedLongLong:[[QueueManager sharedInstance] count]], @"queueCount",
                [NSNumber numberWithUnsignedLong:submissionAttempts], @"submissionAttempts",
                [NSNumber numberWithUnsignedLong:successfulSubmissions], @"successfulSubmissions",
                msg, @"lastServerRepsonse",
                song, @"lastSongSubmitted",
                nil]);
}

- (NSDictionary*)subNotificationUserInfo
{
    NSString *msg = [self lastSubmissionMessage];
    if (msg) {
        NSUInteger i = [msg rangeOfString:@"\n"].location;
        if (NSNotFound != i)
            msg = [msg substringToIndex:i];
    } else
        msg = [self lastHandshakeMessage];
        
    NSString *song;
    if (lastSongSubmitted)
        song = [NSString stringWithFormat:@"%@ - %@", [lastSongSubmitted artist], [lastSongSubmitted title]];
    else
        song = nil;

    return ([NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithUnsignedLongLong:[[QueueManager sharedInstance] count]], @"queueCount",
                [NSNumber numberWithUnsignedLong:submissionAttempts], @"submissionAttempts",
                [NSNumber numberWithUnsignedLong:successfulSubmissions], @"successfulSubmissions",
                msg, @"lastServerRepsonse",
                song, @"lastSongSubmitted",
                nil]);
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
	if (0 == [result length]) {
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
        subFailures = 0;
        hsBadAuth = 0;
        handshakeDelay = HANDSHAKE_DEFAULT_DELAY;
	} else {
        if ([[self lastHandshakeResult] isEqualToString:HS_RESULT_BADAUTH]) {
            ++hsBadAuth;
            if (hsBadAuth >= BADAUTH_WARN) {
                @try {
                [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_BADAUTH object:self];
                } @catch (id e) {
                    ScrobDebug(@"exception: %@", e);
                }
                handshakeDelay = HANDSHAKE_DEFAULT_DELAY * 2.0f;
                hsBadAuth = 0;
			} else {
                handshakeDelay = HANDSHAKE_DEFAULT_DELAY;
            }
        } else {
            hsBadAuth = 0;
            handshakeDelay *= 2.0f;
            if (handshakeDelay > [self handshakeMaxDelay])
                handshakeDelay = [self handshakeMaxDelay];
        }
        hsState = hs_delay;
        handshakeTimer = [NSTimer scheduledTimerWithTimeInterval:handshakeDelay target:self
                selector:@selector(scheduleHandshake:) userInfo:nil repeats:NO];
    }
    
    @try {
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_HANDSHAKE_COMPLETE object:self
        userInfo:[self hsNotificationUserInfo]];
    } @catch (id e) {
        ScrobDebug(@"exception: %@", e);
    }
    
    if (success && sendNP)
        [self sendNowPlaying];
    
    if (success && [[QueueManager sharedInstance] count])
        [self submit:nil];
}

- (void)handshake
{
    if (!isNetworkAvailable) {
        ScrobLog(SCROB_LOG_VERBOSE, @"%@ (%lu)", NETWORK_UNAVAILABLE_MSG, [[QueueManager sharedInstance] count]);
        [self checkNetReach:NO];
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
    npInProgress = NO;
    
    NSString* url = /*@"127.0.0.1"*/ [self handshakeURL];
    ScrobLog(SCROB_LOG_VERBOSE, @"Handshaking... %@", url);
    
    if (!url) {
        ScrobLog(SCROB_LOG_CRIT, @"Empty handshake URL!\n");
        hsState = hs_needed;
        return;
    }
    
    @try {
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_HANDSHAKE_START object:self];
    } @catch (id e) {
        ScrobDebug(@"exception: %@", e);
    }
    
	NSURL *nsurl = [NSURL URLWithString:url];
	//SCrobTrace(@"nsurl: %@",nsurl);
	//ScrobTrace(@"host: %@",[nsurl host]);
	//ScrobTrace(@"query: %@", [nsurl query]);
	
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl cachePolicy:
        NSURLRequestReloadIgnoringCacheData timeoutInterval:REQUEST_TIMEOUT];
	[request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    
    // we don't need to explicitly retain the connection because of the kill timer
    NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:self];
    
    // Setup timer to kill the current handhskake and reset state
    // if we've been in progress for double our timeout period
    killTimer = [NSTimer scheduledTimerWithTimeInterval:REQUEST_TIMEOUT*2.0 target:self
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

- (BOOL)validHandshake
{
    NSString *result = [self lastHandshakeResult];
    
    return ([result isEqualToString:HS_RESULT_OK]);
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
    if (d) {
        [prefs setObject:d forKey:@"LastSongSubmitted"];
        (void)[prefs synchronize];
    }
}

- (NSString*)md5Challenge
{
    return ([hsResult objectForKey:HS_RESPONSE_KEY_MD5]);
}

- (NSString*)submitURL
{
    return ([hsResult objectForKey:HS_RESPONSE_KEY_SUBMIT_URL]);
}

- (NSString*)nowPlayingURL
{
    return ([hsResult objectForKey:HS_RESPONSE_KEY_NOWPLAYING_URL]);
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
    
    [agent replaceOccurrencesOfString:@"-arch-" withString:ISCPUArchitectureString() options:0 range:NSMakeRange(0, [agent length])];
    return (agent);
}

- (float)minPercentagePlayed
{
    return (50.0f);
}

- (float)minTimePlayed
{
    return (240.0f); // Four minutes
}

- (float)handshakeMaxDelay
{
    return (7200.00f); // Two hours
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
    nextResubmission *= 2.0f;
    if (nextResubmission > [self handshakeMaxDelay])
        nextResubmission = [self handshakeMaxDelay];
}

- (void)writeSubLogEntry:(unsigned)sid withTrackCount:(NSUInteger)count withData:(NSData*)data
{
    @try {
    NSString *timestamp = [[NSDate date] descriptionWithCalendarFormat:@"%Y/%m/%e %H:%M:%S GMT"
        timeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"] locale:nil];
    [subLog writeData:[[NSString stringWithFormat:@"[%@, attempt=%u, track count=%lu, size=%lu]\n",
        timestamp, sid, count, [data length]] dataUsingEncoding:NSUTF8StringEncoding]];
    [subLog writeData:data];
    [subLog writeData:[@"\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch(id e) {}
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
        ISASSERT(subConn == nil, "subConn active!");
        [self completeHandshake:myData];
        [myData release];
        myData = nil;
        return;
    }
    
    if (hs_valid != hsState) {
        ScrobLog(SCROB_LOG_ERR, @"Internal inconsistency! Invalid Handshake state (%u)!", hsState);
        [self setSubmitResult:
            [NSDictionary dictionaryWithObjectsAndKeys:
            HS_RESULT_FAILED, HS_RESPONSE_KEY_RESULT,
            @"Internal inconsistency!", HS_RESPONSE_KEY_RESULT_MSG,
            nil]];
        hsState = hs_needed;
        goto didFinishLoadingExit;
    }
    
    NSUInteger i;
    NSMutableString *result = [[[NSMutableString alloc] initWithData:myData encoding:NSUTF8StringEncoding] autorelease];
    // Remove any carriage returns (such as HTTP style \r\n -- which killed us during a server upgrade)
    (void)[result replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0,[result length])];
	
    if (npInProgress) {
        [myData release];
        myData = nil;
        [subConn autorelease];
        subConn = nil;
        npInProgress = NO;
        ScrobLog(SCROB_LOG_VERBOSE, @"NP result: %@", result);
        return;
    }
    
    ScrobLog(SCROB_LOG_VERBOSE, @"Submission result: %@", result);
    ScrobLog(SCROB_LOG_TRACE, @"Tracks in queue after submission: %lu", [[QueueManager sharedInstance] count]);
    
    [self setSubmitResult:[self submitResponse:result]];
    
    // Process Body, and if OK, remove the in flight songs from the queue
    if([[self lastSubmissionResult] isEqualToString:HS_RESULT_OK])
    {
		NSUInteger count = [inFlight count];
        for(i=0; i < count; i++) {
            [[QueueManager sharedInstance] removeSong:[inFlight objectAtIndex:i] sync:NO];
        }
        [[QueueManager sharedInstance] syncQueue:nil];
        ScrobLog(SCROB_LOG_TRACE, @"Queue cleaned, track count: %lu", [[QueueManager sharedInstance] count]);
        nextResubmission = HANDSHAKE_DEFAULT_DELAY;
        
        // Set the new max if we detected a proxy truncation -- only done once
        if (missingVarErrorCount > MAX_MISSING_VAR_ERRORS && count > (MAX_MISSING_VAR_ERRORS * 2)
            && DEFAULT_MAX_TRACKS_PER_SUB == maxTracksPerSub)
            maxTracksPerSub = count;
        
        ++successfulSubmissions;
        missingVarErrorCount = 0;
        subBadAuth = 0;
        
        // See if there are any more entries in the queue
        if ([[QueueManager sharedInstance] count]) {
            // Schedule the next sub after a minute delay
            [self performSelector:@selector(submit:) withObject:nil afterDelay:0.5];
        }
    } else {
        ScrobLog(SCROB_LOG_INFO, @"Server error -- tracks in queue: %lu", [[QueueManager sharedInstance] count]);
        if (SCROB_LOG_TRACE == ScrobLogLevel())
            [self writeSubLogEntry:submissionAttempts withTrackCount:[inFlight count] withData:myData];
        
        if (++subFailures >= 3)
            hsState = hs_needed;
        
		if ([[self lastSubmissionResult] isEqualToString:HS_RESULT_BADAUTH]) {
			hsState = hs_needed;
            ++subBadAuth;
            // Send notification if we've hit the threshold
			if (subBadAuth >= BADAUTH_WARN) {
                @try {
				[[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_BADAUTH object:self];
                } @catch (id e) {
                    ScrobDebug(@"exception: %@", e);
                }
                subBadAuth = 0;
			}
		} else {
			subBadAuth = 0;
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
    
    [subConn autorelease];
    subConn = nil;
    
    @try {
    if (0 != notify_post)
        notify_post("org.bergstrand.iscrobbler.didsubmit");
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self
        userInfo:[self subNotificationUserInfo]];
    } @catch (id e) {
        ScrobDebug(@"exception: %@", e);
    }
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
        ISASSERT(subConn == nil, "subConn active!");
        // Emulate a server error
        NSData *response = [[@"FAILED Connection failed - " stringByAppendingString:why]
            dataUsingEncoding:NSUTF8StringEncoding];
        [self completeHandshake:response];
        return;
    }
    
    [subConn autorelease];
    subConn = nil;
    
    if (npInProgress) {
        npInProgress = NO;
        ScrobLog(SCROB_LOG_INFO, @"NP Connection error: '%@'.", [reason localizedDescription]);
        return;
    }
    
    [self setSubmitResult:
        [NSDictionary dictionaryWithObjectsAndKeys:
        HS_RESULT_FAILED, HS_RESPONSE_KEY_RESULT,
        why, HS_RESPONSE_KEY_RESULT_MSG,
        nil]];
	
    [self setLastSongSubmitted:[inFlight lastObject]];
    
    @try {
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self
        userInfo:[self subNotificationUserInfo]];
    } @catch (id e) {
        ScrobDebug(@"exception: %@", e);
    }
    
    // Kick off resubmit timer
    [self scheduleResubmit];
    
    ScrobLog(SCROB_LOG_INFO, @"Connection error: '%@'. Tracks in queue: %lu.",
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
    if (inFlight || subConn) {
        if ([[NSDate date] timeIntervalSince1970] > (subConnCreation + REQUEST_TIMEOUT*2.0)) {
            [subConn cancel];
            ScrobLog(SCROB_LOG_VERBOSE, @"Stuck submission connection detected, forcing timeout error.");
            [self connection:subConn didFailWithError:
                [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
        } else {
            ScrobLog(SCROB_LOG_WARN, @"Already connected to server, delaying submission... (connection=%p, inFlight=%p)",
                subConn, inFlight);
        }
        return;
    }
    
    if (!isNetworkAvailable) {
        ScrobLog(SCROB_LOG_VERBOSE, @"%@ (%lu)", NETWORK_UNAVAILABLE_MSG, [[QueueManager sharedInstance] count]);
        [self checkNetReach:NO];
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
    NSUInteger submissionCount = [inFlight count];
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
            
        ScrobLog(SCROB_LOG_VERBOSE, @"Possible proxy corruption detected (%u). Batch sub reduced to %lu.",
            missingVarErrorCount, submissionCount);
            
        ISASSERT(submissionCount <= [inFlight count], "Adjusted sub count out of range!");
    }
    
    if (submissionCount != [inFlight count])
        inFlight = [inFlight subarrayWithRange:NSMakeRange(0,submissionCount)];
    
    [resubmitTimer invalidate];
    resubmitTimer = nil;
    
    @try {
    if (0 != notify_post)
        notify_post("org.bergstrand.iscrobbler.willsubmit");
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_START object:self];
    } @catch (id e) {
        ScrobDebug(@"exception: %@", e);
    }
    
    (void)[inFlight retain];
    NSMutableData *subData = [[NSMutableData alloc] init];
    
    @try {
    [self setSubValue:[self authChallengeResponse] forKey:@"s" inData:subData];
    
    // Fill the dictionary with every entry in the queue, ordering them from
    // oldest to newest.
    NSUInteger i;
    for(i=0; i < submissionCount; ++i) {
        [subData appendData:[self encodeSong:[inFlight objectAtIndex:i] submissionNumber:(unsigned)i]];
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
    subConn = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
    subConnCreation = [[NSDate date] timeIntervalSince1970];
    
    ScrobLog(SCROB_LOG_INFO, @"%lu song(s) submitted...\n", [inFlight count]);
    if (SCROB_LOG_TRACE == ScrobLogLevel())
        [self writeSubLogEntry:submissionAttempts withTrackCount:[inFlight count] withData:[request HTTPBody]];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception generated during submission attempt: %@\n", e);
        @try {
        [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self
            userInfo:[self subNotificationUserInfo]];
        } @catch (NSException *e2) {
            ScrobDebug(@"exception: %@", e2);
        }
        [inFlight release];
        inFlight = nil;
    }
    [subData release];
}

- (NSString*)netDiagnostic
{
    NSString *msg = nil;
    CFNetDiagnosticRef diag = CFNetDiagnosticCreateWithURL(kCFAllocatorDefault,
        (CFURLRef)[NSURL URLWithString:[self handshakeURL]]);
    if (diag) {
        (void)CFNetDiagnosticCopyNetworkStatusPassively(diag, (CFStringRef*)&msg);
        CFRelease(diag);
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
        lastNetCheck = 0.0;
        
        NSString *msg = @"", *logmsg = @"";
        if ((isNetworkAvailable = available)) {
            handshakeDelay = nextResubmission = HANDSHAKE_DEFAULT_DELAY;
            // XXX: if g_PM is nil, then we are being called from [init].
            // As the QM has probably not been created yet, this will cause an infite recursion
            // of new instances of us and the QM.
            if (g_PM && [[QueueManager sharedInstance] count])
                [self submit:nil];
        } else {
            msg = [self netDiagnostic];
            logmsg = [NSString stringWithFormat:@" (%@)", msg];
        }
        ScrobLog(SCROB_LOG_VERBOSE, @"Network status changed. Is available? \"%@\".%@\n",
            isNetworkAvailable ? @"Yes" : @"No", logmsg);
        
        @try {
        [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_NETWORK_STATUS
            object:self userInfo:
                [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithBool:available], PM_NOTIFICATION_NETWORK_STATUS_KEY,
                    msg, PM_NOTIFICATION_NETWORK_MSG_KEY,
                    nil]];
        } @catch (id e) {
            ScrobDebug(@"exception: %@", e);
        }
    }
}

- (BOOL)networkAvailable
{
    return (isNetworkAvailable);
}

- (void)setNetworkAvailable:(NSNumber*)available
{
    [self setIsNetworkAvailable:[available boolValue]];
}

#define IsNetworkUp(flags) \
( ((flags) & kSCNetworkFlagsReachable) && (0 == ((flags) & kSCNetworkFlagsConnectionRequired) || \
  ((flags) & kSCNetworkFlagsConnectionAutomatic)) )

- (BOOL)registerNetMonitor
{
    SCNetworkReachabilityContext reachContext = {0,};
    
    if (netReachRef) {
        ScrobLog(SCROB_LOG_TRACE, @"Rescheduling network monitor.");
        (void)SCNetworkReachabilitySetCallback(netReachRef, NULL, &reachContext);
        (void)SCNetworkReachabilityUnscheduleFromRunLoop(netReachRef,
            [[NSRunLoop currentRunLoop] getCFRunLoop], kCFRunLoopCommonModes);
        CFRelease(netReachRef);
        netReachRef = NULL;
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"IgnoreNetworkMonitor"]) {
        netReachRef = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault,
            [[[NSURL URLWithString:[self handshakeURL]] host] cStringUsingEncoding:NSASCIIStringEncoding]);
        
        if (netReachRef)
            [self checkNetReach:YES]; // Get the current state
        
        // Install a callback to get notified of iface up/down events
        reachContext.info = self;
        if (netReachRef && SCNetworkReachabilitySetCallback(netReachRef, NetworkReachabilityCallback, &reachContext)
            && SCNetworkReachabilityScheduleWithRunLoop(netReachRef,
                [[NSRunLoop currentRunLoop] getCFRunLoop], kCFRunLoopCommonModes)) {
            return (YES);
        } else {
            ScrobLog(SCROB_LOG_WARN, @"Could not create network status monitor - assuming network is always available.");
            if (netReachRef) {
                reachContext.info = NULL;
                (void)SCNetworkReachabilitySetCallback(netReachRef, NULL, &reachContext);
                CFRelease(netReachRef);
                netReachRef = NULL;
            }
        }
    } else { // @"IgnoreNetworkMonitor"
        ScrobLog(SCROB_LOG_INFO, @"Ignoring network status monitor - assuming network is always available.");
    }
    
    isNetworkAvailable = NO;
    [self setIsNetworkAvailable:YES];
    return (NO);
}

- (void)checkNetReachInBackground:(NSValue*)reachRef
{
    if ([reachRef pointerValue] != netReachRef)
        return;
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    SCNetworkConnectionFlags flags;
    BOOL canReach;
    BOOL resetMonitor = NO;
    if ((canReach = SCNetworkReachabilityGetFlags(netReachRef, &flags)) && IsNetworkUp(flags)) {
        canReach = YES;
    } else {
        if (!canReach) {
            resetMonitor = YES;
        } else
            canReach = NO;
    }
    
    ScrobTrace(@"Connection flags: %x.", flags);
    
    LEOPARD_BEGIN
    [self performSelectorOnMainThread:@selector(setNetworkAvailable:)
        withObject:[NSNumber numberWithBool:canReach] waitUntilDone:YES];
    if (resetMonitor)
        [self performSelectorOnMainThread:@selector(registerNetMonitor) withObject:nil waitUntilDone:YES];
    [pool release];
    return;
    LEOPARD_END
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    // Tiger
    [self setIsNetworkAvailable:canReach];
    if (resetMonitor)
        [self performSelector:@selector(registerNetMonitor) withObject:nil afterDelay:1.0]; // avoid recursion
    [pool release];
    #endif
}

- (void)checkNetReach:(BOOL)force
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!force && now < (lastNetCheck+900.0))
        return;
    
    lastNetCheck = now;
    isNetworkAvailable = !isNetworkAvailable;
    LEOPARD_BEGIN
    [self performSelectorInBackground:@selector(checkNetReachInBackground:)
        withObject:[NSValue valueWithPointer:netReachRef]];
    return;
    LEOPARD_END
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    // perform check on main thread in Tiger
    ScrobLog(SCROB_LOG_TRACE, @"Performing network check on main thread.");
    [self checkNetReachInBackground:[NSValue valueWithPointer:netReachRef]];
    #endif
}

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
    
    [self checkNetReach:YES];
}

static SongData *npSong = nil;
static int npDelays = 0;
- (void)sendNowPlaying
{
    sendNP = NO;
    
    if (!npSong || ![self isNetworkAvailable])
        return; // we missed it, oh well...
    
    if (!subConn) {
        NSMutableURLRequest *request =
            [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self nowPlayingURL]]
                cachePolicy:NSURLRequestReloadIgnoringCacheData
                timeoutInterval:REQUEST_TIMEOUT];
        [request setHTTPMethod:@"POST"];
        [request setHTTPBody:[self nowPlayingDataForSong:npSong]];
        // Set the user-agent to something Mozilla-compatible
        [request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
        
        subConn = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
        subConnCreation = [[NSDate date] timeIntervalSince1970];
        npInProgress = YES;
        npDelays = 0;
        
        ScrobLog(SCROB_LOG_VERBOSE, @"Sending NP notification for '%@'.", [npSong brief]);
        if (SCROB_LOG_TRACE == ScrobLogLevel())
            [self writeSubLogEntry:0 withTrackCount:1 withData:[request HTTPBody]];
    } else if (npDelays < 5) {
        [self performSelector:@selector(sendNowPlaying) withObject:nil afterDelay:(npDelays+=1) * 1.0];
    } else {
        npDelays = 0;
        ScrobLog(SCROB_LOG_WARN, @"Can't send NP notification as a connection to the server is already in progress.");
    }
}

- (void)nowPlaying:(NSNotification*)note
{
    SongData *s = [note object];
    BOOL repeat = NO;
    id obj;
    NSDictionary *userInfo = [note userInfo];
    if (userInfo && (obj = [userInfo objectForKey:@"repeat"]))
        repeat = [obj boolValue];
    if (!isNetworkAvailable || !s || (!repeat && [npSong isEqualToSong:s]) || 0 == [[s artist] length] || 0 == [[s title] length]) {
        if (!s) {
            [npSong release];
            npSong = nil;
        }
        return;
    }
    
    [npSong release];
    npSong = [s retain];
    
    // We must execute a server handshake before
    // doing anything else. If we've already handshaked, then no worries.
    if (hs_valid != hsState) {
		ScrobLog(SCROB_LOG_VERBOSE, @"NP: Need to handshake.\n");
        sendNP = YES;
		[self handshake];
        return;
    }
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendNowPlaying) object:nil];
    [self performSelector:@selector(sendNowPlaying) withObject:nil afterDelay:1.0];
}

- (void)authDidChange:(NSNotification*)note
{
    if (subConn) {
        ScrobLog(SCROB_LOG_TRACE, @"Authentication credentials have changed during an active network connection, delaying state change...");
        // We don't want to reset the handshake state while a sub is in progress; otherwise,
        // an error will occur in [connectionDidFinishLoading:] 
        [self performSelector:@selector(authDidChange:) withObject:note afterDelay:1.0];
        return;
    }
    ScrobLog(SCROB_LOG_VERBOSE, @"Authentication credentials changed, need to handshake");
    hsState = hs_needed;
    
    if ([[QueueManager sharedInstance] count] > 0) {
        // This is a really a warning, but errors require the user to close the window manually
        [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Credentials Changed", "")
            message:NSLocalizedString(@"The Last.fm credentials have changed and there are songs queued for submission. The queued songs will be submitted to the current last.fm account even if they were played while a different account was active.", "")];
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
    
    if ([self registerNetMonitor]) {
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
            selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(authDidChange:) name:iScrobblerAuthenticationDidChange object:nil];
    
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
    
    maxTracksPerSub = DEFAULT_MAX_TRACKS_PER_SUB;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(nowPlaying:) name:@"Now Playing" object:nil];

    // We are an abstract class, only subclasses return valid objects
    return (nil);
}

- (void)dealloc
{
    [prefs release];
    [inFlight release];
    [lastSongSubmitted release];
    [hsResult release];
    [submitResult release];
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
        [[self elapsedTime] floatValue] > [pm minTimePlayed] || reconstituted) );
    
    if ([self isLastFmRadio]) {
        // banned and skipped radio songs still get submitted even though they are not counted in stats
        good = ([self banned] || [self skipped] || good);
        if (good && [[self lastFmAuthCode] length] <= 0) {
            ScrobLog(SCROB_LOG_WARN, @"Radio track \"%@\" will not be submitted because it is missing a last.fm authorization code.",
                [self brief]);
            good = NO;
        }
    } else {
        good = (good && ![self banned] && ![self skipped]);
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

- (NSString*)lastFmRating
{
    NSString *r = @"";
    if ([self loved])
        r = @"L";
    else if ([self isLastFmRadio]) {
        if ([self banned]) // Ban supersedes skip
            r = @"B";
        else if ([self skipped])
            r = @"S";
    }
    return (r);
}

@end

static void NetworkReachabilityCallback (SCNetworkReachabilityRef target, 
    SCNetworkConnectionFlags flags, void *info)
{
    BOOL up = IsNetworkUp(flags);
    ScrobTrace(@"Connection flags: %x.\n", flags);
    
    ProtocolManager *pm = (ProtocolManager*)info;
    [pm setIsNetworkAvailable:up];
}
