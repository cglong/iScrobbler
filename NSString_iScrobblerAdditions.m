//
//  NSString_iScrobblerAdditions.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "NSString_iScrobblerAdditions.h"


@implementation NSString (iScrobblerAdditions)

- (NSString *)stringByAddingPercentEscapes {
	return [self stringByAddingPercentEscapesIncludingCharacters:nil];
}

- (NSString *)stringByAddingPercentEscapesIncludingCharacters:(NSString *)addecCharacters {
	NSString *escapedString = (NSString *)
		CFURLCreateStringByAddingPercentEscapes(NULL, // allocator
												(CFStringRef)self, // original string
												NULL, // chars to ignore
												(CFStringRef)addecCharacters, // extra chars to escape
												kCFStringEncodingUTF8); // encoding
	return [escapedString autorelease];
}

- (NSString *)stringBySelectingCharactersFromSet:(NSCharacterSet *)charSet
    /*"Makes a new string by removing all the characters in the receiver
    that aren't in charSet.  The string returned is autoreleased. If the
     receiver doesn't contain any characters from charSet, this method
     returns nil, not an empty  string.  For example, passing [NSCharacterSet
         decimalDigitsCharacterSet] will remove all non-digits from the result."*/
{
    NSMutableString *keepers = nil;
    NSMutableString *result = [NSMutableString string];
    NSScanner *scanner = [NSScanner scannerWithString:self];
    while (![scanner isAtEnd])
    {
        [scanner scanCharactersFromSet:charSet intoString:&keepers];
        [scanner scanUpToCharactersFromSet:charSet intoString:(NSString **) nil];
		[result appendString:keepers];
    }
    return [result length] ? result : nil;
}
@end
