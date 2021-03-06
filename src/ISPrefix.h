//
//  ISPrefix.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/21/2007.
//  Copyright 2007-2009 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#include <AvailabilityMacros.h>
#ifndef MAC_OS_X_VERSION_10_6
#define MAC_OS_X_VERSION_10_6 1060
#endif

#define ISEXPORT __attribute__((visibility("default")))

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#import "ScrobLog.h"

#ifndef NSFoundationVersionNumber10_6
#define NSFoundationVersionNumber10_6 751.00
#endif

@interface NSDate (ISDateConversion)
- (NSCalendarDate*)GMTDate;
@end

@interface NSFileManager (ISExtensions)
- (NSString*)ISDestinationOfAliasAtPath:(NSString*)path error:(NSError**)error;
#define destinationOfAliasAtPath ISDestinationOfAliasAtPath
- (NSString*)iscrobblerSupportFolder;
@end

@interface NSXMLNode (ISAdditions)
- (NSInteger)integerValue; // this could be added at some point to 10.5.x or 10.6
@end

@interface NSWindow (ISAdditions)
- (void)scrobFadeOutAndClose;
#define fadeOutAndClose scrobFadeOutAndClose
@end

@interface NSWindowController (ISAdditions)
- (BOOL)scrobWindowShouldClose;
@end

@interface NSCalendarDate (ISAdditions)
- (NSNumber*)GMTOffset;
@end

NS_INLINE NSString* ISCPUArchitectureString() {
return (
#ifdef __ppc__
    @"PPC"
#elif defined(__i386__)
    @"Intel"
#elif defined(__x86_64__)
    @"Intel 64-bit"
#elif defined(__ppc64__)
    @"PPC 64-bit"
#else
#error unknown arch
#endif
);
}

extern CGFloat isUtilityWindowAlpha;
#define IS_UTIL_WINDOW_ALPHA isUtilityWindowAlpha

#if defined(__LP64__)
// The OBJC 2.0 64bit ABI can hide class symbols
#define ISEXPORT_CLASS __attribute__((visibility("default")))
#else
#define ISEXPORT_CLASS
#endif

#endif // OBJC

#if defined(__ppc__) || defined(__ppc64__)
#define IS_BADADDR (void*)0xdeadbeefUL
#define trap() asm volatile("trap")
#elif defined(__i386__) || defined(__x86_64__)
#define IS_BADADDR (void*)0xbaadf00dUL
#define trap() asm volatile("int $3")
#else
#error unknown arch
#endif

#if defined(obsolete) && __LP64__
#define IS_SCRIPT_PROXY 1
#endif

// Debug

#ifdef ISDEBUG

#define ISASSERT(condition,msg) do { \
if (0 == (condition)) { \
    ScrobLog(SCROB_LOG_CRIT, @"!!ASSERT FIRED!! (%s:%d,%s) cond=(%s) msg=(%s)", __FILE__, __LINE__, __FUNCTION__, #condition, (msg)); \
    trap(); \
} } while(0)
#define ISDEBUG_ONLY

#include <mach/mach.h>
#include <mach/mach_time.h>

#define ISElapsedTimeInit() \
u_int64_t start, end, diff; \
double abs2clockns; \
mach_timebase_info_data_t info; \
(void)mach_timebase_info(&info); \

#define ISStartTime() do { start = mach_absolute_time(); } while(0)
#define ISEndTime() do { \
    end = mach_absolute_time(); \
    diff = end - start; \
    abs2clockns = (double)info.numer / (double)info.denom; \
    abs2clockns *= diff; \
} while(0)
#define ISElapsedMicroSeconds() (abs2clockns / 1000.0)
#define ISElapsedMilliSeconds() (abs2clockns / 1000000.0)
#define ISElapsedSeconds() (abs2clockns / 1000000000.0)

#else

#define ISASSERT(condition,msg) {}
#define ISDEBUG_ONLY __unused
#define ISElapsedTimeInit() {}
#define ISStartTime() {}
#define ISEndTime() {}
#define ISElapsedMicroSeconds() 0
#define ISElapsedMilliSeconds() 0
#define ISElapsedSeconds() 0

#endif // ISDEBUG
