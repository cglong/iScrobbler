//
//  KeyChain.m
//  Fire
//
//  Created by Colter Reed on Thu Jan 24 2002.
//  Copyright (c) 2002 Colter Reed. All rights reserved.
//  Released under GPL.  You know how to get a copy.
//
//  Modified for use in iScrobbler by Sam Ley.
//  http://iscrobbler.sourceforge.net

#import "KeyChain.h"

#import <Security/SecKeyChain.h>
#import <Security/SecKeyChainItem.h>

#define MAX_PASSWORD_LENGTH			127

@interface KeyChain (KeyChainPrivate)
- (KCItemRef)_genericPasswordReferenceForService:(NSString *)service account:(NSString*)account;
@end

static KeyChain *_defaultKeyChain = nil;

@implementation KeyChain

// FIXME: This should be a _sharedInstance method
+ (KeyChain *) defaultKeyChain {
	if (!_defaultKeyChain)
		_defaultKeyChain = [[self alloc] init];
	
    return _defaultKeyChain;
}

- (void)setGenericPassword:(NSString*)password forService:(NSString *)service account:(NSString*)account
{
	if (![service length] || ![account length]) return;
	
	if (![password length]) {
		[self removeGenericPasswordForService:service account:account];
	} else {
		OSStatus ret;
		SecKeychainItemRef itemref = NULL;
		if (itemref = [self _genericPasswordReferenceForService:service account:account]) {
			ret = SecKeychainItemModifyAttributesAndData(itemref, // item
														  NULL, // attributes
														  [password cStringLength], [password cString]); // data
		} else {		
			ret = SecKeychainAddGenericPassword(NULL, // keychain
												[service cStringLength], [service cString], // service
												[account cStringLength], [account cString], // name
												[password cStringLength], [password cString], // data
												NULL); // returned item
		}
		if (ret)
			NSLog(@"Error (%i) setting password for service: %@  account: %@", ret, service, account);
	}
}

- (NSString*)genericPasswordForService:(NSString *)service account:(NSString*)account
{
	if (![service length]|| ![account length]) return nil;
	
	char *passwordData = NULL;
    UInt32 passwordLength = 0;
	OSStatus status = SecKeychainFindGenericPassword(NULL, // keychain
													 [service cStringLength], [service cString],
													 [account cStringLength], [account cString],
													 &passwordLength, (void **)&passwordData,
													 NULL); // item ref
		
	if (status) {
		NSLog(@"Error (%i) fetching password for service: %@  account: %@", status, service, account);
		return nil;
	}
	
	return [NSString stringWithCString:passwordData length:passwordLength];
}
- (void)removeGenericPasswordForService:(NSString *)service account:(NSString*)account
{
    SecKeychainItemRef itemref = nil ;
    if (itemref = [self _genericPasswordReferenceForService:service account:account])
        SecKeychainItemDelete(itemref);
}
@end

@implementation KeyChain (KeyChainPrivate)
- (SecKeychainItemRef)_genericPasswordReferenceForService:(NSString *)service account:(NSString*)account
{
    SecKeychainItemRef itemref = nil;
	OSStatus status = SecKeychainFindGenericPassword(NULL, // keychain
													  [service cStringLength], [service cString], // service
													  [account cStringLength], [account cString], // name
													  0, NULL, // password data
													 &itemref); // item ref
	
	if (status) {
		NSLog(@"Error (%i) finding password for service: %@  account: %@", status, service, account);
		return nil;
	}
	
    return itemref;
}
@end
