//
//  ScrobLog.h
//  iScrobbler
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

scrob_log_level_t ScrobLogLevel(void);
void SetScrobLogLevel(scrob_log_level_t level);

void ScrobLog (scrob_log_level_t level, NSString *fmt, ...);
#define ScrobTrace(fmt, ...) do { \
    NSString *newfmt = [NSString stringWithFormat:@"%s:%ld -- %@", __PRETTY_FUNCTION__, __LINE__, (fmt)]; \
    ScrobLog (SCROB_LOG_TRACE, newfmt, ## __VA_ARGS__); \
} while (0)


void ScrobLogTruncate(void);
