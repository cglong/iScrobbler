//
//  iScrobblerController.h
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import <Cocoa/Cocoa.h>
#import <Growl/Growl.h>

@class PreferenceController;
@class SongData;
@class ISStatusItem;

@interface iScrobblerController : NSObject <GrowlApplicationBridgeDelegate>
{

    //the status item that will be added to the system status bar
    ISStatusItem *statusItem;

    //the menu attached to the status item
    IBOutlet NSMenu *theMenu;
    // a sub-menu attached to recently played songs
    NSMenu *songActionMenu;

    //the script to get information from iTunes
    NSAppleScript *script;

    //stores info about the songs iTunes has played
    NSMutableArray *songList;
    
    // Song that iTunes is currently playing (or pausing)
    SongData *currentSong;
    BOOL currentSongPaused;

    //the preferences window controller
    PreferenceController *preferenceController;
    // Preferences tracking object
    NSUserDefaults *prefs;

    NSNotificationCenter *nc;
    
    // GetTrackInfo error timer
    NSTimer *getTrackInfoTimer;
    
    // iPod sync management
    NSString *iPodMountPath;
    NSMutableDictionary *iPodMounts;
    NSImage *iPodIcon;
    NSDate *iTunesLastPlayedTime;
    int iPodMountCount;
    NSArray *iTunesPlaylists;
    
    BOOL badAuthAlertIsOpen;
    // Temporarily disable submissions
    BOOL submissionsDisabled;
    BOOL frontRowActive;
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

-(IBAction)performFindPanelAction:(id)sender;

-(IBAction)enableDisableSubmissions:(id)sender;

-(IBAction)donate:(id)sender;

-(IBAction)loveTrack:(id)sender;
-(IBAction)banTrack:(id)sender;

-(NSString *)md5hash:(id)input;

-(SongData*)nowPlaying;

- (BOOL)queueSongsForLaterSubmission;

-(NSString*)stringByEncodingURIChars:(NSString*)str;
-(NSURL*)audioScrobblerURLWithArtist:(NSString*)artist trackTitle:(NSString*)title;

- (void)showApplicationIsDamagedDialog;
- (void)showBadCredentialsDialog;

// For last.fm communication events
- (void)displayProtocolEvent:(NSString *)msg;

- (void)displayNowPlayingWithMsg:(NSString*)msg;
- (void)displayNowPlaying;
- (void)displayErrorWithTitle:(NSString*)title message:(NSString*)msg;
- (void)displayWarningWithTitle:(NSString*)title message:(NSString*)msg;

// Bindings
- (BOOL)isIPodMounted;
- (void)setIsIPodMounted:(BOOL)val;

@end

@interface NSMutableArray (iScrobblerContollerFifoAdditions)
- (void)pushSong:(id)obj;
@end

void ISDurationsFromTime(unsigned int tSeconds, unsigned int *days, unsigned int *hours,
    unsigned int *minutes, unsigned int *seconds);
void ISDurationsFromTime64(unsigned long long tSeconds, unsigned int *days, unsigned int *hours,
    unsigned int *minutes, unsigned int *seconds);

// Track Extended Menu
enum {
    MACTION_LOVE_TAG = 99999,
    MACTION_BAN_TAG,
    MACTION_TAG_TAG,
    MACTION_RECOMEND_TAG,
    MACTION_OPEN_ARTIST_PAGE,
    MACTION_OPEN_TRACK_PAGE,
    // Radio specific
    MACTION_PLAY,
    MACTION_SKIP,
    MACTION_STOP,
    MACTION_DISCOVERY, // subscriber only
    MACTION_SCROBRADIO,
    MACTION_CONNECTRADIO,
    MSTATION_INIT,
    MSTATION_RECOMMENDED,
    MSTATION_MYRADIO,  // subscriber only
    MSTATION_MYLOVED, // subscriber only
    MSTATION_LASTTUNED,
    MSTATION_MYPLAYLIST,
    MSTATION_MYNEIGHBORHOOD,
    MSTATION_SEARCH
};



#define IS_GROWL_NOTIFICATION_ALERTS @"Alerts"

#define IPOD_SYNC_BEGIN @"org.bergstrand.iscrobbler.ipod.sync.begin"
#define IPOD_SYNC_END @"org.bergstrand.iscrobbler.ipod.sync.end"
#define IPOD_SYNC_KEY_PATH @"Path"
#define IPOD_SYNC_KEY_ICON @"Icon"
#define IPOD_ICON_NAME @"iPod Icon"
#define IPOD_SYNC_KEY_TRACK_COUNT @"Track Count"
#define IPOD_SYNC_KEY_SCRIPT_MSG @"Script Msg"

#define RESET_PROFILE @"org.bergstrand.iscrobbler.resetProfile"
