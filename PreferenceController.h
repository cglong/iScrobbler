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

extern NSString *CDCNumSongsKey;

@interface PreferenceController : NSWindowController
{
    IBOutlet NSTextField *numRecentSongsField;
    IBOutlet NSTextField *username;
    IBOutlet NSSecureTextField *password;
    IBOutlet NSTextField *passwordStored;
    IBOutlet NSTextField *lastResultShortField;
    IBOutlet NSTextView *lastResultLongField;
    IBOutlet NSTextField *lastSongSubmitted;
    IBOutlet NSTextView *lastResultDataField;
    IBOutlet NSTextField *versionNumber;
    IBOutlet NSTextField *versionWarning;
    IBOutlet NSButton *updateButton;
    IBOutlet NSTableView *songDataTable;
    IBOutlet NSWindow *window;
//    IBOutlet NSButton *copyButton;
    NSUserDefaults *prefs;
    NSString *lastResult;
    NSString *lastResultLong;
    NSString *lastResultShort;
    NSNotificationCenter *nc;
    KeyChain * myKeyChain;
    NSMutableDictionary *songData;
    NSString * downloadURL;
   }
// -(IBAction)changeNumRecentSongs:(id)sender;
-(IBAction)apply:(id)sender;
-(IBAction)forgetPassword:(id)sender;
-(IBAction)OK:(id)sender;
-(IBAction)cancel:(id)sender;
-(IBAction)submitWebBugReport:(id)sender;
-(IBAction)submitEmailBugReport:(id)sender;
-(void)savePrefs;
-(void)setLastResult: (NSString *)newLastResult;
-(NSString *)lastResult;
-(void)setLastResultShort: (NSString *)newLastResultShort;
-(NSString *)lastResultShort;
-(void)setLastResultLong: (NSString *)newLastResultLong;
-(NSString *)lastResultLong;
-(void)setSongData: (NSMutableDictionary *)newSongData;
-(NSMutableDictionary *)songData;
-(void)handleLastResultChanged:(NSNotification *)aNotification;
-(void)updateFields;
-(void)generateResultText;
-(IBAction)queryiTunes:(id)sender;
-(IBAction)queryAudion:(id)sender;
-(IBAction)downloadUpdate:(id)sender;
-(NSString *)downloadURL;
-(void)setDownloadURL:(NSString *)newDownloadURL;
- (int)numberOfRowsInTableView:(NSTableView *)tableView;
- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
            row:(int)row;
//-(IBAction)copy:(id)sender;
@end

