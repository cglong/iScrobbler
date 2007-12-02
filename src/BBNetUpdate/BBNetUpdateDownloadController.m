/*
* Copyright 2002,2006,2007 Brian Bergstrand.
*
* Redistribution and use in source and binary forms, with or without modification, 
* are permitted provided that the following conditions are met:
*
* 1.	Redistributions of source code must retain the above copyright notice, this list of
*     conditions and the following disclaimer.
* 2.	Redistributions in binary form must reproduce the above copyright notice, this list of
*     conditions and the following disclaimer in the documentation and/or other materials provided
*     with the distribution.
* 3.	The name of the author may not be used to endorse or promote products derived from this
*     software without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
* WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
* AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE
* FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
* OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
* CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
* THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
* $Id$
*/

#import <AvailabilityMacros.h>
#import <sys/types.h>
#import <sys/fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
#import <CommonCrypto/CommonDigest.h>
#define SHA_DIGEST_LENGTH CC_SHA1_DIGEST_LENGTH
#define SHA_CTX CC_SHA1_CTX
#define SHA1_Init CC_SHA1_Init
#define SHA1_Update CC_SHA1_Update
#define SHA1_Final CC_SHA1_Final

#define MD5_DIGEST_LENGTH CC_MD5_DIGEST_LENGTH
#define MD5_CTX CC_MD5_CTX
#define MD5_Init CC_MD5_Init
#define MD5_Update CC_MD5_Update
#define MD5_Final CC_MD5_Final
#else
#import <openssl/sha.h>
#import <openssl/md5.h>
// We define our own prototypes, because the CommonCrypto ones are explicitly
// marked extern which prevents them from being weak linked.
typedef unsigned char CC_SHA512_CTX[256];
#define CC_SHA512_DIGEST_LENGTH		64			/* digest length in bytes */
extern int CC_SHA512_Init(CC_SHA512_CTX *c)  __attribute__((weak_import));
extern int CC_SHA512_Update(CC_SHA512_CTX *c, const void *data, uint32_t len)  __attribute__((weak_import));
extern int CC_SHA512_Final(unsigned char *md, CC_SHA512_CTX *c)  __attribute__((weak_import));
#endif

#import "BBNetUpdateVersionCheckController.h"
#import "BBNetUpdateDownloadController.h"

__private_extern__ NSString *BBNetUpdateDidFinishUpdateCheck;

static BBNetUpdateDownloadController *gDLInstance = nil;

static NSString* timeMonikers[] = {@"seconds", @"minutes", @"hours", nil};

@implementation BBNetUpdateDownloadController

+ (void)downloadTo:(NSString*)file from:(NSString*)url withHashInfo:(NSDictionary*)hash
{
    timeMonikers[0] = NSLocalizedStringFromTable(@"seconds", @"BBNetUpdate", @"");
    timeMonikers[1] = NSLocalizedStringFromTable(@"minutes", @"BBNetUpdate", @"");
    timeMonikers[2] = NSLocalizedStringFromTable(@"hours", @"BBNetUpdate", @"");
        
   if (!gDLInstance) {
      gDLInstance = [[BBNetUpdateDownloadController alloc] initWithWindowNibName:@"BBNetUpdateDownload"];
      if (!gDLInstance) {
         NSBeep();
         return;
      }
      
      [gDLInstance setWindowFrameAutosaveName:@"BBNetUpdateDownload"];
   }
   
   @try {
   gDLInstance->_url = [[NSURL alloc] initWithString:url];
   } @finally {}
   if (!gDLInstance->_url) {
      [gDLInstance release];
      gDLInstance = nil;
      
      NSBeep();
      return;
   }
   
    gDLInstance->_file = [file retain];
    gDLInstance->bbHash = [hash retain];
   
   if (![gDLInstance isWindowLoaded]) {
      // Load it
      (void)[gDLInstance window];
   }
   
   [gDLInstance startDownload];
}

- (IBAction)cancel:(id)sender
{
    // user chose to cancel a new version, delete the lastCheck key so they are still notified that a new version exists later
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BBNetUpdateLastCheck"];
   [bbDownload cancel];
   [self close];
}

- (void)startDownload
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_url
            cachePolicy:NSURLRequestReloadIgnoringCacheData
            timeoutInterval:60.0];
    
    
    
    [request setValue:[BBNetUpdateVersionCheckController userAgent] forHTTPHeaderField:@"User-Agent"];
    
    bbDownload = [[[NSURLDownload alloc] initWithRequest:request delegate:self] autorelease];
   
   if (!bbDownload) {
      NSBeep();
      [self close];
   }
   
   [progressBar setIndeterminate:YES];
   [progressBar startAnimation:self];
   [progressBar displayIfNeeded];
   
   [[super window] makeKeyAndOrderFront:nil];
}

// NSWindowController

- (void)close
{
   [_file release];
   [_url release];
   [bbTmpFile release];
   [bbHash release];
   
   [[NSNotificationCenter defaultCenter] postNotificationName:BBNetUpdateDidFinishUpdateCheck
         object:nil];
   
   [super close];
}

- (BOOL)hashFile:(NSString*)path using:(NSDictionary*)hashInfo
{
    BOOL good = NO;
    
    struct {    
        union {
            CC_SHA512_CTX sha512;
            SHA_CTX sha;
            MD5_CTX md5;
        } ctx;
        
        int digest_len;
        unsigned char digest[64];
        
        int (*init)(void *c);
        int (*update)(void *c, const void *data, unsigned long len);
        int (*final)(unsigned char *md, void *c);
    } h;
    void *ctx;
    
    NSString *hash = [hashInfo objectForKey:@"SHA512"];
    if (hash && NULL != CC_SHA512_Init) {
        ctx = &h.ctx.sha512;
        h.digest_len = CC_SHA512_DIGEST_LENGTH;
        h.init = (typeof(h.init))CC_SHA512_Init;
        h.update = (typeof(h.update))CC_SHA512_Update;
        h.final = (typeof(h.final))CC_SHA512_Final;
    } else if ((hash = [hashInfo objectForKey:@"SHA1"])) {
        ctx = &h.ctx.sha;
        h.digest_len = SHA_DIGEST_LENGTH;
        h.init = (typeof(h.init))SHA1_Init;
        h.update = (typeof(h.update))SHA1_Update;
        h.final = (typeof(h.final))SHA1_Final;
    } else if ((hash = [hashInfo objectForKey:@"MD5"])) {
        ctx = &h.ctx.md5;
        h.digest_len = MD5_DIGEST_LENGTH;
        h.init = (typeof(h.init))MD5_Init;
        h.update = (typeof(h.update))MD5_Update;
        h.final = (typeof(h.final))MD5_Final;
    } else
        return (YES); // unknown method, let it pass
    
    struct stat sb;
    if (0 != stat([path fileSystemRepresentation], &sb))
        return (NO);
    
    bzero(h.digest, sizeof(h.digest));
    
    int fd = open([path fileSystemRepresentation], O_RDONLY,  0);
    if (fd > -1) {
        char *buf = malloc(sb.st_blksize);
        if (buf) {
            (void)h.init(ctx);
            
            size_t bytes;
            while ((bytes = read(fd, buf, sb.st_blksize)) > 0)
                (void)h.update(ctx, buf, bytes);
            
            (void)h.final(h.digest, ctx);
            
            free(buf);
        }
        close(fd);
        
        const char *expectedDigest = [hash UTF8String];
        size_t expectedLen = strlen(expectedDigest);
        
        char digestString[sizeof(h.digest) * 4];
        int i, j;
        for (i = j = 0; i < h.digest_len; ++i)
            j += sprintf((digestString + j), "%02x", h.digest[i]);
        *(digestString + j) = 0;
        
        if (expectedLen == strlen(digestString) && 0 == strcmp(digestString, expectedDigest))
            good = YES;
    }
    
    return (good);
}

- (NSString*)progressString
{
    NSString *s;
    if (totalBytes > 0.0) {
        static NSString* const byteMonikers[] = {@"bytes", @"KB", @"MB", @"GB", @"TB", @"PB", nil};
        
        NSTimeInterval delta = [[NSDate date] timeIntervalSince1970] - epoch;
        double recvdPerSecond = recvdBytes / delta;
        int rsi, ri, ti, timei;
        for (rsi = 0; recvdPerSecond >= 1024.0; ++rsi)
            recvdPerSecond /= 1024.0;
        double recvdSize = recvdBytes;
        for (ri = 0; recvdSize >= 1024.0; ++ri)
            recvdSize /= 1024.0;
        double totalSize = totalBytes;
        for (ti = 0; totalSize >= 1024.0; ++ti)
            totalSize /= 1024.0;
        double remainingTime = (totalBytes - recvdBytes) / (recvdBytes / delta);
        for (timei = 0; remainingTime >= 60.0 && timei < 2 /*cap to hours*/; ++timei)
            remainingTime /= 60.0;
        
        s = [NSString stringWithFormat:
            NSLocalizedStringFromTable(@"%.1f %@ of %.1f %@ (%.1f %@/sec), About %.1f %@ remaining", @"BBNetUpdate", @"received of total (received/second), About time remaining"),
            recvdSize, byteMonikers[ri], totalSize, byteMonikers[ti], recvdPerSecond, byteMonikers[rsi],
            remainingTime, timeMonikers[timei]];
    } else
        s = [NSLocalizedStringFromTable(@"Establishing connection", @"BBNetUpdate", @"") stringByAppendingFormat:@"%C", 0x2026];
    return (s);
}

- (void)setProgressString:(NSString*)s
{
    // just for bindings completeness
}

// NSURLDownload protocol

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
    totalBytes = (typeof(totalBytes))[response expectedContentLength];
    if (totalBytes > 0.0) {
        epoch = [[NSDate date] timeIntervalSince1970];
        [progressBar stopAnimation:self];
        [progressBar setIndeterminate:NO];
        [progressBar setDoubleValue:0.0];
        [progressBar displayIfNeeded];
    }
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{   
   // Alert the user
   NSBeginInformationalAlertSheet(
        NSLocalizedStringFromTable(@"BBNetUpdateDownloadErrorTitle", @"BBNetUpdate", @""),
        @"OK", nil, nil, [super window],
        self, @selector(endAlertSheet:returnCode:contextInfo:), nil, (void*)-1,
        NSLocalizedStringFromTable(@"BBNetUpdateDownloadError", @"BBNetUpdate", @""), [error localizedDescription]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BBNetUpdateLastCheck"];
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    if (bbHash && NO == [self hashFile:bbTmpFile using:bbHash]) {
        NSDictionary *info = [NSDictionary dictionaryWithObject:
            NSLocalizedStringFromTable(@"Hash failed: the file may be corrupt or invalid.", @"BBNetUpdate", @"")
            forKey:NSLocalizedDescriptionKey];
        
        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:info];
        [self download:download didFailWithError:error];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BBNetUpdateLastCheck"];
        return;
    }
    
    // Move the temp file to the final location
    (void)[[NSFileManager defaultManager] movePath:bbTmpFile toPath:_file handler:nil];
    [self close];
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length;
{
   if (totalBytes > 0.0) {
       recvdBytes += (double)length;
       [progressBar incrementBy:((double)length / totalBytes) * 100.0];
       [self willChangeValueForKey:@"progressString"];
       [self didChangeValueForKey:@"progressString"];
    }
}

- (void)download:(NSURLDownload *)download decideDestinationWithSuggestedFilename:(NSString *)filename
{
    // Create a unique name incase the user somehow ended up with duplicate URL's.
    char tmp[] = "bbdlXXXXXX";
    (void*)mktemp(tmp);
    NSString *path = NSTemporaryDirectory();
    path = [path stringByAppendingPathComponent:
        ([path respondsToSelector:@selector(stringWithCString:encoding:)] ?
        [NSString stringWithCString:tmp encoding:NSASCIIStringEncoding] :
        [NSString stringWithCString:tmp])];
    [download setDestination:path allowOverwrite:NO];
    if ([download respondsToSelector:@selector(setDeletesFileUponFailure:)])
        [download setDeletesFileUponFailure:YES];
}

- (void)download:(NSURLDownload *)download didCreateDestination:(NSString*)filename
{
    bbTmpFile = [filename retain];
}

// Sheet handlers

- (void)endAlertSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
   if ((void*)-1 == contextInfo) {
      // Error - close the parent
      [NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(close) userInfo:nil repeats:NO];
   }
}

@end
