//
//  PreferenceController.h
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available in res/gpl.txt
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

@end

#define SCROB_PREFS_CHANGED @"iScrobbler Prefs Changed"
