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
        if (!good) {
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
    [panel setExtensionHidden:NO];
    
    [panel beginSheetForDirectory:nil
        file:[[[self window] title] stringByAppendingPathExtension:@"html"]
        modalForWindow:[self window] modalDelegate:self
        didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (void)awakeFromNib
{
    [bindingsController setContent:[NSMutableDictionary dictionaryWithCapacity:1]];
    [[bindingsController selection] setValue:myWebView forKey:@"myWebView"];
    
    [myWebView setCustomUserAgent:[[ProtocolManager sharedInstance] userAgent]];
}

- (void)windowWillClose:(NSNotification*)note
{ 
    if (myURLPath)
        [[NSFileManager defaultManager] removeFileAtPath:[myURLPath path] handler:nil];
    [myURLPath release];
    myURLPath = nil;
    // Make sure the bindings are released
    [bindingsController setContent:nil];
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

@implementation WebView (ISProfileAdditions)

- (BOOL)isInProgress
{
    return ([self estimatedProgress] > 0.0 && [self estimatedProgress] < 1.0);
}

- (id)valueForUndefinedKey:(NSString*)key
{
    return (nil);
}

@end