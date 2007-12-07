//
//  ScrobLog.h
//  iScrobbler
//
//  Copyright 2004,2005,2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import <Cocoa/Cocoa.h>

// Log levels
enum {
    SCROB_LOG_CRIT    = 0,
    SCROB_LOG_ERR     = 1,
    SCROB_LOG_WARN    = 2,
    SCROB_LOG_INFO    = 3,
    SCROB_LOG_VERBOSE = 10,
    SCROB_LOG_TRACE   = 15,
};
typedef NSInteger scrob_log_level_t;

__private_extern__ scrob_log_level_t ScrobLogLevel(void);
__private_extern__ void SetScrobLogLevel(scrob_log_level_t level);

__private_extern__ void ScrobLogMsg(scrob_log_level_t level, NSString *fmt, ...);
#define ScrobLog(level, fmt, ...) do { \
    if (level <= ScrobLogLevel()) \
        ScrobLogMsg(level, fmt, ## __VA_ARGS__); \
} while(0)

#define ScrobTrace(fmt, ...) do { \
    if (ScrobLogLevel() >= SCROB_LOG_TRACE) { \
        NSString *newfmt = [NSString stringWithFormat:@"%s:%ld -- %@", __PRETTY_FUNCTION__, __LINE__, (fmt)]; \
        ScrobLogMsg(SCROB_LOG_TRACE, newfmt, ## __VA_ARGS__); \
    } \
} while (0)
#ifdef ISDEBUG
#define ScrobDebug(fmt, ...) do { \
    NSString *newfmt = [NSString stringWithFormat:@"%s:%ld -- %@", __PRETTY_FUNCTION__, __LINE__, (fmt)]; \
    ScrobLogMsg(SCROB_LOG_TRACE, newfmt, ## __VA_ARGS__); \
} while (0)
#else
#define ScrobDebug(fmt, ...)
#endif

// ScrobLogCreateFlags
#define SCROB_LOG_OPT_SESSION_MARKER 0x00000001
__private_extern__ NSFileHandle* ScrobLogCreate(NSString *name, unsigned flags, unsigned limit);
__private_extern__ void ScrobLogTruncate(void);
