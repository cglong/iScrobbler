//
//  KeyChain.m
//  Fire
//
//  Created by Colter Reed on Thu Jan 24 2002.
//  Copyright (c) 2002 Colter Reed. All rights reserved.
//  Released under GPL.  You know how to get a copy.
//
//  Modified for use in iScrobbler by Sam Ley and Brian Bergstrand.
//  http://iscrobbler.sourceforge.net

#import <Security/SecKeychain.h>
#import <Security/SecKeychainItem.h>
#import "keychain.h"

static KeyChain* defaultKeyChain = nil;

@interface KeyChain (KeyChainPrivate)
-(SecKeychainItemRef)copyGenericPasswordReferenceForService:(NSString *)service account:(NSString*)account;
@end

@implementation KeyChain

+ (KeyChain*) defaultKeyChain {
    return ( defaultKeyChain ? defaultKeyChain : (defaultKeyChain = [[KeyChain alloc] init]) );
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if (defaultKeyChain == nil) {
            return ([super allocWithZone:zone]);
        }
    }

    return (defaultKeyChain);
}

- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (NSUInteger)retainCount
{
    return (NSUIntegerMax);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
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
            #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
            SecKeychainItemDelete(itemref);
            #else
            KCDeleteItem(itemref);
            #endif
            CFRelease(itemref);
        }
        const char *kcService = [service UTF8String];
        const char *kcAccount = [account UTF8String];
        const char *kcPass = [password UTF8String];
        OSStatus ret = SecKeychainAddGenericPassword(NULL, (UInt32)strlen(kcService), kcService,
            (UInt32)strlen(kcAccount), kcAccount, (UInt32)strlen(kcPass), kcPass, NULL);
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
    ret = SecKeychainFindGenericPassword(NULL, (UInt32)strlen(kcService), kcService,
        (UInt32)strlen(kcAccount), kcAccount, &passwordLen, &passwordData, NULL);
    if (noErr == ret) {
        string = [[[NSString alloc] initWithBytes:passwordData length:passwordLen encoding:NSUTF8StringEncoding] autorelease];
        SecKeychainItemFreeContent(NULL, passwordData);
    }
    #ifdef ScrobLog
    else {
        ScrobLog(SCROB_LOG_ERR, @"error retrieving password from keychain: '%@' (%d)",
            [(NSString*)SecCopyErrorMessageString(ret, NULL) autorelease], ret);
    }
    #endif
    return (string);
}

- (void)removeGenericPasswordForService:(NSString *)service account:(NSString*)account
{
    SecKeychainItemRef itemref;
    if (itemref = [self copyGenericPasswordReferenceForService:service account:account]) {
        #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
        SecKeychainItemDelete(itemref);
        #else
        KCDeleteItem(itemref);
        #endif
        CFRelease(itemref);
    }
}

- (NSString*)internetPassswordForService:(NSString*)service account:(NSString**)account
{
    // SecKeychainAttributeInfoForItemID
    
    OSStatus ret;

    if ([service length] == 0) {
        return @"";
    }
    
    const char *kcService = [service UTF8String];
    void *data;
    UInt32 len;
    NSString *string = @"";
    SecKeychainItemRef item;
    ret = SecKeychainFindInternetPassword(NULL, (UInt32)strlen(kcService), kcService,
        // security domain, account name, path, port
        0, NULL, 0, NULL, 0, NULL, 0, kSecAuthenticationTypeAny, kSecAuthenticationTypeAny, &len, &data, &item);
    if (noErr == ret) {
        string = [[[NSString alloc] initWithBytes:data length:len encoding:NSUTF8StringEncoding] autorelease];
        SecKeychainItemFreeContent(NULL, data);
        
        SecKeychainAttribute attr;
        attr.tag = kSecAccountItemAttr;
        attr.length = 0;
        attr.data = NULL;
        SecKeychainAttributeList attrs;
        attrs.count = 1;
        attrs.attr = &attr;
        ret = SecKeychainItemCopyContent(item, NULL, &attrs, &len, &data);
        if (noErr == ret && attrs.attr->data) {
            if (account)
                *account = [[[NSString alloc] initWithBytes:attrs.attr->data length:attrs.attr->length encoding:NSUTF8StringEncoding] autorelease];
            SecKeychainItemFreeContent(&attrs, data);
        }
    }
    #ifdef ScrobLog
    else {
        ScrobLog(SCROB_LOG_ERR, @"error retrieving internet password from keychain: '%@' (%d)",
            [(NSString*)SecCopyErrorMessageString(ret, NULL) autorelease], ret);
    }
    #endif
    return (string);
}

@end

@implementation KeyChain (KeyChainPrivate)
- (SecKeychainItemRef)copyGenericPasswordReferenceForService:(NSString *)service account:(NSString*)account
{
    SecKeychainItemRef itemref;
    const char *kcService = [service UTF8String];
    const char *kcAccount = [account UTF8String];
    OSStatus ret = SecKeychainFindGenericPassword(NULL, (UInt32)strlen(kcService), kcService,
        (UInt32)strlen(kcAccount), kcAccount, NULL, NULL, &itemref);
    if (noErr != ret) {
        itemref = NULL;
        #ifdef ScrobLog
        ScrobLog(SCROB_LOG_ERR, @"error retrieving item from keychain: '%@' (%d)",
            [(NSString*)SecCopyErrorMessageString(ret, NULL) autorelease], ret);
        #endif
    }
    return (itemref);
}
@end
