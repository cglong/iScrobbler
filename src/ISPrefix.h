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
#endif

#ifdef __ppc__
#define trap() asm volatile("trap")
#elif __i386__
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

#else

#define ISASSERT(condition,msg) {}
#define ISDEBUG_ONLY __unused
#define ISElapsedTimeInit() {}
#define ISStartTime() {}
#define ISEndTime() {}

#endif
