//
//  iScrobblerController.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net/

#import <openssl/md5.h>

#import "iScrobblerController.h"
#import <CURLHandle/CURLHandle.h>
#import <CURLHandle/CURLHandle+extras.h>
#import "PreferenceController.h"
#import "SongData.h"
#import "keychain.h"
#import "NSString+parse.h"
#import "CURLHandle+SpecialEncoding.h"
#import "NSDictionary+httpEncoding.h"
#import "QueueManager.h"
#import "ProtocolManager.h"
#import "ScrobLog.h"
//#import <mHashMacOSX/mhash.h>
#import <ExtFSDiskManager/ExtFSDiskManager.h>

@interface iScrobblerController ( private )

-(void)changeLastResult:(NSString *)newResult;
-(void)changeLastHandshakeResult:(NSString *)result;
- (void) restoreITunesLastPlayedTime;
- (void) setITunesLastPlayedTime:(NSDate*)date;

// ExtFSManager notifications
- (void) volMount:(NSNotification*)notification;
- (void) volUnmount:(NSNotification*)notification;

@end

#define CLEAR_MENUITEM_TAG          1
#define SUBMIT_IPOD_MENUITEM_TAG    4

@implementation iScrobblerController

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    ScrobTrace(@"%@", [anItem title]);
    if(CLEAR_MENUITEM_TAG == [anItem tag])
        [mainTimer fire];
    else if(SUBMIT_IPOD_MENUITEM_TAG == [anItem tag] &&
         (!iPodDisk || ![prefs boolForKey:@"Sync iPod"]))
        return NO;
    return YES;
}

- (void)handshakeCompleteHandler:(NSNotification*)note
{
    ProtocolManager *pm = [note object];
    
    [self changeLastHandshakeResult:[pm lastHandshakeResult]];
    
    if ([pm updateAvailable] ||
         [[pm lastHandshakeResult] isEqualToString:HS_RESULT_BADAUTH]) {
        [self openPrefs:self];
    }
}

- (void)badAuthHandler:(NSNotification*)note
{
    [self openPrefs:self];
}

- (void)submitCompleteHandler:(NSNotification*)note
{
    ProtocolManager *pm = [note object];
    
    [self changeLastResult:[pm lastSubmissionResult]];
}

-(id)init
{
    // Read in a defaults.plist preferences file
    NSString * file = [[NSBundle mainBundle]
        pathForResource:@"defaults" ofType:@"plist"];
	
    NSDictionary * defaultPrefs = [NSDictionary dictionaryWithContentsOfFile:file];
	
    prefs = [[NSUserDefaults standardUserDefaults] retain];
    [prefs registerDefaults:defaultPrefs];
	
    // Request the password and lease it, this will force it to ask
    // permission when loading, so it doesn't annoy you halfway through
    // a song.
    (void)[[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler"
        account:[prefs stringForKey:@"username"]];
	
	// Create an instance of the preferenceController
    if(!preferenceController)
        preferenceController=[[PreferenceController alloc] init];
	
	// Set the script locations
    NSURL *url=[NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                stringByAppendingPathComponent:@"Scripts/controlscript.scpt"] ];
	
    // Get our iPod update script as text
    file = [[[NSBundle mainBundle] resourcePath]
                stringByAppendingPathComponent:@"iPodUpdate.applescript"];
    iPodUpdateScript = [[NSString alloc] initWithContentsOfFile:file];
    if (!iPodUpdateScript)
        ScrobLog(SCROB_LOG_CRIT, @"Failed to load iPodUpdateScript!\n");
    
    [self restoreITunesLastPlayedTime];
    
    if(self=[super init])
    {
        [NSApp setDelegate:self];
        
        script=[[NSAppleScript alloc] initWithContentsOfURL:url error:nil];
        nc=[NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(handleChangedNumRecentTunes:)
                   name:@"CDCNumRecentSongsChanged"
                 object:nil];
        
        // Initialize ExtFSManager
        (void)[ExtFSMediaController mediaController];
        
        // Register for ExtFSManager disk notifications
        [nc addObserver:self
                selector:@selector(volMount:)
                name:ExtFSMediaNotificationMounted
                object:nil];
        [nc addObserver:self
                selector:@selector(volUnmount:)
                name:ExtFSMediaNotificationUnmounted
                object:nil];
        
        // Create protocol mgr
        (void)[ProtocolManager sharedInstance];
        
        // Register for PM notifications
        [nc addObserver:self
                selector:@selector(handshakeCompleteHandler:)
                name:PM_NOTIFICATION_HANDSHAKE_COMPLETE
                object:nil];
        [nc addObserver:self
                selector:@selector(badAuthHandler:)
                name:PM_NOTIFICATION_BADAUTH
                object:nil];
        [nc addObserver:self
                selector:@selector(submitCompleteHandler:)
                name:PM_NOTIFICATION_SUBMIT_COMPLETE
                object:nil];
        
        // Create queue mgr
        (void)[QueueManager sharedInstance];
        if ([[QueueManager sharedInstance] count])
            [[QueueManager sharedInstance] submit];
    }
    return self;
}

#define MAIN_TIMER_INTERVAL 10.0

- (void)awakeFromNib
{
    songList=[[NSMutableArray alloc ]init];
	
    mainTimer = [[NSTimer scheduledTimerWithTimeInterval:(MAIN_TIMER_INTERVAL)
                                                  target:self
                                                selector:@selector(mainTimer:)
                                                userInfo:nil
                                                 repeats:YES] retain];
    
    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
	
    [statusItem setTitle:[NSString stringWithFormat:@"%C",0x266B]];
    [statusItem setHighlightMode:YES];
    [statusItem setMenu:theMenu];
    [statusItem setEnabled:YES];
	
    [mainTimer fire];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [[QueueManager sharedInstance] syncQueue:nil];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)updateMenu
{
    NSMenuItem *item;
    NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
    SongData *song;
    // ScrobTrace(@"updating menu");
	
    // remove songs from menu
    while(item=[enumerator nextObject])
        if([item action]==@selector(playSong:))
            [theMenu removeItem:item];
    
    // add songs from songList array to menu
    enumerator=[songList reverseObjectEnumerator];
    while ((song = [enumerator nextObject]))
    {
        //ScrobTrace(@"Corrupted song:\n%@",song);
        item = [[[NSMenuItem alloc] initWithTitle:[song title]
                                           action:@selector(playSong:)
                                    keyEquivalent:@""] autorelease];
        
        [item setTarget:self];
        [theMenu insertItem:item atIndex:0];
		//    ScrobTrace(@"added item to menu");
    }
}

// Caller must release
- (SongData*)createSong:(NSArray*)data
{
    SongData * song = [[SongData alloc] init];
    [song setTrackIndex:[NSNumber numberWithFloat:[[data objectAtIndex:0]
        floatValue]]];
    [song setPlaylistIndex:[NSNumber numberWithFloat:[[data objectAtIndex:1]
        floatValue]]];
    [song setTitle:[data objectAtIndex:2]];
    [song setDuration:[NSNumber numberWithFloat:[[data objectAtIndex:3] floatValue]]];
    [song setPosition:[NSNumber numberWithFloat:[[data objectAtIndex:4] floatValue]]];
    [song setArtist:[data objectAtIndex:5]];
    [song setAlbum:[data objectAtIndex:6]];
    [song setPath:[data objectAtIndex:7]];
    if (9 == [data count])
        [song setLastPlayed:[NSDate dateWithNaturalLanguageString:[data objectAtIndex:8]
            locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]]];
    //ScrobTrace(@"SongData allocated and filled");
    return (song);
}

-(void)mainTimer:(NSTimer *)timer
{
    // micah_modell@users.sourceforge.net
    // Check for null and branch to avoid having the application hang.
    NSAppleEventDescriptor * executionResult = [ script executeAndReturnError: nil ] ;
    
    if( nil != executionResult )
    {
        NSString *result=[[NSString alloc] initWithString:[ executionResult stringValue]];
	
    //ScrobTrace(@"timer fired");
    //ScrobTrace(@"%@",result);
	
    // For Debugging: Display the contents of the parsed result array
    // ScrobTrace(@"Parsed result array:\n%@\n",parsedResult);
    
    // If the script didn't return an error, continue
    if([result hasPrefix:@"NOT PLAYING"]) {
		
    } else if([result hasPrefix:@"RADIO"]) {
		
    } else if([result hasPrefix:@"INACTIVE"]) {
        
    } else {
        // Parse the result and create an array
        NSArray *parsedResult = [[NSArray alloc] initWithArray:[result 				componentsSeparatedByString:@"***"]];
		NSDate *now;
        
        // Make a SongData object out of the array
        SongData *song = [self createSong:parsedResult];
        
        // iPod sync date management, the goal is to detect the valid songs to sync
		now = [NSDate date];
        // XXX We need to do something fancy here, because this assumes
        // the user will sync the iPod before playing anything in iTunes,
        // and that we have been running the whole time they were gone.
        [self setITunesLastPlayedTime:now];
        
        // If the songlist is empty, then simply add the song object to the songlist
        if([songList count]==0)
        {
            ScrobLog(SCROB_LOG_VERBOSE, @"adding first item");
            [songList insertObject:song atIndex:0];
        }
        else
        {
            // Is the track equal to the track that's
            // currently in first place in the song list? If so, find out what percentage
            // of the song has been played, and queue a submission if necessary.
            if([song isEqualToSong:[songList objectAtIndex:0]])
            {
                [[songList objectAtIndex:0] setPosition:[song position]];
                [[songList objectAtIndex:0] setLastPlayed:[song lastPlayed]];
                // If the song hasn't been queued yet, see if its ready.
                if(![[songList objectAtIndex:0] hasQueued])
                {
                    [[QueueManager sharedInstance] queueSong:[songList objectAtIndex:0]];
                }
            } else {
                // Check to see if the current track is anywhere in the songlist
                // If it is, we set found equal to the index position where it was found
                // ScrobTrace(@"Looking for track");
                int j;
                int found = 0;
                for(j = 0; j < [songList count]; j++) {
                    if([[songList objectAtIndex:j] isEqualToSong:song])
                    {
                        found = j;
                        break;
                    }
                }
                //ScrobTrace(@"Found = %i",j);
				
                // If the track wasn't found anywhere in the list, we add a new item
                if(!found)
                {
                    ScrobLog(SCROB_LOG_VERBOSE, @"adding new item");
                    [songList insertObject:song atIndex:0];
                }
                // If the trackname was found elsewhere in the list, we remove the old
                // item, and add the new one onto the beginning of the list.
                else
                {
                    //ScrobTrace(@"removing old, adding new");
                    [songList removeObjectAtIndex:found];
                    [songList insertObject:song atIndex:0];
                }
            }
        }
        // If there are more items in the list than the user wanted
        // Then we remove the last item in the songlist
        while([songList count]>[prefs integerForKey:@"Number of Songs to Save"]) {
            //ScrobTrace(@"Removed an item from songList");
            [songList removeObject:[songList lastObject]];
        }
		
        //ScrobTrace(@"About to release song and parsedResult");
        [self updateMenu];
        [song release];
        [parsedResult release];
        //ScrobTrace(@"song and parsedResult released");
    }
    
    [result release];
    //ScrobTrace(@"result released");
    }
}

-(IBAction)playSong:(id)sender{
    SongData *songInfo;
    NSString *scriptText;
    NSAppleScript *play;
    int index=[[sender menu] indexOfItem:sender];
	
    songInfo = [songList objectAtIndex:index];
	
	
    scriptText=[NSString stringWithFormat: @"tell application \"iTunes\" to play track %d of playlist %d",[[songInfo trackIndex] intValue],[[songInfo playlistIndex] intValue]];
	
    play=[[NSAppleScript alloc] initWithSource:scriptText];
	
    [play executeAndReturnError:nil];
    
    [play release];
    [mainTimer fire];
}

-(IBAction)clearMenu:(id)sender{
    NSMenuItem *item;
    NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
	
	ScrobTrace(@"clearing menu");
    [songList removeAllObjects];
    
	while(item=[enumerator nextObject])
        if([item action]==@selector(playSong:))
            [theMenu removeItem:item];
	
	[mainTimer fire];
}

-(IBAction)openPrefs:(id)sender{
    // ScrobTrace(@"opening prefs");
    if(!preferenceController)
        preferenceController=[[PreferenceController alloc] init];
	
    [preferenceController takeValue:[[ProtocolManager sharedInstance] lastSubmissionResult] forKey:@"lastResult"];
	
    [NSApp activateIgnoringOtherApps:YES];
    [[preferenceController window] makeKeyAndOrderFront:nil];
}

-(IBAction)openScrobblerHomepage:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"http://www.audioscrobbler.com"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

-(IBAction)openUserHomepage:(id)sender
{
    NSString *prefix = @"http://www.audioscrobbler.com/user/";
    NSURL *url = [NSURL URLWithString:[prefix stringByAppendingString:[prefs stringForKey:@"username"]]];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

-(void) handleChangedNumRecentTunes:(NSNotification *)aNotification
{
    while([songList count]>[prefs integerForKey:@"Number of Songs to Save"])
        [songList removeObject:[songList lastObject]];
    [self updateMenu];
}

-(void)dealloc{
	[nc removeObserver:self];
	[nc release];
	[statusItem release];
	[songList release];
	[script release];
	[mainTimer invalidate];
	[mainTimer release];
	[prefs release];
	[preferenceController release];
	[super dealloc];
}

- (void)changeLastResult:(NSString *)newResult
{
    //ScrobTrace(@"song data before sending: %@",[songQueue objectAtIndex:0]);
    [preferenceController takeValue:newResult forKey:@"lastResult"];
    [nc postNotificationName:@"lastResultChanged" object:self];
	
    ScrobLog(SCROB_LOG_VERBOSE, @"result changed");
}

- (void)changeLastHandshakeResult:(NSString*)result
{	
    [preferenceController setLastHandshakeResult:result];
    [nc postNotificationName:@"lastHandshakeResultChanged" object:self];
	
    ScrobLog(SCROB_LOG_VERBOSE, @"Handshakeresult changed: %@", result);
}

- (NSString *)md5hash:(NSString *)input
{
	unsigned char *hash = MD5([input cString], [input cStringLength], NULL);
	int i;
    
	NSMutableString *hashString = [NSMutableString string];
	
    // Convert the binary hash into a string
    for (i = 0; i < MD5_DIGEST_LENGTH; i++) {
		//ScrobTrace(@"Appending %X to hashString (currently %@)", *hash, hashString);
		[hashString appendFormat:@"%02x", *hash++];
	}
	
    //ScrobTrace(@"Returning hash... %@ for input: %@", hashString, input);
    return hashString;
}

-(IBAction)cleanLog:(id)sender
{
    ScrobLogTruncate();
}

#define ONE_WEEK (3600.0 * 24.0 * 7.0)
- (void) restoreITunesLastPlayedTime
{
    NSTimeInterval ti = [[prefs stringForKey:@"iTunesLastPlayedTime"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDate *tr = [NSDate dateWithTimeIntervalSince1970:ti];

    if (!ti || ti > (now + MAIN_TIMER_INTERVAL) || ti < (now - ONE_WEEK)) {
        ScrobLog(SCROB_LOG_WARN, @"Discarding invalid iTunesLastPlayedTime value (ti=%.0lf, now=%.0lf).\n",
            ti, now);
        tr = [NSDate date];
    }
    
    [self setITunesLastPlayedTime:tr];
}

- (void) setITunesLastPlayedTime:(NSDate*)date
{
    [date retain];
    [iTunesLastPlayedTime release];
    iTunesLastPlayedTime = date;
    // Update prefs
    [prefs setObject:[NSString stringWithFormat:@"%.2lf", [iTunesLastPlayedTime timeIntervalSince1970]]
        forKey:@"iTunesLastPlayedTime"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

/*
Validate all of the post dates. We do this, because there seems
to be a iTunes bug that royally screws up last played times during daylight
savings changes.

Scenario: Unplug iPod on 10/30, play a lot of songs, then sync the next day (10/31 - after 0200)
and some of the last played dates will be very bad.
*/
- (NSMutableArray*)validateIPodSync:(NSArray*)songs
{
    NSMutableArray *sorted = [[songs sortedArrayUsingSelector:@selector(compareSongPostDate:)] mutableCopy];
    int i;
    
validate:
    for (i = 1; i < [sorted count]; ++i) {
        SongData *thisSong = [sorted objectAtIndex:i];
        SongData *lastSong = [sorted objectAtIndex:i-1];
        NSTimeInterval thisPost = [[thisSong postDate] timeIntervalSince1970];
        NSTimeInterval lastPost = [[lastSong postDate] timeIntervalSince1970];
        
        if ((lastPost + [[lastSong duration] doubleValue]) > thisPost) {
            ScrobLog(SCROB_LOG_WARN, @"iPodSync: Discarding '%@' because of invalid play time.\n\t'%@' = Start: %@, Duration: %@"
                "\n\t'%@' = Start: %@, Duration: %@\n", [thisSong breif], [lastSong breif], [lastSong postDate], [lastSong duration],
                [thisSong breif], [thisSong postDate], [thisSong duration]);
            [sorted removeObjectAtIndex:i];
            goto validate;
        }
    }
    
    return ([sorted autorelease]);
}

//#define IPOD_UPDATE_SCRIPT_DATE_FMT @"%A, %B %d, %Y %I:%M:%S %p"
#define IPOD_UPDATE_SCRIPT_DATE_TOKEN @"Thursday, January 1, 1970 12:00:00 AM"
#define IPOD_UPDATE_SCRIPT_SONG_TOKEN @"$$$"

- (void)syncIPod:(id)sender
{
    ScrobTrace (@"syncIpod: called: script=%p, sync pref=%i\n", iPodUpdateScript, [prefs boolForKey:@"Sync iPod"]);
    
    if (iPodUpdateScript && [prefs boolForKey:@"Sync iPod"]) {
        // Copy the script
        NSMutableString *text = [iPodUpdateScript mutableCopy];
        NSAppleScript *iuscript;
        NSAppleEventDescriptor *result;
        NSDictionary *errInfo, *localeInfo;
        NSTimeInterval now, fudge;
        unsigned int added;
        
        // Our main timer loop is only fired every 10 seconds, so we have to
        // make sure to adjust our time
        fudge = [iTunesLastPlayedTime timeIntervalSince1970]+MAIN_TIMER_INTERVAL;
        now = [[NSDate date] timeIntervalSince1970];
        if (now > fudge) {
            [self setITunesLastPlayedTime:[NSDate dateWithTimeIntervalSince1970:fudge]];
        } else {
            [self setITunesLastPlayedTime:[NSDate date]];
        }
        
        // AppleScript expects the date string formated according to the users's system settings
        localeInfo = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        
        // Replace the token with our last update
        [text replaceOccurrencesOfString:IPOD_UPDATE_SCRIPT_DATE_TOKEN
            withString:[iTunesLastPlayedTime descriptionWithCalendarFormat:
                [localeInfo objectForKey:NSTimeDateFormatString] timeZone:nil locale:localeInfo]
            options:0 range:NSMakeRange(0, [iPodUpdateScript length])];
        
        ScrobLog(SCROB_LOG_VERBOSE, @"syncIPod: Requesting songs played after '%@'\n",
            [iTunesLastPlayedTime descriptionWithCalendarFormat:[localeInfo objectForKey:NSTimeDateFormatString]
                timeZone:nil locale:localeInfo]);
        // Run script
        iuscript = [[NSAppleScript alloc] initWithSource:text];
        if ((result = [iuscript executeAndReturnError:&errInfo])) {
            if (![[result stringValue] hasPrefix:@"INACTIVE"]) {
                NSArray *songs = [[result stringValue]
                    componentsSeparatedByString:IPOD_UPDATE_SCRIPT_SONG_TOKEN];
                NSEnumerator *en = [songs objectEnumerator];
                NSString *data;
                SongData *song;
                NSMutableArray *iqueue = [NSMutableArray array];
                
                if ([[result stringValue] hasPrefix:@"ERROR"]) {
                    NSString *errmsg, *errnum;
                NS_DURING
                    errmsg = [songs objectAtIndex:1];
                    errnum = [songs objectAtIndex:2];
                NS_HANDLER
                    errmsg = errnum = @"UNKNOWN";
                NS_ENDHANDLER
                    // Display dialog instead of logging?
                    ScrobLog(SCROB_LOG_ERR, @"syncIPod: iPodUpdateScript returned error: \"%@\" (%@)\n",
                        errmsg, errnum);
                    goto sync_ipod_script_release;
                }
                
                added = 0;
                while ((data = [en nextObject])) {
                    NSArray *components = [data componentsSeparatedByString:@"***"];
                    NSTimeInterval postDate;
                    
                    if ([components count] > 1) {
                        song = [self createSong:components];
                        // Since this song was played "offline", we set the post date
                        // in the past 
                        postDate = [[song lastPlayed] timeIntervalSince1970] - [[song duration] doubleValue];
                        [song setPostDate:[NSCalendarDate dateWithTimeIntervalSince1970:postDate]];
                        // Make sure the song passes submission rules                            
                        [song setStartTime:[NSDate dateWithTimeIntervalSince1970:postDate]];
                        [song setPosition:[song duration]];
                        
                        [iqueue addObject:song];
                        [song release];
                    }
                }
                
                iqueue = [self validateIPodSync:iqueue];
                
                en = [iqueue objectEnumerator];
                while ((song = [en nextObject])) {
                    if (![[song postDate] isGreaterThan:iTunesLastPlayedTime]) {
                        ScrobLog(SCROB_LOG_WARN,
                            @"Anachronistic post date for song '%@'. Discarding -- possible date parse error.\n\t"
                            "Post Date: %@, Last Played: %@, Duration: %.0lf, iTunesLastPlayed: %@.\n",
                            [song breif], [song postDate], [song lastPlayed], [[song duration] doubleValue],
                            iTunesLastPlayedTime);
                        continue;
                    }
                    ScrobLog(SCROB_LOG_VERBOSE, @"syncIPod: Queuing '%@' with postDate '%@'\n", [song breif], [song postDate]);
                    [[QueueManager sharedInstance] queueSong:song submit:NO];
                    ++added;
                }
                
                [self setITunesLastPlayedTime:[NSDate date]];
                if (added > 0) {
                    [[QueueManager sharedInstance] submit];
                }
            }
        } else if (!result) {
            // Script error
            ScrobLog(SCROB_LOG_ERR, @"iPodUpdateScript execution error: %@\n", errInfo);
        }
        
sync_ipod_script_release:
        [iuscript release];
        [text release];
    } else {
        ScrobLog(SCROB_LOG_CRIT, @"iPodUpdateScript missing\n");
    }
}

// ExtFSManager notifications
- (void)volMount:(NSNotification*)notification
{
    ExtFSMedia *media = [notification object];
    NSString *iPodCtl =
        [[media mountPoint] stringByAppendingPathComponent:@"iPod_Control"];
    BOOL isDir;
    
    ScrobTrace(@"Volume '%@' (%@) mounted on '%@'.\n", [media volName], [media bsdName], [media mountPoint]);
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:iPodCtl isDirectory:&isDir]
         && isDir) {
        iPodDisk = [media retain];
    }
}

- (void)volUnmount:(NSNotification*)notification
{
    ScrobTrace(@"Volume '%@' unmounted.\n", [[notification object] bsdName]);
    
    if (iPodDisk != [notification object])
        return;
    
    [iPodDisk release];
    iPodDisk = nil;
    
    [self syncIPod:nil];
}

@end
