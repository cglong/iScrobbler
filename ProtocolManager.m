//
//  ProtocolManager.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/04.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "ProtocolManager.h"
#import "ProtocolManager+Subclassers.h"
#import "ProtocolManager_v11.h"
#import <CURLHandle/CURLHandle.h>
#import <CURLHandle/CURLHandle+extras.h>
#import "CURLHandle+SpecialEncoding.h"
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
- (void)setURLHandle:(CURLHandle *)inURLHandle;
- (NSString*)md5Challenge;
- (NSString*)submitURL;

@end

static ProtocolManager *g_PM = nil;

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
    CURLHandle *h = [[timer userInfo] objectForKey:@"Handle"];
    killTimer = nil;
    
    if (hs_inprogress == hsState) {
        // Kill handshake that seems to be stuck
        [h removeClient:self];
        [h cancelLoadInBackground];
        // Reset state and try again
        hsState = hs_needed;
        ScrobLog(SCROB_LOG_INFO, @"Stopped runaway handshake. Trying again...\n");
        [self handshake];
    }
}

- (void)completeHandshake:(NSURLHandle *)sender
{
    [sender flushCachedData];
    NSData *data = [sender resourceData];
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
		NSURL *nsurl = [NSURL URLWithString:[self submitURL]];
		[myURLHandle setURL:nsurl];
		
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
	
	CURLHandle *handshakeHandle = (CURLHandle*)[CURLHandle cachedHandleForURL:nsurl];	
	
    // Setup timer to kill the current handhskake and reset state
    // if we've been in progress for 5 minutes
    killTimer = [NSTimer scheduledTimerWithTimeInterval:300.0 target:self
        selector:@selector(killHandshake:)
        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:handshakeHandle, @"Handle", nil]
        repeats:NO];
    
	// fail on errors (response code >= 300)
    [handshakeHandle setFailsOnError:YES];
	[handshakeHandle setFollowsRedirects:YES];
	[handshakeHandle setConnectionTimeout:HANDSHAKE_TIMEOUT];
	
    // Set the user-agent to something Mozilla-compatible
    [handshakeHandle setUserAgent:[self userAgent]];
	
    [handshakeHandle addClient:self];
	[handshakeHandle loadInBackground];
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

- (void)setURLHandle:(CURLHandle *)inURLHandle
{
    [inURLHandle retain];
    [myURLHandle release];
    myURLHandle = inURLHandle;
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

// URL callbacks
- (void)URLHandleResourceDidFinishLoading:(NSURLHandle *)sender
{
    [sender removeClient:self];
    
    if (hs_inprogress == hsState) {
        [self completeHandshake:sender];
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
    NSData *data = [sender resourceData];
    NSMutableString *result = [[[NSMutableString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
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
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PM_NOTIFICATION_SUBMIT_COMPLETE object:self];
}

-(void)URLHandleResourceDidBeginLoading:(NSURLHandle *)sender { }

-(void)URLHandleResourceDidCancelLoading:(NSURLHandle *)sender
{
    [sender removeClient:self];
    [self setLastSongSubmitted:nil];
    [inFlight release];
    inFlight = nil;
}

-(void)URLHandle:(NSURLHandle *)sender resourceDataDidBecomeAvailable:(NSData *)newBytes { }

-(void)URLHandle:(NSURLHandle *)sender resourceDidFailLoadingWithReason:(NSString *)reason
{
    [myURLHandle removeClient:self];
    
    if (hs_inprogress == hsState) {
        [self completeHandshake:sender];
        return;
    }
    
    [self setSubmitResult:
        [NSDictionary dictionaryWithObjectsAndKeys:
        HS_RESULT_FAILED, HS_RESPONSE_KEY_RESULT,
        reason, HS_RESPONSE_KEY_RESULT_MSG,
        nil]];
	
    [self setLastSongSubmitted:[inFlight lastObject]];
    [inFlight release];
    inFlight = nil;
    
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
    
    // First things first, we must execute a server handshake before
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
    
    // fail on errors (response code >= 300)
    [myURLHandle setFailsOnError:YES];
    [myURLHandle setFollowsRedirects:YES];
    
    // Set the user-agent to something Mozilla-compatible
    [myURLHandle setUserAgent:[prefs stringForKey:@"useragent"]];
    
    //ScrobTrace(@"dict before sending: %@",dict);
    // Handle "POST"
    [myURLHandle setSpecialPostDictionary:dict encoding:NSUTF8StringEncoding];
    
    // And load in background...
    [myURLHandle addClient:self];
    [myURLHandle loadInBackground];
    
    [dict release];
    
    ScrobLog(SCROB_LOG_INFO, @"%u song(s) submitted...\n", [inFlight count]);
}

- (void)applicationWillTerminate:(NSNotification*)notification
{
    [CURLHandle curlGoodbye];
}

- (id)init
{
    self = [super init];
    
    // Activate CURLHandle
    [CURLHandle curlHelloSignature:@"net.sourceforge.iscrobbler" acceptAll:YES];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(applicationWillTerminate:)
                name:NSApplicationWillTerminateNotification
                object:nil];
    
    prefs = [[NSUserDefaults standardUserDefaults] retain];
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
    
    // Set the URL for CURLHandle
    [self setURLHandle:(CURLHandle *)
        [[NSURL URLWithString:[prefs stringForKey:@"url"]] URLHandleUsingCache:NO]];
#if 0
    [self setURLHandle:(CURLHandle *)
        [[NSURL URLWithString:@"http://127.0.0.1/"] URLHandleUsingCache:NO]];
    #warning Set Handshake NO
    hsState = hs_valid;
    [myURLHandle setURL:[NSURL URLWithString:@"http://127.0.0.1/v1.1.php"]];
#endif

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
    [myURLHandle release];
}

@end

@implementation SongData (ProtocolManagerAdditions)

- (BOOL)canSubmit
{
    ProtocolManager *pm = [ProtocolManager sharedInstance];
    BOOL good = ( [[self duration] floatValue] >= 30.0 &&
        ([[self percentPlayed] floatValue] > [pm minPercentagePlayed] ||
        [[self position] floatValue] > [pm minTimePlayed]) );

    return (good);
}

@end
