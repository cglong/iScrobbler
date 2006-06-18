//
//  ProtocolManager_v11.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/31/04.
//  Copyright 2004-2006 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "ProtocolManager_v11.h"
#import "SongData.h"

@implementation ProtocolManager_v11

- (NSString*)handshakeURL
{
    NSString *url = [[prefs stringForKey:@"url"] stringByAppendingString:@"?hs=true"];
    NSString* escapedusername=[(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[self userName],
            NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) 	autorelease];
    
    url = [url stringByAppendingFormat:@"&u=%@", escapedusername];
    url = [url stringByAppendingFormat:@"&p=%@", [self protocolVersion]];
	url = [url stringByAppendingFormat:@"&v=%@", [self clientVersion]];
	url = [url stringByAppendingFormat:@"&c=%@", [self clientID]];
    
    return (url);
}

- (NSString*)protocolVersion
{
    return (@"1.1");
}

- (NSDictionary*)handshakeResponse:(NSString*)serverData
{
    NSArray *splitResult = [serverData componentsSeparatedByString:@"\n"];
    NSString *result = [splitResult objectAtIndex:0];
    NSString *hresult;
    NSString *md5 = @"", *submitURL = @"", *updateURL = @"";
    
    if ([result hasPrefix:@"UPTODATE"])
        hresult = HS_RESULT_OK;
    else if ([result hasPrefix:@"UPDATE"]) {
		hresult = HS_RESULT_UPDATE_AVAIL;
        updateURL = [[result componentsSeparatedByString:@" "] objectAtIndex:1];
    } else if ([result hasPrefix:@"FAILED"])
        hresult = HS_RESULT_FAILED;
    else if ([result hasPrefix:@"BADUSER"])
        hresult = HS_RESULT_BADAUTH;
    else
        hresult = HS_RESULT_UNKNOWN;
    
    if ([hresult isEqualToString:HS_RESULT_OK] ||
         [hresult isEqualToString:HS_RESULT_UPDATE_AVAIL]) {
		md5 = [splitResult objectAtIndex:1];
		submitURL = [splitResult objectAtIndex:2];
	}
    
    return ([NSDictionary dictionaryWithObjectsAndKeys:
        hresult, HS_RESPONSE_KEY_RESULT,
        serverData, HS_RESPONSE_KEY_RESULT_MSG,
        md5, HS_RESPONSE_KEY_MD5,
        submitURL, HS_RESPONSE_KEY_SUBMIT_URL,
        updateURL, HS_RESPONSE_KEY_UPDATE_URL,
        @"", HS_RESPONSE_KEY_INTERVAL, // Not handled
        nil]);
}

- (NSDictionary*)submitResponse:(NSString*)serverData
{
    NSArray *splitResult = [serverData componentsSeparatedByString:@"\n"];
    NSString *result = [splitResult objectAtIndex:0];
    NSString *hresult;
    
    if ([result hasPrefix:@"OK"])
        hresult = HS_RESULT_OK;
    else if ([result hasPrefix:@"FAILED"]) {
        if (0 == [result rangeOfString:@"Not all request variables are set" options:NSCaseInsensitiveSearch].length)
            hresult = HS_RESULT_FAILED;
        else
            hresult = HS_RESULT_FAILED_MISSING_VARS;
    } else if ([result hasPrefix:@"BADAUTH"])
        hresult = HS_RESULT_BADAUTH;
    else
        hresult = HS_RESULT_UNKNOWN;
    
    return ([NSDictionary dictionaryWithObjectsAndKeys:
        hresult, HS_RESPONSE_KEY_RESULT,
        serverData, HS_RESPONSE_KEY_RESULT_MSG,
        nil]);
}

- (NSData*)encodeSong:(SongData*)song submissionNumber:(unsigned)submissionNumber
{
    // URL escape relevant fields
	NSString * escapedtitle = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song title], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString * escapedartist = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song artist], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString * escapedalbum = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song album], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];
        
    NSString * escapedDate = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL,
            (CFStringRef)[[song postDate] descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"
                timeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"] locale:nil],
            NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];
    
    // populate the data
    return ([[NSString stringWithFormat:@"a[%u]=%@&t[%u]=%@&b[%u]=%@&m[%u]=%@&l[%u]=%@&i[%u]=%@&",
        submissionNumber, escapedartist, submissionNumber, escapedtitle, submissionNumber,
        escapedalbum, submissionNumber, [song mbid], submissionNumber, [song duration],
        submissionNumber, escapedDate] dataUsingEncoding:NSUTF8StringEncoding]);
}

- (id)init
{
    (void)[super init];
    return (self);
}

@end
