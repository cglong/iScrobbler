//
//  CURLHandle+SpecialEncoding.h
//  iScrobbler
//
//  Created by Sam Ley on Thu Apr 03 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CURLHandle/CURLHandle.h>

@interface CURLHandle (SpecialEncoding) 

- (void) setSpecialPostDictionary:(NSDictionary *)inDictionary encoding:(NSStringEncoding) inEncoding;

@end
