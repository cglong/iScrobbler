//
//  CURLHandle+SpecialEncoding.m
//  iScrobbler
//
//  Created by Sam Ley on Thu Apr 03 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "CURLHandle+SpecialEncoding.h"
#import "NSDictionary+httpEncoding.h"

@implementation CURLHandle (SpecialEncoding)

/*"	Set the dictionary of post options, and make the request be a HTTP POST, specifying the string encoding.
"*/
- (void) setSpecialPostDictionary:(NSDictionary *)inDictionary encoding:(NSStringEncoding) inEncoding
{
    NSString *postFields = @"";
    if (nil != inDictionary)
    {
        postFields = [inDictionary specialFormatForHTTPUsingEncoding:inEncoding];
    }
    [self setString:postFields forKey:CURLOPT_POSTFIELDS];
}



@end
