//
//  NSDictionary+httpEncoding.h
//  iScrobbler
//
//  Created by Sam Ley on Thu Apr 03 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSDictionary (httpEncoding) 

- (NSString *) specialFormatForHTTPUsingEncoding:(NSStringEncoding)inEncoding;
- (NSString *) specialFormatForHTTPUsingEncoding:(NSStringEncoding)inEncoding ordering:(NSArray *)inOrdering;

@end
