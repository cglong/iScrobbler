//
//  AudioScrobblerProtocol.m
//  iScrobbler
//
//  Created by Eric Seidel on Sat Oct 30 2004.
//

#import "AudioScrobblerProtocol.h"

#import "iScrobblerController.h"

#import "SongData.h"

#import "NSString_iScrobblerAdditions.h"
#import "NSDictionary+httpEncoding.h"

#import <openssl/md5.h> // the symbols are pulled in via security.framework anyway...


#define UNSUBMITTED_SONGS_FILE @"UnsubmittedSongs.plist"

@interface AudioScrobblerProtocol (PrivateMethods)

- (void)submissionTimer:(NSTimer *)timer; //called when queueTimer fires

- (void)adjustBackOffTimerForSuccess:(BOOL)success;
- (void)updateBadAuthenticationCountWithSuccess:(BOOL)successfulAuthentication;

- (NSString *)escapedUsername;
- (NSString *)handshakeBaseURLString;
- (NSURL *)submitURL;

- (NSString *)md5hash:(NSString *)input;
@end


@implementation AudioScrobblerProtocol

- (id)init {
	if (self = [super init]) {
		
		// this should probably be moved to being lazily accessed.
		NSString *filePath = [[[NSApp delegate] appSupportDirectory] stringByAppendingString:UNSUBMITTED_SONGS_FILE];
		_songSubmissionQueue = [[NSMutableArray alloc] initWithContentsOfFile:filePath];
		if (!_songSubmissionQueue)
			_songSubmissionQueue = [[NSMutableArray alloc] init];
		else
			ISLog(@"AudioScrobblerProtocol init", @"Succesfully loaded %i songs into submission queue.", [_songSubmissionQueue count]);
	}
	
	return self;
}

- (void)dealloc{
	[_lastResult release];
	[_lastHandshakeResult release];
	
	[_songSubmissionQueue release];
	[_md5Challenge release];
	[_submitURLString release];

	[_submissionTimer invalidate];
	[_submissionTimer release];
	
	[super dealloc];
}

#pragma mark -

- (void)queueSongForSubmission:(SongData *)song {
	ISLog(@"queueSongForSubmission:", @"Ready to send (%@).", song);
	
	[song setHasQueued:YES]; // FIXME: why hold this info in the song?
	
	// FIXME: Why do we need to copy the song object??
	[_songSubmissionQueue insertObject:[[song copy] autorelease] atIndex:0];
	
	// we schedule the submission timer if it's not already
	[self scheduleSubmissionTimerIfNeeded];
}

- (SongData *)peekNextSongForSubmission {
	return [_songSubmissionQueue lastObject];
}

- (SongData *)popNextSongForSubmission {
	SongData *song = nil;
	if ([_songSubmissionQueue count]) {
		int lastIndex = [_songSubmissionQueue count] - 1;
		song = [_songSubmissionQueue objectAtIndex:lastIndex];
		[_songSubmissionQueue removeObjectAtIndex:lastIndex];
	}
	return song;
}

- (void)clearSubmittedSongs {
	// this should really be a separate "submitted songs" queue
	// which is used to know which songs should be removed
	// from the real queue.
	[_songSubmissionQueue removeAllObjects];
	NSLog(@"FIXME: _songSubmissionQueue cleaned, count = %i",[_songSubmissionQueue count]);
}

#pragma mark -

// FIXME: This should probably be done via subclasses to some ScrobblerProtocol object...
- (NSString *)handshakeString1_2 {
	// http://post.audioscrobbler.com/?hs=true&p=1.2&c=<clientid>&v=<clientversion>&u=<username>&t=<unix_timestamp>&a=<passcode>
	
	NSMutableString *url = [[[self handshakeBaseURLString] mutableCopy] autorelease];
		
	// build the rest of the URL
    [url appendString:@"?hs=true"];	
	[url appendString:@"&p=1.2"]; // 1.1 protocol
	
	[url appendString:@"&v="];
	[url appendString:[[NSUserDefaults standardUserDefaults] stringForKey:@"version"]];
	
	[url appendString:@"&u="];
	[url appendString:[self escapedUsername]]; // username
	
	[url appendString:@"&c="];
	[url appendString:[[NSUserDefaults standardUserDefaults] stringForKey:@"clientid"]];
	
	NSString *timestamp = [[NSDate date] description];
	[url appendString:@"&t="];
	[url appendString:timestamp];
	
	[url appendString:@"&a="];
	// per protocol: a = md5(md5(password) + timestamp)
	[url appendString:[self md5hash:[[self md5hash:[[NSApp delegate] password]] stringByAppendingString:_md5Challenge]]];
	
	return url;
}

- (NSString *)handshakeString {
	
	// grab the URL from the prefs and make sure it's valid
	NSMutableString *url = [[[self handshakeBaseURLString] mutableCopy] autorelease];
	
	// build the rest of the URL
    [url appendString:@"?hs=true"];	
	[url appendString:@"&u="];
	[url appendString:[self escapedUsername]]; // username
	[url appendString:@"&p=1.1"]; // 1.1 protocol
	[url appendString:@"&v="];
	[url appendString:[[NSUserDefaults standardUserDefaults] stringForKey:@"version"]];
	[url appendString:@"&c="];
	[url appendString:[[NSUserDefaults standardUserDefaults] stringForKey:@"clientid"]];
	
	//NSLog(@"returning: %@", url);
	
	return url;
}

- (BOOL)handleHandshakeResult:(NSString *)resultString {
	//NSLog(@"recieved result = %@", resultString);
	NSArray *splitResult = [resultString componentsSeparatedByString:@"\n"];
	NSString *handshakeResult = [splitResult objectAtIndex:0];
	
	// did we get a "good" response?
	if ([handshakeResult hasPrefix:@"UPTODATE"] ||
		[handshakeResult hasPrefix:@"UPDATE"]) {
		
		if ([splitResult count] > 2) {
			// looks to be decent data, lets keep it
			[self setValue:[splitResult objectAtIndex:1] forKey:@"md5Challenge"];
			[self setValue:[splitResult objectAtIndex:2] forKey:@"submitURLString"];
			
			[self adjustBackOffTimerForSuccess:YES];
			[self setValue:[NSNumber numberWithBool:YES] forKey:@"haveHandshaked"];
			[self scheduleSubmissionTimerIfNeeded];
			return YES;
		} else {
			ISLog(@"handleHandshakeResule", @"Got UPTODATE/UPDATE response from handshake, but missing some data! (response = %@)", splitResult);
			// maybe the server is just upset, let's try agian.
			[self adjustBackOffTimerForSuccess:NO];
			[self scheduleSubmissionTimerIfNeeded];
			return NO;
		}
	} else if ([handshakeResult hasPrefix:@"BADUSER"]) {
		// authentication failed.
		// this only applies to 1.2, 1.1 never returns bad user from handshake
		[self updateBadAuthenticationCountWithSuccess:NO];
		return NO;
	} else {
		ISLog(@"handleHandshakeResult", @"Unknown response from handshake: %@, backing off, then trying again...", handshakeResult);
		
		// let's try again, see if it goes away.
		[self adjustBackOffTimerForSuccess:NO];
		[self scheduleSubmissionTimerIfNeeded];
		return NO;
	}
}

//TODO: INTERVAL stuff

/* the 1.1 and 1.0 protocols have "INTERVAL" values appended
to every command which:
"INTERVAL is the number of seconds you must wait between sending updates this will be 0 if the server is doing ok, but if the server is under heavy stress, it may go up to avoid too many submissions in a short space of time."
we're currently ignoring this value, using the 1.2 backoff scheme.
We probably should respect the intervals.
*/

- (BOOL)handshake
{
	// get the handshake URL
	NSString *url = [self handshakeString];
	if (![url length]) {
		NSLog(@"Failed to get url, can't handshake.");
		// FIXME: should throw up some kind of fatal error here.
		// allowing them to rever their preferences...
	}
	ISLog(@"handshake", @"Handshaking... %@", url);
	
	// actually make the network request.
	NSURLRequest *handshakeRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30];
	
	[self setValue:[NSURLConnection connectionWithRequest:handshakeRequest delegate:self] forKey:@"openConnection"];
}

#pragma mark -

- (void)scheduleSubmissionTimerIfNeeded {
	if (![_submissionTimer isValid]) {
		[_submissionTimer release];
		ISLog(@"scheduleSubmissionTimerIfNeeded", @"Scheduling next submission attempt %i seconds from now", _exponentialBackOffDelay);
		// FIXME, this could possibly be something other than a timer
		// are we ever going to go throug this logic with a _exponentialBackOffDelay > 0?
		_submissionTimer = [[NSTimer scheduledTimerWithTimeInterval:_exponentialBackOffDelay
															 target:self
														   selector:@selector(submissionTimer:)
														   userInfo:nil
															repeats:NO] retain];
	} else
		ISLog(@"scheduleSubmissionTimerIfNeeded", @"Not scheduling submission timer, already scheduled to fire at %@", [[_submissionTimer fireDate] description]);
}

- (NSDictionary *)songPostDictionaryForSongs:(NSArray *)submissionQueue {
	NSMutableDictionary *postDictionary = [NSMutableDictionary dictionary];
	
	// username
	[postDictionary setObject:[self escapedUsername] forKey:@"u"];
	
	// per protocol: s = md5(md5(password) + challenge)
	NSString *response = [self md5hash:[[self md5hash:[[NSApp delegate] password]] stringByAppendingString:_md5Challenge]];
	[postDictionary setObject:response forKey:@"s"];
	//NSLog(@"songPostDictionaryForSongs:", @"challange response: %@", response);
	
	// Fill the dictionary with every entry in the _songSubmissionQueue, ordering them from
	// oldest to newest.
	// FIXME: this should actually sort by date...
	// FIXME: this logic could also be clearer...
	int submissionCount = [_songSubmissionQueue count];
	for(int i = (submissionCount - 1); i >= 0; i--) {
		SongData *song = [_songSubmissionQueue objectAtIndex:i];
		NSDictionary *songDictionary = [song postDict:(submissionCount - 1 - i)];
		[postDictionary addEntriesFromDictionary:songDictionary];
	}
	
	return postDictionary;
}

- (BOOL)handleSubmissionResponse:(NSString *)result {
	
	[self setValue:result forKey:@"lastResult"];
    //ISLog(@"handleSubmissionResponse:", "_songSubmissionQueue count after loading: %d", [_songSubmissionQueue count]);
	
	ISLog(@"handleSubmissionResponse:", @"Server result: %@", result);
    // Process Body, if OK, then remove the submitted songs from the queue
    if([result hasPrefix:@"OK"])
    {
		[self clearSubmittedSongs];
		[self updateBadAuthenticationCountWithSuccess:YES];
		[self adjustBackOffTimerForSuccess:YES];
		return YES;
    } else {
		// failed to submit, may need to handshake again.
		[self setValue:[NSNumber numberWithBool:NO] forKey:@"haveHandshaked"];
		
		// If the password is wrong, note it.
		if ([result hasPrefix:@"BADAUTH"]) {
			[self updateBadAuthenticationCountWithSuccess:NO];
		} else {
			// update the backoff delay
			[self adjustBackOffTimerForSuccess:NO];
			// try again, maybe the error will go away...
			[self scheduleSubmissionTimerIfNeeded];
		}
		
		ISLog(@"handleSubmissionResponse:", @"Server responded with error, %i songs left in queue.  (response = %@)",[_songSubmissionQueue count], result);
		return NO;
    }
}

- (BOOL)submitSongs
{
	// then we build the post data from our song submission queue
	NSDictionary *songPost = [self songPostDictionaryForSongs:_songSubmissionQueue];
	NSString *postString = [songPost specialFormatForHTTPUsingEncoding:NSUTF8StringEncoding];
	NSData *postData = [postString dataUsingEncoding:NSUTF8StringEncoding];
	
	// build the networking request...
	ISLog(@"submitSongs", @"Submitting... %@", [self submitURL]);
	NSMutableURLRequest *submissionRequest =
		[NSMutableURLRequest requestWithURL:[self submitURL]
								cachePolicy:NSURLRequestReloadIgnoringCacheData
							timeoutInterval:30];
	[submissionRequest setHTTPMethod:@"POST"];
	[submissionRequest setHTTPBody:postData];
	
	// perform the actual networking.
	[self setValue:[NSURLConnection connectionWithRequest:submissionRequest delegate:self] forKey:@"openConnection"];
}

- (void)submissionTimer:(NSTimer *)timer
{
	ISLog(@"submitSongs", @"submissionTimer:");
	
	if (_openConnection) {
		ISLog(@"submitSongs", @"Already connected to AudioScrobbler, ignoring submissionTimer firing.");
		return;
	}
	
	// make sure we have songs to submit first.
    if([_songSubmissionQueue count]) {
		
		// If we haven't already, we must handshake w/ the server.
		if(!_haveHandshaked)
			[self handshake];
		else 
			[self submitSongs];
    } else
		ISLog(@"submitSongs", @"Not attempting submission, submission queue empty.");
}

#pragma mark -

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	if (!_incomingData) {
		_incomingData = [[NSMutableData alloc] init];
	}
	[_incomingData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	[_incomingData release];
	_incomingData = nil;
	
	ISLog(@"connection:didFailWithError", @"Got %@ connection error: %@  Bytes recieved before error: %i", _haveHandshaked ? @"handshake" : @"submission", error, [_incomingData length]);
	
	[self setValue:[NSNumber numberWithBool:NO] forKey:@"haveHandshaked"];
	
	// depending on the error, we'll try again...
	// FIXME: we need to handle the different errors here.
	
	[self setValue:nil forKey:@"openConnection"];
	
	[self adjustBackOffTimerForSuccess:NO];
	// try again, maybe the error will go away...
	[self scheduleSubmissionTimerIfNeeded];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	// actually handle the data
	ISLog(@"connectionDidFinishLoading", @"Successful connection, %i bytes recieved.", [_incomingData length]);
	// build the response string from data...
	NSString *response = [[[NSString alloc] initWithData:_incomingData encoding:NSUTF8StringEncoding] autorelease];
	
	BOOL success = NO;
	
	if (_haveHandshaked) {
		success = [self handleSubmissionResponse:response];
	} else
		success = [self handleHandshakeResult:response];
	
	[_incomingData release];
	_incomingData = nil;
	
	[self setValue:nil forKey:@"openConnection"];
}

#pragma mark -

- (NSString *)escapedUsername {
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
	return [username stringByAddingPercentEscapesIncludingCharacters:@"&+"];
}

- (NSString *)handshakeBaseURLString {
	NSString *urlString = [[NSUserDefaults standardUserDefaults] stringForKey:@"url"];
	if (![urlString length]) {
		urlString = @"http://post.audioscrobbler.com/";
		NSLog(@"Failed to get URL from preferences, using default: %@");
	}
	// we could do validity checking here... but I *don't* think people
	// will be, or should be using this default.  This is mostly here
	// for legacy reasons.
	return urlString;
}

- (NSURL *)submitURL {
	// first we check our submission URL (which we got from the handshake)
	if (![_submitURLString length]) {
		// FIXME: default will have to reflect protocol version
		[self setValue:@"http://post.audioscrobbler.com/v1.1.php" forKey:@"submitURLString"];
		NSLog(@"Error: empty submitURLString, using default: %@ (submission may fail as a result).");
	}
	// we could do further URL validation... but I don't think it's really necessary.
	return [NSURL URLWithString:_submitURLString];
}

#pragma mark -

- (void)adjustBackOffTimerForSuccess:(BOOL)success {
	if (success)
		_exponentialBackOffDelay = 0; // no delay.
	else if (_exponentialBackOffDelay < 60)
		_exponentialBackOffDelay = 60; // if it's less than a minute, make it so.
	else {
		_exponentialBackOffDelay *= 2; // double our wait
		int twoHours = 60 * 60 * 2;
		if (_exponentialBackOffDelay >= twoHours)
			_exponentialBackOffDelay = twoHours; // cap our longest wait at two hours.
	}
}

- (void)updateBadAuthenticationCountWithSuccess:(BOOL)successfulAuthentication {
	if (successfulAuthentication)
		_consecutiveBadAuthentications = 0; // on success, reset.
	else
		_consecutiveBadAuthentications++; // otherwise increment
	
	// Only show dialog if we get BADAUTH twice in a row.
	if (_consecutiveBadAuthentications > 1) {
		[[NSApp delegate] showBadCredentialsDialog];
		_consecutiveBadAuthentications = 0; // reset counter
	}
}

- (NSString *)md5hash:(NSString *)input
{
	unsigned char *hash = MD5([input cString], [input cStringLength], NULL);
	
	NSMutableString *hashString = [NSMutableString string];
	
    // Convert the data returned into a string
    for (int i = 0; i < MD5_DIGEST_LENGTH; i++) {
		//NSLog(@"Appending %X to hashString (currently %@)", *hash, hashString);
		[hashString appendFormat:@"%02x", *hash++];
	}
	
    //NSLog(@"Returning hash... %@ for input: %@", hashString, input);
    return hashString;
}

- (void)writeUnsubmittedSongsToDisk {
	ISLog(@"writeUnsubmittedSongsToDisk", @"%i songs", [_songSubmissionQueue count]);
	
	NSString *filePath = [[[NSApp delegate] appSupportDirectory] stringByAppendingString:UNSUBMITTED_SONGS_FILE];
	if (![_songSubmissionQueue writeToFile:filePath atomically:YES])
		NSLog(@"Failed to write UnsubmittedSongs.plist to disk. (%@)", filePath);
}

@end
