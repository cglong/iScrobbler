//
//  ScrobLog.h
//  iScrobbler
//
//  Copyright 2004,2005 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//
#import <Cocoa/Cocoa.h>

// Log levels
typedef enum {
    SCROB_LOG_CRIT    = 0,
    SCROB_LOG_ERR     = 1,
    SCROB_LOG_WARN    = 2,
    SCROB_LOG_INFO    = 3,
    SCROB_LOG_VERBOSE = 10,
    SCROB_LOG_TRACE   = 15,
} scrob_log_level_t;

__private_extern__ scrob_log_level_t ScrobLogLevel(void);
__private_extern__ void SetScrobLogLevel(scrob_log_level_t level);

__private_extern__ void ScrobLog (scrob_log_level_t level, NSString *fmt, ...);
#define ScrobTrace(fmt, ...) do { \
    NSString *newfmt = [NSString stringWithFormat:@"%s:%ld -- %@", __PRETTY_FUNCTION__, __LINE__, (fmt)]; \
    ScrobLog (SCROB_LOG_TRACE, newfmt, ## __VA_ARGS__); \
} while (0)

// ScrobLogCreateFlags
#define SCROB_LOG_OPT_SESSION_MARKER 0x00000001
__private_extern__ NSFileHandle* ScrobLogCreate(NSString *name, unsigned flags, unsigned limit);
__private_extern__ void ScrobLogTruncate(void);
