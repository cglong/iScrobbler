//
//  MobileDeviceSupport.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 7/12/2008.
//  Copyright 2008,2009 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#ifndef MOBILE_DEVICE_SUPPORT_H_
#define MOBILE_DEVICE_SUPPORT_H_

__private_extern__
int InitializeMobileDeviceSupport(const char *path, void **handle);

#ifdef __OBJC__

#if IS_SCRIPT_PROXY
typedef NSDistributedNotificationCenter MDSNotificationCenter;
#else
typedef NSNotificationCenter MDSNotificationCenter;
#endif

#endif // __OBJC__

#endif // MOBILE_DEVICE_SUPPORT_H_
