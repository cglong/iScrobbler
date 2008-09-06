//
//  ProtocolManager_v12.h
//  iScrobbler
//
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "ProtocolManager_v12.h"
#import "SongData.h"
#import "keychain.h"
#import "iScrobblerController.h"

@interface ProtocolManager (Private)

- (NSString*)md5Challenge;

@end

@implementation ProtocolManager_v12

- (NSString*)handshakeURL
{
    NSString *url = [[prefs stringForKey:@"url"] stringByAppendingString:@"?hs=true"];
    NSString *escapedusername=[(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[self userName],
            NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];
    
    url = [url stringByAppendingFormat:@"&p=%@", [self protocolVersion]];
	url = [url stringByAppendingFormat:@"&c=%@", [self clientID]];
    url = [url stringByAppendingFormat:@"&v=%@", [self clientVersion]];
    url = [url stringByAppendingFormat:@"&u=%@", escapedusername];
    
    NSString *timestamp = [NSString stringWithFormat:@"%qu", (u_int64_t)[[NSDate date] timeIntervalSince1970]];
    url = [url stringByAppendingFormat:@"&t=%@", timestamp];
    
    NSString *challenge = [[NSApp delegate] lastfmCredential];
    challenge = [challenge stringByAppendingString:timestamp];
    challenge = [[NSApp delegate] md5hash:challenge];
    url = [url stringByAppendingFormat:@"&a=%@", challenge];
    
    return (url);
}

- (NSString*)protocolVersion
{
    return (@"1.2");
}

- (NSDictionary*)handshakeResponse:(NSString*)serverData
{
    NSArray *splitResult = [serverData componentsSeparatedByString:@"\n"];
    NSString *result = [splitResult objectAtIndex:0];
    NSString *hresult;
    NSString *md5 = @"", *submitURL = @"", *nowPlayingURL = @"";
    
    if ([result hasPrefix:@"OK"])
        hresult = HS_RESULT_OK;
    else if ([result hasPrefix:@"FAILED"])
        hresult = HS_RESULT_FAILED;
    else if ([result hasPrefix:@"BADAUTH"])
        hresult = HS_RESULT_BADAUTH;
    else if ([result hasPrefix:@"BANNED"])
        hresult = HS_RESULT_FAILED;
    else if ([result hasPrefix:@"BADTIME"]) {
        hresult = HS_RESULT_FAILED;
        [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Your computer clock may be wrong.", "")
            message:NSLocalizedString(@"Last.fm submissions are disabled. Please verify the time, day of month, month and year.", "")];
        ScrobLog(SCROB_LOG_WARN, @"Your computer clock may be wrong. Please verify the time, day of month, month and year.");
    } else
        hresult = HS_RESULT_UNKNOWN;
    
    if ([hresult isEqualToString:HS_RESULT_OK]) {
		md5 = [splitResult objectAtIndex:1];
		nowPlayingURL = [splitResult objectAtIndex:2];
        submitURL = [splitResult objectAtIndex:3];
	}
    
    return ([NSDictionary dictionaryWithObjectsAndKeys:
        hresult, HS_RESPONSE_KEY_RESULT,
        serverData, HS_RESPONSE_KEY_RESULT_MSG,
        md5, HS_RESPONSE_KEY_MD5,
        submitURL, HS_RESPONSE_KEY_SUBMIT_URL,
        nowPlayingURL, HS_RESPONSE_KEY_NOWPLAYING_URL,
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
    } else if ([result hasPrefix:@"BADSESSION"])
        hresult = HS_RESULT_FAILED;
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
	NSString *escapedtitle = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song title], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString *escapedartist = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song artist], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString *escapedalbum = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song album], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];
    
    // populate the data
    unsigned trackNum = [[song trackNumber] unsignedIntValue];
    return ([[NSString stringWithFormat:@"a[%u]=%@&t[%u]=%@&i[%u]=%qu&o[%u]=%@&b[%u]=%@&m[%u]=%@&l[%u]=%u&n[%u]=%@&r[%u]=%@&",
        submissionNumber, escapedartist, submissionNumber, escapedtitle,
        submissionNumber, (u_int64_t)[[song postDate] timeIntervalSince1970],
        // P & L are the only valid codes currently
        // P == "song chosen by user" and L is a last.fm track
        submissionNumber, NO == [song isLastFmRadio] ? @"P" : [@"L" stringByAppendingString:[song lastFmAuthCode]], 
        submissionNumber, escapedalbum, submissionNumber, [song mbid],
        submissionNumber, [[song duration] unsignedIntValue], // required only when source is "P"
        submissionNumber, trackNum > 0 ? [song trackNumber] : @"",
        submissionNumber, [song lastFmRating]
        ] dataUsingEncoding:NSUTF8StringEncoding]);
}

- (NSData*)nowPlayingDataForSong:(SongData*)song
{
    // URL escape relevant fields
	NSString *escapedtitle = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song title], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString *escapedartist = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song artist], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];

    NSString *escapedalbum = [(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[song album], NULL,
        (CFStringRef)@"&+", kCFStringEncodingUTF8) autorelease];
    
    // populate the data
    unsigned trackNum = [[song trackNumber] unsignedIntValue];
    return ([[NSString stringWithFormat:@"s=%@&a=%@&t=%@&b=%@&m=%@&l=%u&n=%@&",
        [self authChallengeResponse], escapedartist, escapedtitle,
        escapedalbum, [song mbid],
        [[song duration] unsignedIntValue],
        trackNum > 0 ? [song trackNumber] : @""
        ] dataUsingEncoding:NSUTF8StringEncoding]);
}

- (NSString*)authChallengeResponse
{
    return ([self md5Challenge]);
}

- (id)init
{
    (void)[super init];
    return (self);
}

@end
