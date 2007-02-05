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
#import <openssl/sha.h>
#import <openssl/md5.h>
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
#import <CommonCrypto/CommonDigest.h>
#else
// We define our own prototypes, because the CommonCrypto ones are explicitly
// marked extern which prevents them from being weak linked.
typedef unsigned char CC_SHA512_CTX[256];
#define CC_SHA512_DIGEST_LENGTH		64			/* digest length in bytes */
extern int CC_SHA512_Init(CC_SHA512_CTX *c)  __attribute__((weak_import));
extern int CC_SHA512_Update(CC_SHA512_CTX *c, const void *data, uint32_t len)  __attribute__((weak_import));
extern int CC_SHA512_Final(unsigned char *md, CC_SHA512_CTX *c)  __attribute__((weak_import));
#endif

#import "BBNetUpdateDownloadController.h"

__private_extern__ NSString *BBNetUpdateDidFinishUpdateCheck;

static BBNetUpdateDownloadController *gDLInstance = nil;

@implementation BBNetUpdateDownloadController

+ (void)downloadTo:(NSString*)file from:(NSString*)url withHashInfo:(NSDictionary*)hash
{
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
   [bbDownload cancel];
   [self close];
}

- (void)startDownload
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_url
            cachePolicy:NSURLRequestReloadIgnoringCacheData
            timeoutInterval:60.0];
    
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"BBNetUpdateVersion"];
    if (!ver) {
        if (!(ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]))
            ver = @"";
    }
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (!build)
        build = ver;
    
    NSString *agent = [NSString stringWithFormat:@"%@ %@/%@ (Macintosh; U; %@ Mac OS X)",
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"], ver, build,
        #ifdef __ppc__
        @"PPC"
        #elif defined(__i386__)
        @"Intel"
        #else
        #error Unknown architecture
        #endif
        ];
    
    [request setValue:agent forHTTPHeaderField:@"User-Agent"];
    
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
            
            int bytes;
            while ((bytes = read(fd, buf, sb.st_blksize)) > 0)
                (void)h.update(ctx, buf, bytes);
            
            (void)h.final(h.digest, ctx);
            
            free(buf);
        }
        close(fd);
        
        const char *expectedDigest = [hash UTF8String];
        unsigned expectedLen = strlen(expectedDigest);
        
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

// NSURLDownload protocol

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
    _totalBytes = (typeof(_totalBytes))[response expectedContentLength];
    if (_totalBytes > 0.0) {
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
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    if (bbHash && NO == [self hashFile:bbTmpFile using:bbHash]) {
        NSDictionary *info = [NSDictionary dictionaryWithObject:
            NSLocalizedStringFromTable(@"Hash failed: the file may be corrupt or invalid.", @"BBNetUpdate", @"")
            forKey:NSLocalizedDescriptionKey];
        
        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:info];
        [self download:download didFailWithError:error];
        return;
    }
    
    // Move the temp file to the final location
    (void)[[NSFileManager defaultManager] movePath:bbTmpFile toPath:_file handler:nil];
    [self close];
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(unsigned)length;
{
   if (_totalBytes > 0.0) {
       float recvdBytes = ((float)length / _totalBytes) * 100.0;
       [progressBar incrementBy:recvdBytes];
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

- (void)endAlertSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
   if ((void*)-1 == contextInfo) {
      // Error - close the parent
      [NSTimer scheduledTimerWithTimeInterval:0.02 target:self
            selector:@selector(close) userInfo:nil repeats:NO];
   }
}

@end
