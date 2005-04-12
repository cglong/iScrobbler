//
//  ISProfileDocumentController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 4/10/2005.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <unistd.h>

#import "ISProfileDocumentController.h"
#import "ProtocolManager.h"

#import <WebKit/WebKit.h>

@interface NSURL (ISAdditions)
- (NSString*)stringValue;
@end

@implementation ISProfileDocumentController

- (BOOL)isInProgress
{
    return ([myWebView estimatedProgress] > 0.0 && [myWebView estimatedProgress] < 1.0);
}

- (void)showWindowWithHTMLData:(NSData*)data withWindowTitle:(NSString*)title
{
    // Save data to temp file
    char buf[] = "iScrobblerXXXXXX";
    char *name = mktemp(buf);
    if (name) {
        NSString *path = [NSString stringWithFormat:@"/tmp/%s.html", name];
        BOOL good = [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
        if (good) {
            myURLPath = [[NSURL fileURLWithPath:path] retain];
            if (myURLPath) {
                //[myWebView setResourceLoadDelegate:self];
                [super showWindow:nil];
                [[self window] setTitle:title];
                [myWebView takeStringURLFrom:myURLPath];
                return;
            }
        }
    }
    
    [[NSException exceptionWithName:NSFileHandleOperationException reason:@"Could not create temp file." userInfo:nil] raise];
}

- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode
   contextInfo:(void  *)contextInfo
{
    NSString *file = [sheet filename];

    if (NSOKButton == returnCode && file) {
        BOOL good = [[NSFileManager defaultManager] copyPath:[myURLPath path] toPath:file handler:nil];
        if (good) {
            [[NSUserDefaults standardUserDefaults] setObject:[sheet directory]
                forKey:@"Last Save Directory"];
        } else {
            NSRunAlertPanel(NSLocalizedString(@"File Creation Error", ""),
                [NSString stringWithFormat:
                    NSLocalizedString(@"Failed to create file %@.", ""),
                    file], @"OK", nil, nil);
        }
    }
}

- (IBAction)saveDocument:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setMessage:NSLocalizedString(@"Save iScrobbler Profile", "")];
    [panel setCanSelectHiddenExtension:YES];
    [panel setExtensionHidden:YES];
    
    NSString *dir = [[NSUserDefaults standardUserDefaults] objectForKey:@"Last Save Directory"];
    if (!dir || ![dir length])
        dir = [@"~/Documents/" stringByExpandingTildeInPath];
    [panel beginSheetForDirectory:dir
        file:[[[self window] title] stringByAppendingPathExtension:@"html"]
        modalForWindow:[self window] modalDelegate:self
        didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
    
}

- (void)awakeFromNib
{
    [myWebView setCustomUserAgent:[[ProtocolManager sharedInstance] userAgent]];
}

- (void)windowWillClose:(NSNotification*)note
{
    //[myWebView release];
    //myWebView = nil;
    if (myURLPath)
        [[NSFileManager defaultManager] removeFileAtPath:[myURLPath path] handler:nil];
    [myURLPath release];
    myURLPath = nil;
    [self autorelease];
}

- (void)webView:(WebView *)sender resource:(id)identifier didFailLoadingWithError:(NSError *)error fromDataSource:(WebDataSource *)dataSource
{
}

- (void)webView:(WebView *)sender resource:(id)identifier didReceiveResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)dataSource
{
}

- (void)webView:(WebView *)sender resource:(id)identifier didReceiveContentLength:(unsigned)length fromDataSource:(WebDataSource *)dataSource
{
}

@end

@implementation NSURL (ISAdditions)

- (NSString*)stringValue
{
    return ([self absoluteString]);
}

@end