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
@class CURLHandle;
@class KeyChain;

@interface iScrobblerController : NSObject <NSURLHandleClient>
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

    //stores data waiting to be sent to the server
    NSMutableArray *songQueue;

    //the CURLHandle object that will do the data transmission
    CURLHandle * myURLHandle;

    //the preferences window controller
    PreferenceController *preferenceController;

    // Result code to display in pref window if error.
    NSString * lastResult;

    // Preferences tracking object
    NSUserDefaults * prefs;

    NSNotificationCenter *nc;
    KeyChain * myKeyChain;
}

// return the last result
-(NSString *)lastResult;
// set the last result
-(void)setLastResult:(NSString *)newResult;
-(void)changeLastResult:(NSString *)newResult;

//called when mainTimer fires
-(void)timer:(NSTimer *)timer;

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

// Queues the data up, determining when to send data, and when not to
- (void)queueData:(SongData *)song;

//connects to the server via CURLhandle and fetches the data
-(void)sendData:(SongData *)song;

-(void)handleChangedNumRecentTunes:(NSNotification *)aNotification;

-(NSString *)md5hash:(NSString *)input;

@end

