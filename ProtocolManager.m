//
//  ProtocolManager.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/04.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <SystemConfiguration/SystemConfiguration.h>

#import "ProtocolManager.h"
#import "ProtocolManager+Subclassers.h"
#import "ProtocolManager_v11.h"
#import "keychain.h"
#import "QueueManager.h"
#import "SongData.h"
#import "iScrobblerController.h"

#define HANDSHAKE_TIMEOUT 30
#define HANDSHAKE_DEFAULT_DELAY 60.0

@interface ProtocolManager (Private)

- (void)handshake;
- (void)resubmit:(NSTimer*)timer;
- (void)setHandshakeResult:(NSDictionary*)result;
- (void)setSubmitResult:(NSDictionary*)result;
- (void)setLastSongSubmitted:(SongData*)song;
- (NSString*)md5Challenge;
- (NSString*)submitURL;
- (void)setIsNetworkAvailble:(BOOL)available;

@end

@interface NSDictionary (ProtocolManagerAdditions)

- (NSString*) httpPostString;

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

- (void)scheduleHandshake:(NSTimer*)timer
{
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
    // Remove any carriage returns (such as HTTP style \r\n -- which killed us during a server upgrade
    (void)[result replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0,[result length])];
	
    [killTimer invalidate];
    killTimer = nil;
    
	ScrobLog(SCROB_LOG_VERBOSE, @"Handshake result: %@", result);
	if ([result length] == 0) {
		ScrobLog(SCROB_LOG_WARN, @"Connection failed");
        result = [NSMutableString stringWithString:@"FAILED\nConnection failed"];
	}
    
NS_DURING
    [self setHandshakeResult:[self handshakeResponse:result]];
NS_HANDLER
    result = [NSMutableString stringWithString:@"FAILED\nInternal exception caused by bad server response."];
    [self setHandshakeResult:[NSDictionary dictionaryWithObjectsAndKeys:
        HS_RESULT_FAILED, HS_RESPONSE_KEY_RESULT,
        result, HS_RESPONSE_KEY_RESULT_MSG,
        @"", HS_RESPONSE_KEY_MD5,
        @"", HS_RESPONSE_KEY_SUBMIT_URL,
        @"", HS_RESPONSE_KEY_UPDATE_URL,
        @"", HS_RESPONSE_KEY_INTERVAL,
        nil]];
NS_ENDHANDLER
	
	if ([self validHandshake]) {
        hsState = hs_valid;
        handshakeDelay = HANDSHAKE_DEFAULT_DELAY;
        
        if ([[QueueManager sharedInstance] count])
            [self submit:nil];
	} else {
        if ([[self lastHandshakeResult] isEqualToString:HS_RESULT_BADAUTH]) {
            hsState = hs_needed;
            handshakeDelay = HANDSHAKE_DEFAULT_DELAY;
        } else {
            hsState = hs_delay;
            [NSTimer scheduledTimerWithTimeInterval:handshakeDelay target:self
                selector:@selector(scheduleHandshake:) userInfo:nil repeats:NO];
            handshakeDelay *= 2.0;
            if (handshakeDelay > [self handshakeMaxDelay])
                handshakeDelay = [self handshakeMaxDelay];
        }
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_HANDSHAKE_COMPLETE object:self];
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
        ScrobLog(SCROB_LOG_VERBOSE, @"Handshake delayed...\n");
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

	NSURL *nsurl = [NSURL URLWithString:url];
	//SCrobTrace(@"nsurl: %@",nsurl);
	//ScrobTrace(@"host: %@",[nsurl host]);
	//ScrobTrace(@"query: %@", [nsurl query]);
	
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl cachePolicy:
        NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
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
    return ([prefs stringForKey:@"useragent"]);
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
        ScrobLog(SCROB_LOG_CRIT, @"Internal inconsistency! Invalid Handshake state (%u)!\n", hsState);
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
    // Remove any carriage returns (such as HTTP style \r\n -- which killed us during a server upgrade
    (void)[result replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0,[result length])];
	
    //[self changeLastResult:result];
    ScrobLog(SCROB_LOG_VERBOSE, @"songs in queue after loading: %d", [[QueueManager sharedInstance] count]);
	
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
        ScrobLog(SCROB_LOG_VERBOSE, @"Song Queue cleaned, count = %i", [[QueueManager sharedInstance] count]);
        nextResubmission = HANDSHAKE_DEFAULT_DELAY;
        
        ++successfulSubmissions;
        
        // See if there are any more entries in the queue
        if (![self useBatchSubmission] && [[QueueManager sharedInstance] count]) {
            // Schedule the next sub after a minute delay
            [self performSelector:@selector(submit:) withObject:nil afterDelay:0.05];
        }
    } else {
        ScrobLog(SCROB_LOG_INFO, @"Server error, songs left in queue, count = %i", [[QueueManager sharedInstance] count]);
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
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self];
}

-(void)connection:(NSURLConnection *)sender didFailWithError:(NSError *)reason
{
    [myData release];
    myData = nil;
    
    if (hs_inprogress == hsState) {
        [self completeHandshake:[NSData data]];
        return;
    }
    
    [self setSubmitResult:
        [NSDictionary dictionaryWithObjectsAndKeys:
        HS_RESULT_FAILED, HS_RESPONSE_KEY_RESULT,
        [reason localizedDescription], HS_RESPONSE_KEY_RESULT_MSG,
        nil]];
	
    [self setLastSongSubmitted:[inFlight lastObject]];
    [inFlight release];
    inFlight = nil;
    
    myConnection = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self];
    
    // Kick off resubmit timer
    [self scheduleResubmit];
    
    ScrobLog(SCROB_LOG_INFO, @"Connection error, songQueue count: %d",[[QueueManager sharedInstance] count]);
}

- (void)resubmit:(NSTimer*)timer
{
    resubmitTimer = nil;
    ScrobLog(SCROB_LOG_VERBOSE, @"Trying resubmission after delay...\n");
    [self submit:nil];
}

- (void)submit:(id)sender
{
    NSMutableDictionary *dict;
    int submissionCount;
    int i;
	
    if (inFlight)
        return;
    
    if (myConnection) {
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
		ScrobLog(SCROB_LOG_VERBOSE, @"Need to handshake");
		[self handshake];
        return;
    }
    
    inFlight = [[[QueueManager sharedInstance] songs] sortedArrayUsingSelector:@selector(compareSongPostDate:)];
    submissionCount = [inFlight count];
    if (!submissionCount) {
        inFlight = nil;
        return;
    }
    
    if (submissionCount > 1 && ![self useBatchSubmission]) {
        submissionCount = 1;
        inFlight = [NSArray arrayWithObject:[inFlight objectAtIndex:0]];
    }
    
    [resubmitTimer invalidate];
    resubmitTimer = nil;
    
    (void)[inFlight retain];
    dict = [[NSMutableDictionary alloc] init];

    NSString* escapedusername=[(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[prefs stringForKey:@"username"],
            NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) 	autorelease];
    
    [dict setObject:escapedusername forKey:@"u"];
    
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
    
    [dict setObject:response forKey:@"s"];
    [response autorelease];
    
    // Fill the dictionary with every entry in the queue, ordering them from
    // oldest to newest.
    for(i=0; i < submissionCount; ++i) {
        [dict addEntriesFromDictionary:[self encodeSong:[inFlight objectAtIndex:i] submissionNumber:i]];
    }
    
    NSMutableURLRequest *request =
		[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self submitURL]]
								cachePolicy:NSURLRequestReloadIgnoringCacheData
							timeoutInterval:30.0];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[[dict httpPostString] dataUsingEncoding:NSUTF8StringEncoding]];
    // Set the user-agent to something Mozilla-compatible
    [request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    
    [dict release];
    
    ++submissionAttempts;
    myConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    
    ScrobLog(SCROB_LOG_INFO, @"%u song(s) submitted...\n", [inFlight count]);
}

- (void)setIsNetworkAvailble:(BOOL)available
{
    isNetworkAvailable = available;
    ScrobLog(SCROB_LOG_VERBOSE, @"Network status changed. Is availbable? \"%@\".\n",
        isNetworkAvailable ? @"Yes" : @"No");
}

- (id)init
{
    self = [super init];
    
    prefs = [[NSUserDefaults standardUserDefaults] retain];
    
    g_networkReachRef = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault,
        [[[NSURL URLWithString:[self handshakeURL]] host] cString]);
    // Get the current state
    SCNetworkConnectionFlags connectionFlags;
    if (SCNetworkReachabilityGetFlags(g_networkReachRef, &connectionFlags) &&
         (connectionFlags & kSCNetworkFlagsReachable))
        isNetworkAvailable = YES;
    // Install a callback to get notified of iface up/down events
    SCNetworkReachabilityContext reachContext = {0};
    reachContext.info = self;
    if (!SCNetworkReachabilitySetCallback(g_networkReachRef, NetworkReachabilityCallback, &reachContext)) {
        ScrobLog(SCROB_LOG_WARN, @"Could not create network status monitor, assuming network is always available.\n");
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
    
    myKeyChain = [[KeyChain defaultKeyChain] retain];

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
}

@end

@implementation SongData (ProtocolManagerAdditions)

- (BOOL)canSubmit
{
    ProtocolManager *pm = [ProtocolManager sharedInstance];
    BOOL good = ( [[self duration] floatValue] >= 30.0 &&
        ([[self percentPlayed] floatValue] > [pm minPercentagePlayed] ||
        [[self position] floatValue] > [pm minTimePlayed]) );
    
    if ([[self artist] length] > 0 && [[self title] length] > 0)
        return (good);
    else
        ScrobLog(SCROB_LOG_WARN, @"Track \"%@\" will not be submitted because it is missing "
            @"Artist, or Title information. Please correct this.", [self breif]);
    return (NO);
}

@end

@implementation NSDictionary (ProtocolManagerAdditions)

- (NSString*) httpPostString
{
    NSMutableString *s = [NSMutableString string];
    NSEnumerator *e = [self keyEnumerator];
    id key;

    while ((key = [e nextObject])) {
        [s appendFormat:@"%@=%@&", key, [self objectForKey:key]];
    }
    
    // Delete final & from the string
    if (![s isEqualToString:@""])
        [s deleteCharactersInRange:NSMakeRange([s length]-1, 1)];
    
    return (s);
}

@end

static void NetworkReachabilityCallback (SCNetworkReachabilityRef target, 
    SCNetworkConnectionFlags flags, void *info)
{
    ProtocolManager *pm = (ProtocolManager*)info;
    
    [pm setIsNetworkAvailble:(flags & kSCNetworkFlagsReachable) ? YES : NO];
    if ((flags & kSCNetworkFlagsReachable))
        [pm submit:nil];
}
