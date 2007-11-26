//
//  ISPrefix.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/21/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#import "ScrobLog.h"

// implemented in PersistentSessionManager.m since that was the first to use it
@interface NSDate (ISDateConversion)
- (NSCalendarDate*)GMTDate;
@end

@interface NSFileManager (ISAliasExtensions)
- (NSString*)ISDestinationOfAliasAtPath:(NSString*)path error:(NSError**)error;
#define destinationOfAliasAtPath ISDestinationOfAliasAtPath
@end

@interface NSXMLElement (ISAdditions)
- (NSInteger)integerValue; // this could be added at some point to 10.5.x or 10.6
@end

NS_INLINE NSString* ISCPUArchitectureString() {
return (
#ifdef __ppc__
    @"PPC"
#elif defined(__i386__)
    @"Intel"
#elif defined(__x86_64__)
    @"Intel 64-bit"
#else
#error unknown arch
#endif
);
}

#if defined(__LP64__) || (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5)
#define LEOPARD_BEGIN
#define LEOPARD_END
#else
#define LEOPARD_BEGIN if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_4) {
#define LEOPARD_END }
#endif

#endif

#ifdef __ppc__
#define trap() asm volatile("trap")
#elif defined(__i386__) || defined(__x86_64__)
#define trap() asm volatile("int $3")
#else
#error unknown arch
#endif

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

#endif
