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

#import "BBNetUpdateVersionCheckController.h"
#import "BBNetUpdateAskController.h"
#import "BBNetUpdateDownloadController.h"

static UInt32 BBCFVersionNumberFromString(CFStringRef);

static BBNetUpdateVersionCheckController *gVCInstance = nil;

__private_extern__ NSString *BBNetUpdateDidFinishUpdateCheck = @"BBNetUpdateDidFinishUpdateCheck";

@implementation BBNetUpdateVersionCheckController

+ (void)checkForNewVersion:(NSString*)appName interact:(BOOL)interact
{
   BOOL dontCheck = [[NSUserDefaults standardUserDefaults] boolForKey:@"BBNetUpdateDontAutoCheckVersion"];
   
   if (dontCheck && !interact)
      return;
   
   if (!gVCInstance) {
      gVCInstance =
         [[BBNetUpdateVersionCheckController alloc] initWithWindowNibName:@"BBNetUpdateVersionCheck"];
      if (!gVCInstance) {
         NSBeep();
         return;
      }
      
      [gVCInstance setWindowFrameAutosaveName:@"BBNetUpdateVersionCheck"];
   }
   
   if (![gVCInstance isWindowLoaded]) {
      // Load it
      (void)[gVCInstance window];
   }
   
   if ([(gVCInstance->progressBar) respondsToSelector:@selector(setDisplayedWhenStopped:)])
      [(gVCInstance->progressBar) setDisplayedWhenStopped:NO];
   
   if (!gVCInstance->bundleName) {
       if (!appName)
          gVCInstance->bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
       else
          gVCInstance->bundleName = appName;
       (void)[gVCInstance->bundleName retain];
   }
   
   gVCInstance->_interact = interact;
   gVCInstance->_didDownload = NO;
   gVCInstance->checkingVersion = YES;
   
   if (![[NSUserDefaults standardUserDefaults] boolForKey:@"BBNetUpdateDontAskConnect"] && !interact) {
      gVCInstance->_interact = YES;
      [BBNetUpdateAskController askUser:appName delagate:gVCInstance];
   }
   else
      [gVCInstance connect:nil];
}

+ (BOOL)isCheckInProgress
{
   return (gVCInstance && gVCInstance->checkingVersion);
}

+ (NSDate*)lastCheck
{
   NSString *dateString = [[NSUserDefaults standardUserDefaults] objectForKey:@"BBNetUpdateLastCheck"];
   if (!dateString)
      return (nil);
   
   return ( [NSDate dateWithString:dateString] );
}

- (void)connect:(id)sender
{
   NSURLHandle *handle;
   
   [fieldTitle setStringValue:
      NSLocalizedStringFromTable(@"BBNetUpdateCheckNewVersionTitle", @"BBNetUpdate", @"")];
   [fieldText setStringValue:@""];
   
   source = [[NSURL URLWithString:[[NSDictionary dictionaryWithContentsOfFile:
         [[NSBundle mainBundle] pathForResource:@"BBNetUpdateConfig" ofType:@"plist"]]
         objectForKey:@"BBNetUpdateDownloadInfoURL"]] retain];
   
   if (!source) {
      checkingVersion = NO;
      NSBeep();
      return;
   }
   
   [buttonDownload setEnabled:NO];
   [buttonMoreInfo setEnabled:NO];
   
   [boxDontCheck setState:
      [[NSUserDefaults standardUserDefaults] boolForKey:@"BBNetUpdateDontAutoCheckVersion"]];
   
   if (_interact)
      [[super window] makeKeyAndOrderFront:nil];
   
   handle = [source URLHandleUsingCache:YES];
   if (!handle) {
      checkingVersion = NO;
      NSBeep();
      return;
   }
   
   [[NSUserDefaults standardUserDefaults] setObject:[[NSDate date] description]
         forKey:@"BBNetUpdateLastCheck"];
   
   checkingVersion = YES;
   
   [handle addClient:self];
   
   [handle loadInBackground];
}

- (IBAction)cancel:(id)sender
{
   if (NSURLHandleLoadInProgress == [[source URLHandleUsingCache:YES] status])
      [[source URLHandleUsingCache:YES] cancelLoadInBackground];
   else
      [self close];
}

- (IBAction)download:(id)sender
{
   NSSavePanel *op;
   
   if (!verInfo)  {
      [self close];
      return;
   }
   
   // Prompt the user for the save dir.
   op = [NSSavePanel savePanel];
   
   [op beginSheetForDirectory:
      [[NSUserDefaults standardUserDefaults] stringForKey:@"BBNetUpdateLastSavePanelLocation"]
      file:[[verInfo objectForKey:@"File"] lastPathComponent]
      modalForWindow:[super window] modalDelegate:self
      didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (IBAction)showHideMoreInfo:(id)sender
{
   NSString *tempTitle;
   
   if (0 == [sender tag]){
      [sender setTag:1];
      // swap the titles
      tempTitle = [sender title];
      [sender setTitle:[sender alternateTitle]];
      [sender setAlternateTitle:tempTitle];
      // open the drawer
      [drawerMoreInfo open];
   } else {
      [sender setTag:0];
      // swap the titles back
      tempTitle = [sender title];
      [sender setTitle:[sender alternateTitle]];
      [sender setAlternateTitle:tempTitle];
      // close the drawer
      [drawerMoreInfo close];
   }
}

// NSWindowController
- (void)close;
{
   [verInfo release];
   [source release];
   
   [[NSUserDefaults standardUserDefaults]
      setBool:(NSOnState == [boxDontCheck state]) forKey:@"BBNetUpdateDontAutoCheckVersion"];
   
   checkingVersion = NO;
   
   if (!_didDownload) {
      // There wasn't a new version, or the user didn't download a new version
      // Either way, send the done notification
      
      [[NSNotificationCenter defaultCenter] postNotificationName:BBNetUpdateDidFinishUpdateCheck
         object:nil];
   }
   
   [super close];
}

// NSURLClient protocol

- (void)URLHandleResourceDidBeginLoading:(NSURLHandle *)sender
{
   [progressBar startAnimation:self];
   [progressBar displayIfNeeded];
}

- (void)URLHandleResourceDidCancelLoading:(NSURLHandle *)sender
{
   [self close];
}

- (void)URLHandleResourceDidFinishLoading:(NSURLHandle *)sender
{
   NSData *data = [sender resourceData];
   
   if (data) {
      CFStringRef *errstr = NULL;
      BOOL display = NO;
      
      verInfo = (NSDictionary*)CFPropertyListCreateFromXMLData(NULL, (CFDataRef)data, 
         kCFPropertyListImmutable, errstr);
      if (errstr)
         CFRelease(errstr);
      
      if (verInfo) {
         NSString *title, *moreInfo, *newVer, *netVer, *curVer;
         
         if (!(curVer = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"BBNetUpdateVersion"]))
            curVer = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
         netVer = [NSString stringWithString:[verInfo objectForKey:@"Version"]];
         
         if (curVer && netVer &&
            (BBCFVersionNumberFromString((CFStringRef)curVer) <
               BBCFVersionNumberFromString((CFStringRef)netVer))) {
            newVer = [NSString stringWithFormat:
               NSLocalizedStringFromTable(@"BBNetUpdateNewVersionAvail", @"BBNetUpdate", @""),
               curVer,
               bundleName,
               netVer];
            
            moreInfo = [[verInfo objectForKey:@"Notes"] objectForKey:@"English"];
            if (moreInfo) {
               [fieldMoreInfo setString:moreInfo];
               [buttonMoreInfo setEnabled:YES];
            }
         
            title = NSLocalizedStringFromTable(@"BBNetUpdateNewVersionTitle", @"BBNetUpdate", @"");
            
            // Make sure the user knows there is a new version
            display = YES;
         } else {
            title = NSLocalizedStringFromTable(@"BBNetUpdateNoNewVersionTitle", @"BBNetUpdate", @"");
            newVer = NSLocalizedStringFromTable(@"BBNetUpdateNoNewVersionAvail", @"BBNetUpdate", @"");
            
            [buttonDownload setTitle:@"OK"];
            
            [verInfo release]; verInfo = nil;
         }
         
         [buttonDownload setEnabled:YES];
         
         [fieldTitle setStringValue:title];
         [fieldText setStringValue:newVer];
         
         if (display && ![[super window] isVisible])
            [[super window] makeKeyAndOrderFront:nil];
      }
   } else  {
      // No version data
      [fieldTitle setStringValue:
         NSLocalizedStringFromTable(@"BBNetUpdateNoNewVersionTitle", @"BBNetUpdate", @"")];
   }
   
   if (![[super window] isVisible])
      [self close];
   
   [progressBar stopAnimation:self];
   [progressBar displayIfNeeded];
}

- (void)URLHandle:(NSURLHandle *)sender resourceDataDidBecomeAvailable:(NSData *)newBytes
{
}

- (void)URLHandle:(NSURLHandle *)sender resourceDidFailLoadingWithReason:(NSString *)reason
{   
   if (![[super window] isVisible])
      [[super window] makeKeyAndOrderFront:nil];
   
   // Alert the user
   NSBeginAlertSheet(NSLocalizedStringFromTable(@"BBNetUpdateDownloadErrorTitle", @"BBNetUpdate", @""),
      @"OK", nil, nil, [super window], self, nil, nil, nil,
   	NSLocalizedStringFromTable(@"BBNetUpdateDownloadError", @"BBNetUpdate", @""), reason);
   
   [fieldTitle setStringValue:
         NSLocalizedStringFromTable(@"BBNetUpdateNoNewVersionTitle", @"BBNetUpdate", @"")];
   
   [buttonDownload setTitle:@"OK"];
   [buttonDownload setEnabled:YES];
   
   [progressBar stopAnimation:self];
   [progressBar displayIfNeeded];
}

// Sheet handlers

- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
   NSString *file = [sheet filename];
   
   if(NSOKButton == returnCode && file) {
      [[NSUserDefaults standardUserDefaults] setObject:[sheet directory]
         forKey:@"BBNetUpdateLastSavePanelLocation"];
      
      [NSTimer scheduledTimerWithTimeInterval:0.02 target:self
            selector:@selector(close) userInfo:nil repeats:NO];
      
      _didDownload = YES;
      
      [BBNetUpdateDownloadController downloadTo:file from:[verInfo objectForKey:@"File"]
        withHashInfo:[verInfo objectForKey:@"Hash"]];
   }
}

@end

// Pulled the following from Apple's Core Foundation

#define DEVELOPMENT_STAGE 0x20
#define ALPHA_STAGE 0x40
#define BETA_STAGE 0x60
#define RELEASE_STAGE 0x80

#define MAX_VERS_LEN 10

static inline Boolean _isDigit(UniChar aChar) {
    return (((aChar >= (UniChar)'0') && (aChar <= (UniChar)'9')) ? true : false);
}

UInt32 BBCFVersionNumberFromString(CFStringRef versStr) {
    // Parse version number from string.
    // String can begin with "." for major version number 0.  String can end at any point, 
    // but elements within the string cannot be skipped.
    UInt32 major1 = 0, major2 = 0, minor1 = 0, minor2 = 0, stage = RELEASE_STAGE, build = 0;
    UniChar versChars[MAX_VERS_LEN];
    UniChar *chars = NULL;
    CFIndex len;
    UInt32 theVers;
    Boolean digitsDone = false;

    if (!versStr) {
        return 0;
    }

    len = CFStringGetLength(versStr);

    if ((len == 0) || (len > MAX_VERS_LEN)) {
        return 0;
    }

    CFStringGetCharacters(versStr, CFRangeMake(0, len), versChars);
    chars = versChars;
    
    // Get major version number.
    major1 = major2 = 0;
    if (_isDigit(*chars)) {
        major2 = *chars - (UniChar)'0';
        chars++;
        len--;
        if (len > 0) {
            if (_isDigit(*chars)) {
                major1 = major2;
                major2 = *chars - (UniChar)'0';
                chars++;
                len--;
                if (len > 0) {
                    if (*chars == (UniChar)'.') {
                        chars++;
                        len--;
                    } else {
                        digitsDone = true;
                    }
                }
            } else if (*chars == (UniChar)'.') {
                chars++;
                len--;
            } else {
                digitsDone = true;
            }
        }
    } else if (*chars == (UniChar)'.') {
        chars++;
        len--;
    } else {
        digitsDone = true;
    }

    // Now major1 and major2 contain first and second digit of the major version number as ints.
    // Now either len is 0 or chars points at the first char beyond the first decimal point.

    // Get the first minor version number.  
    if (len > 0 && !digitsDone) {
        if (_isDigit(*chars)) {
            minor1 = *chars - (UniChar)'0';
            chars++;
            len--;
            if (len > 0) {
                if (*chars == (UniChar)'.') {
                    chars++;
                    len--;
                } else {
                    digitsDone = true;
                }
            }
        } else {
            digitsDone = true;
        }
    }

    // Now minor1 contains the first minor version number as an int.
    // Now either len is 0 or chars points at the first char beyond the second decimal point.

    // Get the second minor version number. 
    if (len > 0 && !digitsDone) {
        if (_isDigit(*chars)) {
            minor2 = *chars - (UniChar)'0';
            chars++;
            len--;
        } else {
            digitsDone = true;
        }
    }

    // Now minor2 contains the second minor version number as an int.
    // Now either len is 0 or chars points at the build stage letter.

    // Get the build stage letter.  We must find 'd', 'a', or 'b' next, if there is anything next.
    if (len > 0) {
        if (*chars == (UniChar)'d') {
            stage = DEVELOPMENT_STAGE;
        } else if (*chars == (UniChar)'a') {
            stage = ALPHA_STAGE;
        } else if (*chars == (UniChar)'b') {
            stage = BETA_STAGE;
        } else {
            return 0;
        }
        chars++;
        len--;
    }

    // Now stage contains the release stage.
    // Now either len is 0 or chars points at the build number.

    // Get the first digit of the build number.
    if (len > 0) {
        if (_isDigit(*chars)) {
            build = *chars - (UniChar)'0';
            chars++;
            len--;
        } else {
            return 0;
        }
    }
    // Get the second digit of the build number.
    if (len > 0) {
        if (_isDigit(*chars)) {
            build *= 10;
            build += *chars - (UniChar)'0';
            chars++;
            len--;
        } else {
            return 0;
        }
    }
    // Get the third digit of the build number.
    if (len > 0) {
        if (_isDigit(*chars)) {
            build *= 10;
            build += *chars - (UniChar)'0';
            chars++;
            len--;
        } else {
            return 0;
        }
    }

    // Range check the build number and make sure we exhausted the string.
    if ((build > 0xFF) || (len > 0)) {
        return 0;
    }

    // Build the number
    theVers = major1 << 28;
    theVers += major2 << 24;
    theVers += minor1 << 20;
    theVers += minor2 << 16;
    theVers += stage << 8;
    theVers += build;

    return theVers;
}

