//
//  NSString+parse.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Foundation/Foundation.h>

@interface NSString (iScrobblerAdditions)

- (NSString *)stringByAddingPercentEscapes;
- (NSString *)stringByAddingPercentEscapesIncludingCharacters:(NSString *)toIgnore;

- (NSString *)stringBySelectingCharactersFromSet:(NSCharacterSet *)charSet;

@end
