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

#import <Security/SecKeychain.h>
#import <Security/SecKeychainItem.h>
#import "keychain.h"

// Not in SecKeychain header
extern CFStringRef SecCopyErrorMessageString(OSStatus, void*);

static KeyChain* defaultKeyChain = nil;

@interface KeyChain (KeyChainPrivate)
-(SecKeychainItemRef)copyGenericPasswordReferenceForService:(NSString *)service account:(NSString*)account;
@end

@implementation KeyChain

+ (KeyChain*) defaultKeyChain {
    return ( defaultKeyChain ? defaultKeyChain : (defaultKeyChain = [[KeyChain alloc] init]) );
}

- (id)init
{
    return (self = [super init]);
}

- (void)setGenericPassword:(NSString*)password forService:(NSString *)service account:(NSString*)account
{
    if ([service length] == 0 || [account length] == 0) {
        return ;
    }
    
    if (!password || [password length] == 0) {
        [self removeGenericPasswordForService:service account:account];
    } else {
        SecKeychainItemRef itemref = NULL;
        if ((itemref = [self copyGenericPasswordReferenceForService:service account:account])) {
            KCDeleteItem(itemref);
            CFRelease(itemref);
        }
        const char *kcService = [service UTF8String];
        const char *kcAccount = [account UTF8String];
        const char *kcPass = [password UTF8String];
        OSStatus ret = SecKeychainAddGenericPassword(NULL, strlen(kcService), kcService,
            strlen(kcAccount), kcAccount, strlen(kcPass), kcPass, NULL);
        if (noErr != ret) {
            NSString *errorMsg = (NSString*)SecCopyErrorMessageString(ret, NULL);
            if (errorMsg)
                [errorMsg autorelease];
            else
                errorMsg = [NSString stringWithFormat:@"Unknown KeyChain error: %d.", ret];
            NSDictionary *info = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:ret]
                forKey:@"KeyChainErrorCode"];
            [[NSException exceptionWithName:NSLocalizedString(@"KeyChain Error", "")
                reason:errorMsg userInfo:info] raise];
        }
    }
}

- (NSString*)genericPasswordForService:(NSString *)service account:(NSString*)account
{
    OSStatus ret;

    if ([service length] == 0 || [account length] == 0) {
        return @"";
    }
    
    const char *kcService = [service UTF8String];
    const char *kcAccount = [account UTF8String];
    void *passwordData;
    UInt32 passwordLen;
    NSString *string = @"";
    ret = SecKeychainFindGenericPassword(NULL, strlen(kcService), kcService,
        strlen(kcAccount), kcAccount, &passwordLen, &passwordData, NULL);
    if (noErr == ret) {
        string = [[[NSString alloc] initWithBytes:passwordData length:passwordLen encoding:NSUTF8StringEncoding] autorelease];
        SecKeychainItemFreeContent(NULL, passwordData);
    }
    return (string);
}

- (void)removeGenericPasswordForService:(NSString *)service account:(NSString*)account
{
    SecKeychainItemRef itemref;
    if (itemref = [self copyGenericPasswordReferenceForService:service account:account]) {
        KCDeleteItem(itemref);
        CFRelease(itemref);
    }
}

@end

@implementation KeyChain (KeyChainPrivate)
- (SecKeychainItemRef)copyGenericPasswordReferenceForService:(NSString *)service account:(NSString*)account
{
    SecKeychainItemRef itemref;
    const char *kcService = [service UTF8String];
    const char *kcAccount = [account UTF8String];
    OSStatus ret = SecKeychainFindGenericPassword(NULL, strlen(kcService), kcService,
        strlen(kcAccount), kcAccount, NULL, NULL, &itemref);
    if (noErr != ret)
        itemref = NULL;
    return (itemref);
}
@end
