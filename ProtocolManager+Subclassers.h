/*
 *  ProtocolManager+Subclassers.h
 *  iScrobbler
 *
 *  Created by Brian Bergstrand on 10/31/04.
//  Copyright 2004 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
 */

#import "ProtocolManager.h"

@class SongData;

// Subclassers must implement these methods
@interface ProtocolManager (SubclassRequired)

- (NSString*)handshakeURL;

- (NSString*)protocolVersion;

- (NSDictionary*)handshakeResponse:(NSString*)serverData;

- (NSDictionary*)submitResponse:(NSString*)serverData;

// returns an NSData object that is packaged and ready for submission.
// adds URL escaped title, artist and filename, and duration and time of
// submission field.
// The caller is still responsible for adding the username, password and version
// fields.
// submissionNumber is the number of this data in the submission queue. For single
// submissions this number will be 0.
- (NSData*)encodeSong:(SongData*)song submissionNumber:(unsigned)submissionNumber;

@end

// These are implemented in the abstract base,
// but may be overridden if necessary
@interface ProtocolManager (SubclassOptional)

- (NSString*)clientID;

//- (NSString*)userAgent;

- (float)minPercentagePlayed;

- (float)minTimePlayed;

- (float)handshakeMaxDelay;

- (BOOL)useBatchSubmission;

@end

// Handshake reponse keys
#define HS_RESPONSE_KEY_RESULT @"Result"
#define HS_RESPONSE_KEY_RESULT_MSG @"Result Msg"
#define HS_RESPONSE_KEY_MD5 @"MD5 Challenge"
#define HS_RESPONSE_KEY_SUBMIT_URL @"Submit URL"
#define HS_RESPONSE_KEY_UPDATE_URL @"Update URL"
// 1.1 only
#define HS_RESPONSE_KEY_INTERVAL @"Interval"
