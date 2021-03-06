//
//  ScrobLog.m
//  iScrobbler
//
//  Copyright 2005-2009 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import <sys/stat.h>
#import "ScrobLog.h"

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
#import <dispatch/dispatch.h>
// serial queue to write log events
__private_extern__ dispatch_queue_t sldq = NULL;
static void __attribute__((constructor)) sldq_constructor(void)
{
    sldq = dispatch_queue_create("org.bergstrand.scroblog", NULL);
    dispatch_set_target_queue(sldq, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
}

#endif

__private_extern__ NSFileHandle *scrobLogFile = nil;

//Log Level
static NSDictionary *string_to_scrob_level = nil;
static NSString* const scrob_level_to_string [] = {
    @"CRIT",
    @"ERR",
    @"WARN",
    @"INFO",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"VERB",
    @"11",
    @"12",
    @"13",
    @"14",
    @"TRACE",
    @"INVAL"
};

NS_INLINE void CreateStringToLevelDict()
{
    if (!string_to_scrob_level) {
        string_to_scrob_level = [[NSDictionary alloc] initWithObjectsAndKeys:
            [NSNumber numberWithInt:SCROB_LOG_CRIT], scrob_level_to_string[SCROB_LOG_CRIT],
            [NSNumber numberWithInt:SCROB_LOG_ERR], scrob_level_to_string[SCROB_LOG_ERR],
            [NSNumber numberWithInt:SCROB_LOG_WARN], scrob_level_to_string[SCROB_LOG_WARN],
            [NSNumber numberWithInt:SCROB_LOG_INFO], scrob_level_to_string[SCROB_LOG_INFO],
            [NSNumber numberWithInt:SCROB_LOG_VERBOSE], scrob_level_to_string[SCROB_LOG_VERBOSE],
            [NSNumber numberWithInt:SCROB_LOG_TRACE], scrob_level_to_string[SCROB_LOG_TRACE],
            nil];
    }
}

#define UTF8_BOM_SIZE 3

__private_extern__ NSFileHandle* ScrobLogCreate_(NSString *name, unsigned flags, unsigned limit)
{
    NSString *path, *parent;
    NSArray *results;
    NSFileManager *fm;
    NSFileHandle *fh = nil;
    BOOL bom = NO;
    
    results = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    if ([results count]) {
        unsigned char utf8bom[] = {0xEF, 0xBB, 0xBF};

        fm = [NSFileManager defaultManager];

        parent = [[results objectAtIndex:0] stringByAppendingPathComponent:@"Logs"];
        // Create the dir if necessary
        if (![fm fileExistsAtPath:parent]) {
            [fm createDirectoryAtPath:parent withIntermediateDirectories:NO attributes:nil error:nil];
        }
        
        path = [parent stringByAppendingPathComponent:name];

        // Create the file
        if (![fm fileExistsAtPath:path]) {
            bom = YES;
            if (![fm createFileAtPath:path contents:nil attributes:nil])
                return (nil);
        }

        if (nil == (fh = [NSFileHandle fileHandleForWritingAtPath:path]))
            return (nil);
        
        int fd = [fh fileDescriptor];
        struct stat sb;
        if (0 == fstat(fd, &sb)) {
            NSInteger logMax = [[NSUserDefaults standardUserDefaults] integerForKey:@"Log Max"];
            if (logMax <= 0)
                logMax = limit;
            if (sb.st_size > logMax) {
                [fh truncateFileAtOffset:UTF8_BOM_SIZE];
            }
        }
        
        [fh seekToEndOfFile];

        NSData *d = nil;
        if (bom) {
            //Write UTF-8 BOM
            if ((d = [NSData dataWithBytes:utf8bom length:UTF8_BOM_SIZE])) {
                @try {
                [fh writeData:d];
                } @finally {}
            }
        }
        if (flags & SCROB_LOG_OPT_SESSION_MARKER) {
            d = [[NSString stringWithFormat:@"  **** New Session %@/%@ - Mac OS X %@ (%@) ****\n",
                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                    [[NSProcessInfo processInfo] operatingSystemVersionString],
                    ISCPUArchitectureString()]
                dataUsingEncoding:NSUTF8StringEncoding];
            if (d) {
                @try {
                [fh writeData:d];
                } @finally {}
            }
        }
    }
    
    CreateStringToLevelDict();
    
    return (fh);
}

static void ScrobLogWrite(NSString *level, NSString *msg)
{
    NSString *entry, *newline;
    NSData *data;
    
    if (!scrobLogFile) {
        if (nil == (scrobLogFile = ScrobLogCreate_(@"iScrobbler.log", SCROB_LOG_OPT_SESSION_MARKER, 0x200000))) {
            NSLog(@"%@", msg);
            return;
        }
        (void)[scrobLogFile retain];
    }

    if (![msg hasSuffix:@"\n"])
        newline = @"\n";
    else
        newline = @"";

    entry = [[NSString alloc] initWithFormat:@"[%@]-[%@] %@%@",
        [[NSDate date] descriptionWithCalendarFormat:@"%b %d, %Y %H:%M:%S %z"
        timeZone:[NSTimeZone localTimeZone] locale:nil],
        level, msg, newline];

    data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    [entry release];
    @try {
    [scrobLogFile writeData:data];
#ifdef ISDEBUG
    [scrobLogFile synchronizeFile];
#endif
    } @catch(id e) {}
}

__private_extern__ void ScrobLogCreate(NSString *name, unsigned flags, unsigned limit)
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
    dispatch_async(sldq, ^ {
    #endif
    
    scrobLogFile = [ScrobLogCreate_(name, flags, limit) retain];
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
    });
    #endif
}

__private_extern__ void ScrobLogTruncate(void)
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
    dispatch_async(sldq, ^ {
    #endif
    
    [scrobLogFile truncateFileAtOffset:UTF8_BOM_SIZE];
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
    });
    #endif
}

ISEXPORT void ScrobLogMsg(scrob_log_level_t level, NSString *fmt, ...)
{
    NSString *msg;
    va_list  args;
    
    if (level > SCROB_LOG_TRACE)
        level = SCROB_LOG_TRACE;
    
    va_start(args, fmt);
    msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
    dispatch_async(sldq, ^ {
    #endif

    ScrobLogWrite(scrob_level_to_string[level], msg);
    
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
    });
    #endif
    
    [msg release];
}

ISEXPORT scrob_log_level_t ScrobLogLevel(void)
{
    NSNumber *lev =  [string_to_scrob_level objectForKey:
#ifndef ISDEBUG
        [[NSUserDefaults standardUserDefaults] objectForKey:@"Log Level"]];
#else
        @"TRACE"];
#endif
    if (lev)
        return ([lev intValue]);
    
    return (SCROB_LOG_VERBOSE);
}

__private_extern__ void SetScrobLogLevel(scrob_log_level_t level)
{
    
}
