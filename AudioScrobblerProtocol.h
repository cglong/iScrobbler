//
//  AudioScrobblerProtocol.h
//  iScrobbler
//
//  Created by Eric Seidel on Sat Oct 30 2004.
//

#import <Cocoa/Cocoa.h>

@class SongData;

@interface AudioScrobblerProtocol : NSObject {
	
	//a timer which will let us check for queue activity
    NSTimer *_submissionTimer;
	
	//stores data waiting to be sent to the server
    NSMutableArray *_songSubmissionQueue;
	
    // Result code to display in pref window if error.
    NSString *_lastResult;
    NSString *_lastHandshakeResult;
	
    // Have we handshaked yet?
    BOOL _haveHandshaked; // should this use *_handshakeResult instead?
	
	// Did we get BADAUTH last time we tried to submit?
	BOOL _lastAttemptBadAuth;
	
	// Data from handshake
	NSString *_md5Challenge;
	NSString *_submitURLString;
	
	int _exponentialBackOffDelay; // used to reduce server conjestion
	int _consecutiveBadAuthentications;
	
	NSMutableData *_incomingData;
	NSURLConnection *_openConnection;
}

- (void)scheduleSubmissionTimerIfNeeded;

- (void)queueSongForSubmission:(SongData *)song;
- (SongData *)peekNextSongForSubmission;
- (SongData *)popNextSongForSubmission;
- (void)writeUnsubmittedSongsToDisk;


// For subclasses to override:
- (BOOL)handshake; 	//connects to the server, executes a handshake transaction
- (BOOL)submitSongs; //connects to the server and submits the songs

@end
