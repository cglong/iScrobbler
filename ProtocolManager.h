//
//  ProtocolManager.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/04.
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
    // Resubmission timer
    NSTimer *resubmitTimer;
    KeyChain *myKeyChain;
    // The  object that will do the data transmission
    NSURLConnection *myConnection;
    // Received data
    NSMutableData *myData;
    // Handshake state
    enum {hs_needed, hs_inprogress, hs_delay, hs_valid} hsState;
    // Dealy time until next Handshake attempt
    float handshakeDelay;
    // Re-submission time
    float nextResubmission;
    // Was the last result bad auth?
    BOOL lastAttemptBadAuth;
    // Is the network available?
    BOOL isNetworkAvailable;
}

+ (ProtocolManager*)sharedInstance;

- (void)submit:(id)sender;

- (NSString*)clientVersion;

- (NSString*)userName;

- (SongData*)lastSongSubmitted;

- (NSString *)lastHandshakeResult;

- (NSString *)lastHandshakeMessage;

- (NSString *)lastSubmissionResult;

- (NSString *)lastSubmissionMessage;

- (NSString *)updateURL;

- (BOOL)validHandshake;

- (BOOL)updateAvailable;

@end

@protocol ProtocolManagerDelgate

- (NSString*)proxyUserName;
- (NSString*)proxyUserAuthentication;

@end

@interface SongData (ProtocolManagerAdditions)

// Tests to see if the song is ready to submit
- (BOOL)canSubmit;

@end

#define PM_NOTIFICATION_HANDSHAKE_COMPLETE @"PMHandshakeComplete"
#define PM_NOTIFICATION_BADAUTH @"PMBadAuth"
#define PM_NOTIFICATION_SUBMIT_COMPLETE @"PMSubmitComplete"

// Handshake and Submission result values
#define HS_RESULT_OK @"OK"
#define HS_RESULT_UPDATE_AVAIL @"Update"
#define HS_RESULT_FAILED @"Failed"
#define HS_RESULT_BADAUTH @"Bad Auth"
#define HS_RESULT_UNKNOWN @"Unknown"
