//
//  iScrobblerController.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net/

// ECS 10/27/04: It looks like most of the original iScrobbler code was stolen from
// http://cocoadevcentral.com/articles/000052.php

#import "iScrobblerController.h"
#import "PreferenceController.h"
#import "AudioScrobblerProtocol.h"

#import "SongData.h"
#import "keychain.h"

// not actually used anywhere.
#define AUDIOSCROBBLER_HOMEPAGE_MENUITEM_TAG	1
#define USER_STATISTICS_MENUITEM_TAG			2
#define PREFERENCES_MENUITEM_TAG				3

#define MAIN_TIMER_INTERVAL 10

NSString *iScrobblerPrefsRecentSongsCountKey = @"Number of Songs to Save";
NSString *iScrobblerPrefsClientVersionKey = @"version";
NSString *iScrobblerPrefsClientIdKey = @"clientid";
NSString *iScrobblerPrefsProtocolVersionKey = @"protocol";
NSString *iScrobblerPrefsServerURLKey = @"url";

static BOOL haveCheckedLoggingDefault = NO;
static BOOL shouldLog = NO;

BOOL ISShouldLog() {
	if (!haveCheckedLoggingDefault) {
		shouldLog = [[NSUserDefaults standardUserDefaults] boolForKey:@"EnableDebugLogging"];
		haveCheckedLoggingDefault = YES;
	}
	return shouldLog;
}

// Logging
void ISLog(NSString *function, NSString *format, ...) {
	if (!ISShouldLog())
		return;
    va_list args;
    va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	NSLog(@"[%@] %@", function, message);
	[message release];
    va_end(args);
}


@interface SongData (iTunesAdditions)
+ (SongData *)songWithiTunesResultString:(NSString *)result;
@end

@implementation SongData (iTunesAdditions)
+ (SongData *)songWithiTunesResultString:(NSString *)result {
	// Parse the result and create an array
	NSArray *parsedResult = [result componentsSeparatedByString:@"***"];
	
	// Make a SongData object out of the array
	SongData *song = [[[SongData alloc] init] autorelease];
	
	// FIXME: we should check to make sure there are 8/9 pieces first!
	
	[song setTrackIndex:[NSNumber numberWithFloat:[[parsedResult objectAtIndex:0]
		floatValue]]];
	[song setPlaylistIndex:[NSNumber numberWithFloat:[[parsedResult objectAtIndex:1]
		floatValue]]];
	[song setTitle:[parsedResult objectAtIndex:2]];
	[song setDuration:[NSNumber numberWithFloat:[[parsedResult objectAtIndex:3] floatValue]]];
	[song setPosition:[NSNumber numberWithFloat:[[parsedResult objectAtIndex:4] floatValue]]];
	[song setArtist:[parsedResult objectAtIndex:5]];
	[song setAlbum:[parsedResult objectAtIndex:6]];
	[song setPath:[parsedResult objectAtIndex:7]];
	if (9 == [parsedResult count])
        [song setLastPlayed:[NSDate dateWithNaturalLanguageString:[parsedResult objectAtIndex:8]]];
	//ISLog(@"songWithiTunesResultString:", @"SongData allocated and filled");
	return song;
}
@end

@interface iScrobblerController (PrivateMethods)

- (void)iTunesUpdateTimer:(NSTimer *)timer; //called when mainTimer fires
- (void)_updateMenu; //sync _recentlyPlayedList and theMenu
- (void)_setupStatusItem;
- (void)handleiPodUpdateResult:(NSString *)result;
- (NSArray *)songsFromResultString:(NSString *)resultString;
- (IBAction)iPodSync:(id)sender;

- (void)addSongToRecentlyPlayedList:(SongData *)newSong;
- (SongData *)lastSongPlayed;
- (unsigned int)indexOfSongInRecentlyPlayedList:(SongData *)song;

- (NSString *)password;
- (void) setITunesLastPlayedTime:(NSDate*)date;
@end


@implementation iScrobblerController

+ (void)initialize {
	//NSLog(@"iScrobblerController initialize");
	// setup the default prefs, as the very first thing we do.
	NSDictionary *defaultPrefs = [NSDictionary dictionaryWithObjectsAndKeys:        
		[NSNumber numberWithInt:5], @"Number of Songs to Save",
		@"http://post.audioscrobbler.com/", @"url",
		@"osx", @"clientid",
		@"1.1", @"protocol",
		@"0.7.0", @"version",
		nil];
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultPrefs];
}

- (id)init {
	if (self = [super init]) {
		// ECS: shoudl be done lazily in an accessor
		_recentlyPlayedList = [[NSMutableArray alloc] init];
		
		// setup iTunes timer.
		_iTunesUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:MAIN_TIMER_INTERVAL
															   target:self
															 selector:@selector(iTunesUpdateTimer:)
															 userInfo:nil
															  repeats:YES] retain];
	}
	return self;
}

- (void)awakeFromNib
{
	// Request the password now, this will force the keychain to ask
	// permission when loading, so it doesn't annoy you halfway through
	// a song.
	(void)[self password];
	
	// this depends on an IBOutlet, so we wait until awakeFromNib...
	[self _setupStatusItem];
	
    [_iTunesUpdateTimer fire]; // make sure we update from iTunes immediately on load.
    [[self submissionController] scheduleSubmissionTimerIfNeeded]; // start submitting if necessary.
}

- (void)dealloc{
	[_recentlyPlayedList release];
	[_statusItem release];
	[_iTunesStatusScript release];
	
	[_iTunesUpdateTimer invalidate];
	[_iTunesUpdateTimer release];
	
	[_preferenceController release];
	[super dealloc];
}


#pragma mark -

- (void)_setupStatusItem {
	// setup the status item
    _statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
	
    [_statusItem setTitle:[NSString stringWithFormat:@"%C",0x266B]];
    [_statusItem setHighlightMode:YES];
	[_statusItem setMenu:theMenu];
	[theMenu setDelegate:self];
	
    [_statusItem setEnabled:YES];
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	//NSLog(@"Updating \"Recently Played\" menu");
    NSMenuItem *item = nil;
    NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
	
    // remove songs from menu
    while(item = [enumerator nextObject])
        if( [item action] == @selector(playSong:))
            [theMenu removeItem:item];
	
	// remove the first separator
	if ([theMenu numberOfItems] && [[theMenu itemAtIndex:0] isSeparatorItem])
		[theMenu removeItemAtIndex:0];
	
	
    // add the current "recent" songs back.
	int numberOfRecentSongs = [_recentlyPlayedList count];
	if (numberOfRecentSongs) {
		
		// how many songs are we supposed to display?
		int numberOfSongsToDisplay = [[NSUserDefaults standardUserDefaults] integerForKey:iScrobblerPrefsRecentSongsCountKey];
		
		// don't try to display more songs than we have...
		if (numberOfSongsToDisplay > numberOfRecentSongs)
			numberOfSongsToDisplay = numberOfRecentSongs;
		
		for (int index = 0; index < numberOfSongsToDisplay; index++) {
			SongData *song = [_recentlyPlayedList objectAtIndex:index];
			
			// build the menu item
			item = [[[NSMenuItem alloc] initWithTitle:[song title]
											   action:@selector(playSong:)
										keyEquivalent:@""] autorelease];
			[item setTarget:self];
			
			// add to the menu
			[theMenu insertItem:item atIndex:index];
		}
				
		// add the separator after the "recent" items.
		[theMenu insertItem:[NSMenuItem separatorItem] atIndex:numberOfRecentSongs];
	}
}

#pragma mark -

- (void)handleiTunesStatusResult:(NSString *)result {

	// If the script didn't return an error, continue
	if([result hasPrefix:@"NOT PLAYING"] || [result hasPrefix:@"RADIO"] || [result hasPrefix:@"INACTIVE"]) {
		//NSLog(@"iTunes not playing, nothing to do.  (result = %@)", result);
		
		// FIXME: We should be more intellegent here, and use this information
		// to stop this polling thread (or at least reduce it to every 30 seconds)
		//  and perhaps wait for an NSWorkspaceDidLaunchApplicationNotification or the like.
		
	} else {
		SongData *newSong = [SongData songWithiTunesResultString:result];
		SongData *lastSong = [self lastSongPlayed];
		
		// are we still playing the same song?
		if(lastSong && [[newSong title] isEqualToString:[lastSong title]])
		{
			// have we already queued this song?
			if(![lastSong hasQueued])
			{
				/*  Submission Rules:
				 * Songs with a duration of less than 30 seconds must not be submitted
				 * Each track must be posted to the server when it is 50% or 240 seconds complete, whichever comes first.
				 * If a user seeks (i.e. manually changes position) within a track before the it is due to be submitted, the track must not be submitted. -- (make sure that total played time is close to full time).
				*/
				if( ([[lastSong duration] intValue] >= 30 ) &&
					([[lastSong percentPlayed] intValue] > 50 || [[lastSong timePlayed] intValue] > 240) ) {
					[[self submissionController] queueSongForSubmission:lastSong];
				}
			}
		} else {
			// this is not the last song we were playing...
			// but did we recently play this song?
			int index = [self indexOfSongInRecentlyPlayedList:newSong];
			
			// if not, we better add it to our list...
			if (index == NSNotFound) {
				[self addSongToRecentlyPlayedList:newSong];
			} else {
				// otherwise, we'll move it's record up to the top of our list...
				//NSLog(@"removing song from old index %i, adding new (%@)", found, song);
				[_recentlyPlayedList removeObjectAtIndex:index];
				[_recentlyPlayedList insertObject:newSong atIndex:0];
			}
		}
	}
}

- (void)addSongToRecentlyPlayedList:(SongData *)newSong {
	ISLog(@"mainTimer:", @"adding new item (%@)", newSong);
	[_recentlyPlayedList insertObject:newSong atIndex:0];
}

- (SongData *)lastSongPlayed {
	SongData *lastSong = nil;
	if ([_recentlyPlayedList count])
		lastSong = [_recentlyPlayedList objectAtIndex:0];
	return lastSong;
}

- (unsigned int)indexOfSongInRecentlyPlayedList:(SongData *)song {
	// FIXME:  This really should compare iTunes IDs and not title
	// so that we correctly handle them changing the id3 tags
	// while playing the song.
	for(int index = 0; index < [_recentlyPlayedList count]; index++) {
		if([[[_recentlyPlayedList objectAtIndex:index] title] isEqualToString:[song title]])
			return index;
	}
	return NSNotFound;
}

- (void)iTunesUpdateTimer:(NSTimer *)timer
{
	if (!_iTunesStatusScript) {
		// Set the script locations
		NSDictionary *error = nil;
		NSURL *url = [NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
					stringByAppendingPathComponent:@"Scripts/getiTunesStatus.applescript"]];
        _iTunesStatusScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:&error];
		if (!_iTunesStatusScript) {
			NSLog(@"Error, failed to read iTunesStatusScript (url = %@), iScrobbler is pretty much useless. (applescript error = %@)", url, error);
			[self showApplicationIsDamagedDialog];
		}
		// FIXME: Very odd.  If I do this alloc/init in -init, I crash on launch (in AppleScript init code) - ECS 10/27/04
		// NSAppleScriptErrorNumber
	}
	
	NSDictionary *applescriptError = nil;
	// WARNING: There is a known leak in this call
	// http://lists.apple.com/archives/applescript-implementors/2003/Apr/msg00020.html
	// I don't know of any way to get around this... -- ECS 10/30/04
    NSAppleEventDescriptor *executionResult = [_iTunesStatusScript executeAndReturnError:&applescriptError];
    
    if(executionResult) {
		NSString *result = [executionResult stringValue];
		[self handleiTunesStatusResult:result];
    } else
		NSLog(@"Error executing iTunesStatusUpdate applescript: %@", applescriptError);
}

#pragma mark -

- (IBAction)playSong:(id)sender{
    int index = [[sender menu] indexOfItem:sender];
	
    SongData *songInfo = [_recentlyPlayedList objectAtIndex:index];
	
    NSString *scriptText =
		[NSString stringWithFormat: @"tell application \"iTunes\" to play track %d of playlist %d",
		[[songInfo trackIndex] intValue], [[songInfo playlistIndex] intValue]];
	
	NSAppleScript *play = [[[NSAppleScript alloc] initWithSource:scriptText] autorelease];
	
    [play executeAndReturnError:nil];
    
    [_iTunesUpdateTimer fire]; // check with iTunes to see what's playing.
}

- (IBAction)clearRecentSongsMenu:(id)sender{
	//NSLog(@"iScrobblerController clearRecentSongsMenu: clearing menu");
	
    [_recentlyPlayedList removeAllObjects];
    
	NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
	NSMenuItem *item = nil;
	while(item = [enumerator nextObject])
        if([item action] == @selector(playSong:))
            [theMenu removeItem:item];
	
	[_iTunesUpdateTimer fire]; // check with iTunes to see what's playing (if anything)
}

- (IBAction)openPreferencesWindow:(id)sender{
	//NSLog(@"iScrobblerController openPreferencesWindow: opening prefs");
	[NSApp activateIgnoringOtherApps:YES];
	[[self preferenceController] showPreferencesWindow];
}

- (IBAction)openAudioScrobblerHomepage:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"http://www.audioscrobbler.com"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)openUserHomepage:(id)sender
{
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
	if (username) {
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.audioscrobbler.com/user/%@", username]];
		[[NSWorkspace sharedWorkspace] openURL:url];
	} else
		NSLog(@"No username in perfs, can't open user homepage!");
}

- (void)showBadCredentialsDialog {	
	[NSApp activateIgnoringOtherApps:YES];
	
	// we should give them the option to ignore
	// these messages, and only update the menu icon... -- ECS 10/30/04
	int result = NSRunAlertPanel(NSLocalizedString(@"Authentication Failure", nil),
								NSLocalizedString(@"Audioscrobbler.com did not accept your username and password.  Please update your user credentials in the iScrobbler preferences.", nil),
								NSLocalizedString(@"Open iScrobbler Preferences", nil),
								NSLocalizedString(@"New Account", nil),
								nil); // NSLocalizedString(@"Ignore", nil)
	
	if (result == NSAlertDefaultReturn)
		[self openPreferencesWindow:self];
	else if (result == NSAlertAlternateReturn)
		[self openAudioScrobblerHomepage:self];
	//else
	//	_ignoreBadCredentials = YES;
}

- (void)showNewVersionExistsDialog {
	if (!_haveShownUpdateNowDialog) {
		[NSApp activateIgnoringOtherApps:YES];
		int result = NSRunAlertPanel(NSLocalizedString(@"New Plugin Available", nil),
									 NSLocalizedString(@"A new version (%@) of the iScrobbler iTunes plugin is now available.  It strongly suggested you update to the latest version.", nil),
									 NSLocalizedString(@"Open Download Page", nil),
									 NSLocalizedString(@"Ignore", nil),
									 nil); // NSLocalizedString(@"Ignore", nil)
		if (result == NSAlertDefaultReturn)
			[self openiScrobblerDownloadPage:self];
		
		_haveShownUpdateNowDialog = YES;
	}
}

- (void)showApplicationIsDamagedDialog {
	[NSApp activateIgnoringOtherApps:YES];
	int result = NSRunCriticalAlertPanel(NSLocalizedString(@"Critical Error", nil),
										 NSLocalizedString(@"The iScrobbler application appears to be damaged.  Please download a new copy from the iScrobbler homepage.", nil),
										 NSLocalizedString(@"Quit", nil),
										 NSLocalizedString(@"Open iScrobbler Homepage", nil), nil);
	if (result == NSAlertAlternateReturn)
		[self openiScrobblerDownloadPage:self];
	
	[NSApp terminate:self];
}

- (IBAction)openiScrobblerDownloadPage:(id)sender {
	//NSLog(@"openiScrobblerDownloadPage");
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.audioscrobbler.com/download.php"]];
}

#pragma mark -

- (AudioScrobblerProtocol *)submissionController {
	if (!_submissionController) {
		// This woulc be where we could control which protocol we use!
		// by choosing which sublcass of AudioScrobblerProtocol we instantiate...
		_submissionController = [[AudioScrobblerProtocol alloc] init];
	}
	return _submissionController;
}

- (PreferenceController *)preferenceController {
	if (!_preferenceController) {
		_preferenceController = [[PreferenceController alloc] init];
	}
	return _preferenceController;
}

- (NSString *)password {
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
	return [[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler" account:username];	
}

#pragma mark -

- (void)_setupAppSupportDirectory {
    if (![[NSFileManager defaultManager] fileExistsAtPath:
        [@"~/Library" stringByExpandingTildeInPath]])
        [[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library" stringByExpandingTildeInPath] attributes:nil];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:
        [@"~/Library/Application Support" stringByExpandingTildeInPath]])
        [[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support" stringByExpandingTildeInPath] attributes:nil];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:
        [@"~/Library/Application Support/iScrobbler" stringByExpandingTildeInPath]])
        [[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/iScrobbler" stringByExpandingTildeInPath] attributes:nil];     
}

- (NSString *)appSupportDirectory {
	return [@"~/Library/Application Support/iScrobbler/" stringByExpandingTildeInPath];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
	// Save away unsubmitted songs...
	// this could also go in 
	// -applicationShouldTerminate
	// in which case, we would throw up a dialog, and then
	// do the actual file write in a seperate thread.
	// that's the cleaner, nicer solution...
	
	[self _setupAppSupportDirectory];
	[[self submissionController] writeUnsubmittedSongsToDisk];
}

#pragma mark -

#define ONE_WEEK (3600.0 * 24.0 * 7.0)
- (void) restoreITunesLastPlayedTime
{
    NSTimeInterval lastPlayedTimeInterval = [[NSUserDefaults standardUserDefaults] floatForKey:@"iTunesLastPlayedTime"];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDate *lastPlayedDate = [NSDate dateWithTimeIntervalSince1970:lastPlayedTimeInterval];
	
    if (!lastPlayedTimeInterval || lastPlayedTimeInterval > now || lastPlayedTimeInterval < (now - ONE_WEEK)) {
        NSLog(@"Discarding invalid iTunesLastPlayedTime value (lastPlayedTime=%.0lf, now=%.0lf).\n",
			  lastPlayedTimeInterval, now);
        lastPlayedDate = [NSDate date];
    }
    
    [self setITunesLastPlayedTime:lastPlayedDate];
}

// FIXME: Why does this method exist?  Why not just prefs?
- (void) setITunesLastPlayedTime:(NSDate*)date
{
    [date retain];
    [_iTunesLastPlayedTime release];
    _iTunesLastPlayedTime = date;
    // Update prefs
    [[NSUserDefaults standardUserDefaults] setFloat:[_iTunesLastPlayedTime timeIntervalSince1970] forKey:@"iTunesLastPlayedTime"];
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
				NSLog(@"iPodSync: Discarding '%@' because of invalid play time.\n\t'%@' = Start: %@, Duration: %@"
					  "\n\t'%@' = Start: %@, Duration: %@\n", thisSong, lastSong, [lastSong postDate], [lastSong duration],
					  thisSong, [thisSong postDate], [thisSong duration]);
				[sorted removeObjectAtIndex:i];
				goto validate;
			}
		}
    
    return ([sorted autorelease]);
}

#define IPOD_UPDATE_SCRIPT_DATE_FMT @"%A, %B %d, %Y %I:%M:%S %p"
#define IPOD_UPDATE_SCRIPT_DATE_TOKEN @"Thursday, January 1, 1970 12:00:00 AM"
#define IPOD_UPDATE_SCRIPT_SONG_TOKEN @"$$$"

- (NSArray *)songsFromResultString:(NSString *)resultString {
	NSArray *songStrings = [resultString componentsSeparatedByString:IPOD_UPDATE_SCRIPT_SONG_TOKEN];
	NSEnumerator *songStringEnumerator = [songStrings objectEnumerator];
	NSString *songString = nil;
	
	SongData *song = nil;
	NSMutableArray *iPodSubmissionQueue = [NSMutableArray array];
	
	while ((songString = [songStringEnumerator nextObject])) {
		
		song = [SongData songWithiTunesResultString:songString];
		// Since this song was played "offline", we set the post date
		// in the past 
		NSTimeInterval postDate = [[song lastPlayed] timeIntervalSince1970] - [[song duration] doubleValue];
		[song setPostDate:[NSCalendarDate dateWithTimeIntervalSince1970:postDate]];
		// Make sure the song passes submission rules                            
		[song setStartTime:[NSDate dateWithTimeIntervalSince1970:postDate]];
		[song setPosition:[song duration]];
		
		[iPodSubmissionQueue addObject:song];
	}
	return iPodSubmissionQueue;
}

- (void)handleiPodUpdate:(NSString *)result {
	
	if (!result)
		return;
	
	if (![result hasPrefix:@"INACTIVE"]) {
		
		NSArray *iPodSubmissionQueue = [self songsFromResultString:result];
		iPodSubmissionQueue = [self validateIPodSync:iPodSubmissionQueue];
		
		SongData *song = nil;
		NSEnumerator *songEnumerator = [iPodSubmissionQueue objectEnumerator];
		
		while ((song = [songEnumerator nextObject])) {
			ISLog(@"syncIPod:", @"Queuing '%@' with postDate '%@'\n", song, [song postDate]);
			[[self submissionController] queueSongForSubmission:song];
		}
		
		[self setITunesLastPlayedTime:[NSDate date]];
	}
}

- (NSString *)iPodUpdateScriptUpdatedText {
	// Copy the script
	NSMutableString *text = [[_iPodUpdateScriptContents mutableCopy] autorelease];
	
	// Our main timer loop is only fired every 10 seconds, so we have to
	// make sure to adjust our time
	NSTimeInterval intervalToFudgedNow = [_iTunesLastPlayedTime timeIntervalSince1970] + MAIN_TIMER_INTERVAL;
	NSTimeInterval intervalToNow = [[NSDate date] timeIntervalSince1970];
	if (intervalToNow > intervalToFudgedNow) {
		[self setITunesLastPlayedTime:[NSDate dateWithTimeIntervalSince1970:intervalToFudgedNow]];
	} else {
		[self setITunesLastPlayedTime:[NSDate date]]; // why not use the interval?
	}
	
	// Replace the token with our last update
	[text replaceOccurrencesOfString:IPOD_UPDATE_SCRIPT_DATE_TOKEN
						  withString:[_iTunesLastPlayedTime descriptionWithCalendarFormat:
													IPOD_UPDATE_SCRIPT_DATE_FMT timeZone:nil locale:nil]
							 options:0 range:NSMakeRange(0, [text length])];
	
	ISLog(@"iPodUpdateScriptUpdatedText", @"Requesting songs played after '%@'\n",
		  [_iTunesLastPlayedTime descriptionWithCalendarFormat:IPOD_UPDATE_SCRIPT_DATE_FMT timeZone:nil locale:nil]);
	
	return text;
}

- (void)syncIPod:(id)sender
{
	// make sure we've loaded up the script text
	// this could be moved into it's own accessor....
	if (!_iPodUpdateScriptContents) {
		// Get our iPod update script as text
		NSString *iTunesScriptPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Scripts/iPodUpdate.applescript"];
		_iPodUpdateScriptContents = [[NSString alloc] initWithContentsOfFile:iTunesScriptPath];
		if (!_iPodUpdateScriptContents) {
			NSLog(@"Failed to find iPodUpdateScript.  (path = %@)", iTunesScriptPath);
			[self showApplicationIsDamagedDialog];
		}
	}
	
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"Sync iPod"]) {
		
		// get an up-to-date copy of the script text.
		NSString *scriptText = [self iPodUpdateScriptUpdatedText];
		
        // Run script
		NSDictionary *errInfo = nil;
		NSAppleEventDescriptor *result = [[[NSAppleScript alloc] initWithSource:scriptText] executeAndReturnError:&errInfo];
        
		// handle result
		[self handleiPodUpdateResult:[result stringValue]];
	}
}


#pragma mark -

- (void)deviceDidMount:(NSNotification*)notification
{
    NSDictionary *object = [notification object];
	NSString *mountPath = [object objectForKey:@"NSDevicePath"];
    NSString *iPodControlPath = [mountPath stringByAppendingPathComponent:@"iPod_Control"];
	
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:iPodControlPath isDirectory:&isDir] && isDir)
        [self setValue:mountPath forKey:@"iPodMountPath"];
	
	// FIXME: we should also pop up a 
}

- (void)deviceDidUnmount:(NSNotification*)notification
{
	NSDictionary *object = [notification object];
	NSString *mountPath = [object objectForKey:@"NSDevicePath"];
	
    if ([_iPodMountPath isEqualToString:mountPath])
        [self setValue:nil forKey:@"iPodMountPath"];
	
	[self iPodSync:nil]; // now that we're sure iTunes synced, we can sync...
}

@end
