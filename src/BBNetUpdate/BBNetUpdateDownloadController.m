/*
* Copyright 2002,2006 Brian Bergstrand.
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

#import <sys/types.h>
#import <sys/fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#include <openssl/evp.h>
#include <openssl/err.h>

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
    NSURLRequest *request = [NSURLRequest requestWithURL:_url
            cachePolicy:NSURLRequestReloadIgnoringCacheData
            timeoutInterval:60.0];
   
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
    
    EVP_MD_CTX ctx;
    unsigned digest_len;
    unsigned char digest[EVP_MAX_MD_SIZE];
    
    const EVP_MD *md;
    NSString *hash = [hashInfo objectForKey:@"SHA1"];
    if (hash) {
        md = EVP_sha1();
    } else if ((hash = [hashInfo objectForKey:@"MD5"])) {
        md = EVP_md5();
    } else
        return (YES); // unknown method, let it pass
    
    struct stat sb;
    if (0 != stat([path fileSystemRepresentation], &sb))
        return (NO);
    
    bzero(digest, sizeof(digest));
    
    int fd = open([path fileSystemRepresentation], O_RDONLY,  0);
    if (fd > -1) {
        char *buf = malloc(sb.st_blksize);
        if (buf) {
            (void)EVP_DigestInit(&ctx, md);
            
            int bytes;
            while ((bytes = read(fd, buf, sb.st_blksize)) > 0)
                (void)EVP_DigestUpdate(&ctx, buf, bytes);
            
            (void)EVP_DigestFinal(&ctx, digest, &digest_len);
            
            free(buf);
        }
        close(fd);
        
        const char *expectedDigest = [hash UTF8String];
        unsigned expectedLen = strlen(expectedDigest);
        
        char digestString[sizeof(digest) * 4];
        int i, j;
        for (i = j = 0; i < digest_len; ++i)
            j += sprintf((digestString + j), "%02x", digest[i]);
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
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithCString:tmp encoding:NSASCIIStringEncoding]];
    [download setDestination:path allowOverwrite:NO];
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
