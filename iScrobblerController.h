//
//  iScrobblerController.h
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import <Cocoa/Cocoa.h>
#import <Growl/Growl.h>

@class PreferenceController;
@class SongData;

@interface iScrobblerController : NSObject <GrowlApplicationBridgeDelegate>
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
    NSUserDefaults *prefs;

    NSNotificationCenter *nc;
    
    BOOL haveShownUpdateNowDialog;
    
    // GetTrackInfo error timer
    NSTimer *getTrackInfoTimer;
    
    // iPod sync management
    NSString *iPodMountPath;
    NSImage *iPodIcon;
    BOOL isIPodMounted;
    NSDate *iTunesLastPlayedTime;
    NSArray *iTunesPlaylists;
    
    // Temporarily disable submissions
    BOOL submissionsDisabled;
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

-(IBAction)performFindPanelAction:(id)sender;

-(IBAction)enableDisableSubmissions:(id)sender;

-(NSString *)md5hash:(NSString *)input;

-(SongData*)nowPlaying;

-(NSURL*)audioScrobblerURLWithArtist:(NSString*)artist trackTitle:(NSString*)title;

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

#ifdef __ppc__
#define trap() asm volatile("trap")
#elif __i386__
#define trap() asm volatile("int $3")
#else
#error unknown arch
#endif

#ifdef ISDEBUG
#define ISASSERT(condition,msg) do { \
if (0 == (condition)) { \
    trap(); \
} } while(0)
#else
#define ISASSERT(condition,msg) {}
#endif

#define IPOD_SYNC_BEGIN @"com.audioscrobbler.ipod.sync.begin"
#define IPOD_SYNC_END @"com.audioscrobbler.ipod.sync.end"
#define IPOD_SYNC_KEY_PATH @"Path"
#define IPOD_SYNC_KEY_ICON @"Icon"
#define IPOD_ICON_NAME @"iPod Icon"

#import "ScrobLog.h"
