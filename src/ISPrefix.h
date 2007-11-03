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
