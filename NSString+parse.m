//
//  NSString+parse.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "NSString+parse.h"


@implementation NSString (Parse)

- (NSString *) stringBySelectingCharactersFromSet:(NSCharacterSet *)charSet
    /*"Makes a new string by removing all the characters in the receiver
    that aren't in charSet.  The string returned is autoreleased. If the
     receiver doesn't contain any characters from charSet, this method
     returns nil, not an empty  string.  For example, passing [NSCharacterSet
         decimalDigitsCharacterSet] will remove all non-digits from the result."*/
{
    NSMutableString *keepers = [[NSString alloc] init];
    NSString *result = [NSString string];
    NSScanner *scanner = [NSScanner scannerWithString:self];
    while (![scanner isAtEnd])
    {
        [scanner scanCharactersFromSet:charSet intoString:&keepers];
        [scanner scanUpToCharactersFromSet:charSet intoString:(NSString **) nil];
        result = [result stringByAppendingString:keepers];
    }
    [keepers release];
    return [result length] ? result : nil;
}
    


@end
