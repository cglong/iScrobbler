//
//  iScrobblerController.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net/

// ECS 10/27/04: It looks like most of this code was stolen from
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

#define UNSUBMITTED_SONGS_PATH 

NSString *iScrobblerPrefsRecentSongsCountKey = @"Number of Songs to Save";
NSString *iScrobblerPrefsClientVersionKey = @"version";
NSString *iScrobblerPrefsClientIdKey = @"clientid";
NSString *iScrobblerPrefsProtocolVersionKey = @"protocol";
NSString *iScrobblerPrefsServerURLKey = @"url";


static BOOL haveCheckedLoggingDefault = NO;
static BOOL shouldLog = NO;

BOOL ISShouldLog() {
	if (!haveCheckedLoggingDefault) {
		shouldLog = [[[NSUserDefaults standardUserDefaults] boolForKey:@"EnableDebugLogging"] boolValue];
		haveCheckedLoggingDefault = YES;
	}
	return shouldLog;
}


// Logging
void ISLog(NSString *function, NSString *format, ...) {
	if (!ISShouldLog())
		return;
	NSLog(@"ISLog function = %@ format = %@", function, format);
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
	//ISLog(@"songWithiTunesResultString:", @"SongData allocated and filled");
	return song;
}
@end

@interface iScrobblerController (PrivateMethods)

- (void)iTunesUpdateTimer:(NSTimer *)timer; //called when mainTimer fires
- (void)_updateMenu; //sync _recentlyPlayedList and theMenu
- (void)_setupStatusItem;

- (void)addSongToRecentlyPlayedList:(SongData *)newSong;
- (SongData *)lastSongPlayed;
- (unsigned int)indexOfSongInRecentlyPlayedList:(SongData *)song;

- (NSString *)password;
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
		_iTunesUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:(10.0) // update from iTunes every 10 seconds.
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

@end
