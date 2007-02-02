//
//  ProtocolManager.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/04.
//  Copyright 2004-2007 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>

#import "SongData.h"

@class KeyChain;
@protocol ProtocolManagerDelgate;

// This is an abstract class cluster

@interface ProtocolManager : NSObject {
    NSUserDefaults *prefs;
    KeyChain *myKeyChain;

@private
    // Songs that have been submitted
    id inFlight;
    // Last song submitted
    SongData *lastSongSubmitted;
    // Handshake reply data
    id hsResult;
    // Last submission reply data
    id submitResult;
    // Timer to kill "stuck" handshake
    NSTimer *killTimer;
    NSTimer *resubmitTimer;
    NSTimer *handshakeTimer;
    // The  object that will do the data transmission
    NSURLConnection *myConnection;
    // Received data
    NSMutableData *myData;
    NSFileHandle *subLog;
    // Handshake state
    enum {hs_needed, hs_inprogress, hs_delay, hs_valid} hsState;
    // Delay interval until next Handshake attempt
    float handshakeDelay;
    // Re-submission time
    float nextResubmission;
    // Count of consecutive BADAUTH repsonses
    int subBadAuth, hsBadAuth;
    // Is the network available?
    BOOL isNetworkAvailable;
    // Counters
    unsigned submissionAttempts, successfulSubmissions, missingVarErrorCount, maxTracksPerSub;
}

+ (ProtocolManager*)sharedInstance;

- (BOOL)isNetworkAvailable;

- (void)submit:(id)sender;

- (NSString*)clientVersion;

- (NSString*)userName;

- (NSString*)userAgent;

- (SongData*)lastSongSubmitted;

- (NSString *)lastHandshakeResult;

- (NSString *)lastHandshakeMessage;

- (NSString *)lastSubmissionResult;

- (NSString *)lastSubmissionMessage;

- (BOOL)validHandshake;

- (unsigned)submissionAttemptsCount;

- (unsigned)successfulSubmissionsCount;

@end

@interface SongData (ProtocolManagerAdditions)

// Tests to see if the song is ready to submit
- (BOOL)canSubmit;
- (NSTimeInterval)submitIntervalFromNow;

@end

#define PM_NOTIFICATION_HANDSHAKE_START @"PMHandshakeStart"
#define PM_NOTIFICATION_HANDSHAKE_COMPLETE @"PMHandshakeComplete"
#define PM_NOTIFICATION_BADAUTH @"PMBadAuth"
#define PM_NOTIFICATION_SUBMIT_COMPLETE @"PMSubmitComplete"
#define PM_NOTIFICATION_SUBMIT_START @"PMSubmitStart"
#define PM_NOTIFICATION_NETWORK_STATUS @"PMNetworkStatus"
#define PM_NOTIFICATION_NETWORK_STATUS_KEY @"PMNetworkStatusKey"
#define PM_NOTIFICATION_NETWORK_MSG_KEY @"PMNetworkMsgKey" 

// Handshake and Submission result values
#define HS_RESULT_OK @"OK"
#define HS_RESULT_UPDATE_AVAIL @"Update"
#define HS_RESULT_FAILED @"Failed"
#define HS_RESULT_BADAUTH @"Bad Auth"
#define HS_RESULT_UNKNOWN @"Unknown"
// This error is usually the result of a proxy truncating our POST submisssion
#define HS_RESULT_FAILED_MISSING_VARS @"Failed: Missing vars"
