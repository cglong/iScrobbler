//
//  NSDictionary+httpEncoding.m
//  iScrobbler
//
//  Created by Sam Ley on Thu Apr 03 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "NSDictionary+httpEncoding.h"


@implementation NSDictionary (httpEncoding)

/*"	This category adds methods for dealing with HTTP input and output to an #NSDictionary.
"*/

/*"	Convert a dictionary to an HTTP-formatted string with the given encoding.
Spaces are turned into !{+}; other special characters are escaped with !{%};
keys and values are output as %{key}=%{value}; in between arguments is !{&}.
"*/

// In this category, keys are NOT URL ENCODED, just values!

- (NSString *) specialFormatForHTTPUsingEncoding:(NSStringEncoding)inEncoding
{
    return [self specialFormatForHTTPUsingEncoding:inEncoding ordering:nil];
}

/*"	Convert a dictionary to an HTTP-formatted string with the given encoding, as above.  The inOrdering parameter specifies the order to place the inputs, for servers that care about this.  (Note that keys in the dictionary that aren't in inOrdering will not be included.)  If inOrdering is nil, all keys and values will be output in an unspecified order.
"*/

- (NSString *)specialFormatForHTTPUsingEncoding:(NSStringEncoding)inEncoding ordering:(NSArray *)inOrdering
{
    NSMutableString *resultString = [NSMutableString string];
    NSEnumerator *keyEnumerator = inOrdering ? [inOrdering objectEnumerator] : [self keyEnumerator];
    id key = nil;
    CFStringEncoding cfStrEnc = CFStringConvertNSStringEncodingToEncoding(inEncoding);

    while ((key = [keyEnumerator nextObject]))
    {
        CFStringRef escapedObject =
		CFURLCreateStringByAddingPercentEscapes(NULL, // allocator
												(CFStringRef) [[self objectForKey:key] description], // original
												NULL, // ignore characters
												NULL, // legal chars to escape
												cfStrEnc); // encoding

        [resultString appendFormat:@"%@=%@&", key, escapedObject];
		CFRelease(escapedObject);
    }
    // Remove final "&" from string (if we actually made one)
    if ([resultString length])
        [resultString deleteCharactersInRange:NSMakeRange([resultString length]-1, 1)];
	
    return resultString;
}

@end
