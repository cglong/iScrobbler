//
//  iScrobblerController.h
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>
#import "SongData.h"

@class PreferenceController;
@class ExtFSMedia;

@interface iScrobblerController : NSObject
{

    //the status item that will be added to the system status bar
    NSStatusItem *statusItem;

    //the menu attached to the status item
    IBOutlet NSMenu *theMenu;

    //a timer which will let us check iTunes every 10 seconds
    NSTimer *mainTimer;

    //the script to get information from iTunes
    NSAppleScript *script;

    //stores info about the songs iTunes has played
    NSMutableArray *songList;

    //the preferences window controller
    PreferenceController *preferenceController;

    // iPod update AppleScript (as text)
    NSString * iPodUpdateScript;
    
    // Preferences tracking object
    NSUserDefaults * prefs;

    NSNotificationCenter *nc;
    
    BOOL haveShownUpdateNowDialog;
    
    NSString *iPodMountPath;
    BOOL isIPodMounted;
    
    // iPod sync management
    NSDate *iTunesLastPlayedTime;
}

//called when mainTimer fires
-(void)mainTimer:(NSTimer *)timer;

//sync songList and theMenu
-(void)updateMenu;

//tells iTunes to play song that the user selected from the menu
-(IBAction)playSong:(id)sender;

//clears songs from theMenu and songList
-(IBAction)clearMenu:(id)sender;

//opens the preferences window
-(IBAction)openPrefs:(id)sender;

//opens Audioscrobbler in the default web browser
-(IBAction)openScrobblerHomepage:(id)sender;
-(IBAction)openUserHomepage:(id)sender;

-(IBAction)openStatistics:(id)sender;

-(IBAction)syncIPod:(id)sender;
-(IBAction)cleanLog:(id)sender;

-(void)handleChangedNumRecentTunes:(NSNotification *)aNotification;

-(NSString *)md5hash:(NSString *)input;

- (void)showApplicationIsDamagedDialog;
- (void)showBadCredentialsDialog;

@end

#import "ScrobLog.h"
