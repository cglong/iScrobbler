//
//  PreferenceController.h
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <AppKit/AppKit.h>


@class iScrobblerController;
@class KeyChain;
@class SongData;

@interface PreferenceController : NSObject
{
    IBOutlet NSSecureTextField *passwordField;
    IBOutlet NSWindow *preferencesWindow;
}

- (NSWindow *)preferencesWindow;
- (void)showPreferencesWindow;

- (IBAction)OK:(id)sender;
- (IBAction)cancel:(id)sender;

//- (IBAction)submitWebBugReport:(id)sender;
//- (IBAction)submitEmailBugReport:(id)sender;

//- (IBAction)copy:(id)sender;
@end

