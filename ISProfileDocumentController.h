//
//  ISProfileDocumentController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 4/10/2005.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>

@class WebView;

@interface ISProfileDocumentController : NSWindowController
{
    IBOutlet WebView *myWebView;
    NSURL *myURLPath;
}

- (BOOL)isInProgress;

- (void)showWindowWithHTMLData:(NSData*)data withWindowTitle:(NSString*)title;

@end
