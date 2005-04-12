//
//  iScrobblerController.h
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>

@class PreferenceController;
@class SongData;

@interface iScrobblerController : NSObject
{

    //the status item that will be added to the system status bar
    NSStatusItem *statusItem;

    //the menu attached to the status item
    IBOutlet NSMenu *theMenu;

    //the script to get information from iTunes
    NSAppleScript *script;

    //stores info about the songs iTunes has played
    NSMutableArray *songList;
    
    // Song that iTunes is currently playing (or pausing)
    SongData *currentSong;
    NSTimer *currentSongQueueTimer;

    //the preferences window controller
    PreferenceController *preferenceController;
    
    // Preferences tracking object
    NSUserDefaults * prefs;

    NSNotificationCenter *nc;
    
    BOOL haveShownUpdateNowDialog;
    
    NSString *iPodMountPath;
    BOOL isIPodMounted;
    
    // iPod sync management
    NSDate *iTunesLastPlayedTime;
    
    NSArray *iTunesPlaylists;
}

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
-(IBAction)openTopLists:(id)sender;

-(IBAction)cleanLog:(id)sender;

-(NSString *)md5hash:(NSString *)input;

-(SongData*)nowPlaying;

- (void)showApplicationIsDamagedDialog;
- (void)showBadCredentialsDialog;

@end

@interface NSMutableArray (iScrobblerContollerFifoAdditions)
    - (void)push:(id)obj;
    - (void)pop;
    - (id)peek;
@end

void ISDurationsFromTime(unsigned int time, unsigned int *days, unsigned int *hours,
    unsigned int *minutes, unsigned int *seconds);

#ifdef ISDEBUG
#define ISASSERT(condition,msg) do { \
if (0 == (condition)) { \
    asm volatile("trap"); \
} } while(0)
#else
#define ISASSERT(condition,msg) {}
#endif

#import "ScrobLog.h"
