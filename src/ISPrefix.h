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
#else
#define ISASSERT(condition,msg) {}
#define ISDEBUG_ONLY __unused
#endif
