//
//  ASXMLRPC.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/7/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

// Audioscrobbler XML RPC kernel

#import <Foundation/Foundation.h>

@interface ASXMLRPC : NSObject {
    NSXMLDocument *request, *response;
    NSMutableData *responseData;
    id adelegate, conn, representedObj;
    #ifdef WSHANDSHAKE
    NSTimer *hstimer;
    BOOL sendRequestAfterHS;
    #endif
}

+ (BOOL)isAvailable;

- (NSString*)method;
- (void)setMethod:(NSString*)method;

// Note most (if not all) methods take the following std. args (in order):
// 1) user name, 2) unix time stamp, 2) auth challenge
// This method creates an array containing these values and returns it ready
// to start adding custom params at index 3 (the 4th param)
// All params are strings
- (NSMutableArray*)standardParams;
- (void)setParameters:(NSMutableArray*)params;

- (void)sendRequest;
- (NSString*)response;

- (id)delegate;
- (void)setDelegate:(id)delegate;

// Object is retained, but not interpreted in anyway
- (id)representedObject;
- (void)setRepresentedObject:(id)obj;

@end

@interface NSObject (ASXMLRCPDelegate)

- (void)responseReceivedForRequest:(ASXMLRPC*)request;
- (void)error:(NSError*)error receivedForRequest:(ASXMLRPC*)request;

@end
