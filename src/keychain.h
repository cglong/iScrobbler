//
//  KeyChain.h
//  Fire
//
//  Created by Colter Reed on Thu Jan 24 2002.
//  Copyright (c) 2002 Colter Reed. All rights reserved.
//  Released under GPL.  You know how to get a copy.
//
//  Modified for use in iScrobbler by Sam Ley.
//  http://iscrobbler.sourceforge.net


#import <Foundation/Foundation.h>

ISEXPORT_CLASS
@interface KeyChain : NSObject {
}

+ (KeyChain*)defaultKeyChain;
// Throws a "KeyChain Error" NSException if a KeyChain error occurs
- (void)setGenericPassword:(NSString*)password forService:(NSString*)service account:(NSString*)account;
- (NSString*)genericPasswordForService:(NSString*)service account:(NSString*)account;
- (void)removeGenericPasswordForService:(NSString*)service account:(NSString*)account;

- (NSString*)internetPassswordForService:(NSString*)service account:(NSString**)account;

@end
