//
//  ScrobLog.m
//  iScrobbler
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//
#import <sys/stat.h>
#import "ScrobLog.h"

static NSFileHandle *scrobLogFile = nil;

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

static inline void CreateStringToLevelDict()
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

static void ScrobLogCreate(void)
{
    NSString *path, *parent;
    NSArray *results;
    NSFileManager *fm;
    BOOL bom = NO;
    
    results = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
    NSUserDomainMask, YES);
    if ([results count]) {
        unsigned char utf8bom[] = {0xEF, 0xBB, 0xBF};

        fm = [NSFileManager defaultManager];

        parent = [[results objectAtIndex:0] stringByAppendingPathComponent:@"Logs"];
        // Create the dir if necessary
        if (![fm fileExistsAtPath:parent]) {
            [fm createDirectoryAtPath:parent attributes:nil];
        }
        
        path = [parent stringByAppendingPathComponent:@"iScrobbler.log"];

        // Create the file
        if (![fm fileExistsAtPath:path]) {
            bom = YES;
            if (![fm createFileAtPath:path contents:nil attributes:nil])
                return;
        }

        scrobLogFile = [[NSFileHandle fileHandleForWritingAtPath:path] retain];
        if (!scrobLogFile)
            return;
        
        int fd = [scrobLogFile fileDescriptor];
        struct stat sb;
        if (0 == fstat(fd, &sb)) {
            int maxSize = [[NSUserDefaults standardUserDefaults] integerForKey:@"Log Max"];
            if (maxSize <= 0)
                maxSize = 0x200000 /* 2 MiB */;
            if (sb.st_size > maxSize) {
                ScrobLogTruncate();
            }
        }
        
        [scrobLogFile seekToEndOfFile];

        NSData *d;
        if (bom) {
            //Write UTF-8 BOM
            d = [NSData dataWithBytes:utf8bom length:UTF8_BOM_SIZE];
        } else {
            d = [@"    **** New Session ****    \n" dataUsingEncoding:NSUTF8StringEncoding];
        }
        NS_DURING
        [scrobLogFile writeData:d];
        NS_HANDLER
        // Write failed
        NS_ENDHANDLER
    }
}

static void ScrobLogWrite(NSString *level, NSString *msg)
{
    NSString *entry, *newline;
    NSData *data;
    
    if (!scrobLogFile) {
        ScrobLogCreate();
        if (!scrobLogFile) {
            NSLog(msg);
            return;
        }
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
    NS_DURING
    [scrobLogFile writeData:data];
#ifdef notyet
    [scrobLogFile synchronizeFile];
#endif
    NS_HANDLER
    // Write failed
    NS_ENDHANDLER
}

void ScrobLogTruncate(void)
{
    [scrobLogFile truncateFileAtOffset:UTF8_BOM_SIZE];
}

void ScrobLog (scrob_log_level_t level, NSString *fmt, ...)
{
    NSString *msg;
    va_list  args;
    
    if (level > SCROB_LOG_TRACE)
        level = SCROB_LOG_TRACE;
    
    if (level > ScrobLogLevel())
        return;
    
    va_start(args, fmt);
    msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    ScrobLogWrite(scrob_level_to_string[level], msg);
    [msg release];
}

scrob_log_level_t ScrobLogLevel(void)
{
    CreateStringToLevelDict();
    NSNumber *lev =  [string_to_scrob_level objectForKey:
        [[NSUserDefaults standardUserDefaults] objectForKey:@"Log Level"]];
    if (lev)
        return ([lev intValue]);
    
    return (SCROB_LOG_VERBOSE);
}

void SetScrobLogLevel(scrob_log_level_t level)
{
    
}
