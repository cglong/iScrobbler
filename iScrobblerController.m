//
//  iScrobblerController.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net/

#import "iScrobblerController.h"
#import <CURLHandle/CURLHandle.h>
#import <CURLHandle/CURLHandle+extras.h>
#import "PreferenceController.h"
#import "SongData.h"
#import "keychain.h"
#import "NSString+parse.h"
#import "CURLHandle+SpecialEncoding.h"
#import "NSDictionary+httpEncoding.h"
#import <mHashMacOSX/mhash.h>
#import <ExtFSDiskManager/ExtFSDiskManager.h>

#define IS_VERBOSE 1

@interface iScrobblerController ( private )

- (void) setURLHandle:(CURLHandle *)inURLHandle;
- (void) restoreITunesLastPlayedTime;
- (void) setITunesLastPlayedTime:(NSDate*)date;
- (void) queueSong:(SongData*)newSong;

// ExtFSManager notifications
- (void) volMount:(NSNotification*)notification;
- (void) volUnmount:(NSNotification*)notification;

@end

@interface SongData (ControllerPrivate)

- (NSComparisonResult) syncIPodSortHelper:(SongData*)song;

@end

@implementation iScrobblerController

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    //NSLog(@"%@",[anItem title]);
    if([[anItem title] isEqualToString:@"Clear Menu"])
        [mainTimer fire];
    else if([[anItem title] isEqualToString:@"Sync iPod"] &&
         (!iPodDisk || ![prefs boolForKey:@"Sync iPod"]))
        return NO;
    return YES;
}



-(id)init
{
    // Read in a defaults.plist preferences file
    NSString * file = [[NSBundle mainBundle]
        pathForResource:@"defaults" ofType:@"plist"];
	
    NSDictionary * defaultPrefs = [NSDictionary dictionaryWithContentsOfFile:file];
	
    songQueue = [[NSMutableArray alloc] init];
	
    prefs = [[NSUserDefaults standardUserDefaults] retain];
    [prefs registerDefaults:defaultPrefs];
	
    if(!myKeyChain)
        myKeyChain=[[KeyChain alloc] init];
	
    // Request the password and lease it, this will force it to ask
    // permission when loading, so it doesn't annoy you halfway through
    // a song.
    NSString * pass = [[[NSString alloc] init] autorelease];
    pass = [myKeyChain genericPasswordForService:@"iScrobbler" account:[prefs stringForKey:@"username"]];
    
    // Activate CURLHandle
    [CURLHandle curlHelloSignature:@"XxXx" acceptAll:YES];
    
    // Set the URL for CURLHandle
    NSURL * mainurl = [NSURL URLWithString:[prefs stringForKey:@"url"]];
    [self setURLHandle:(CURLHandle *)[mainurl URLHandleUsingCache:NO]];
	
    // Indicate that we have not yet handshaked
    haveHandshaked = NO;
	
	// Set the BADAUTH to false
	lastAttemptBadAuth = NO;
    
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
    
    [self restoreITunesLastPlayedTime];
    
    if(self=[super init])
    {
        script=[[NSAppleScript alloc] initWithContentsOfURL:url error:nil];
        nc=[NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(handleChangedNumRecentTunes:)
                   name:@"CDCNumRecentSongsChanged"
                 object:nil];
        
        // Initialize ExtFSManager
        (void)[ExtFSMediaController mediaController];
        
        // Register for ExtFSManager disk notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(volMount:)
                name:ExtFSMediaNotificationMounted
                object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(volUnmount:)
                name:ExtFSMediaNotificationUnmounted
                object:nil];
    }
    return self;
}

#define MAIN_TIMER_INTERVAL 10.0

- (void)awakeFromNib
{
    songList=[[NSMutableArray alloc ]init];
    
    [self setLastResult:@"No data sent yet."];
    //NSLog(@"lastResult: %@",lastResult);
	
    mainTimer = [[NSTimer scheduledTimerWithTimeInterval:(MAIN_TIMER_INTERVAL)
                                                  target:self
                                                selector:@selector(mainTimer:)
                                                userInfo:nil
                                                 repeats:YES] retain];
	
    queueTimer = [[NSTimer scheduledTimerWithTimeInterval:(60.0)
												   target:self
												 selector:@selector(queueTimer:)
												 userInfo:nil
												  repeats:YES] retain];
    
    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
	
    [statusItem setTitle:[NSString stringWithFormat:@"%C",0x266B]];
    [statusItem setHighlightMode:YES];
    [statusItem setMenu:theMenu];
    [statusItem setEnabled:YES];
	
    [mainTimer fire];
    [queueTimer fire];
}

- (void)updateMenu
{
    NSMenuItem *item;
    NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
    SongData *song;
    //   NSLog(@"updating menu");
	
    // remove songs from menu
    while(item=[enumerator nextObject])
        if([item action]==@selector(playSong:))
            [theMenu removeItem:item];
    
    // add songs from songList array to menu
    enumerator=[songList reverseObjectEnumerator];
    while ((song = [enumerator nextObject]))
    {
        //NSLog(@"Shit in song:\n%@",song);
        item = [[[NSMenuItem alloc] initWithTitle:[song title]
                                           action:@selector(playSong:)
                                    keyEquivalent:@""] autorelease];
        
        [item setTarget:self];
        [theMenu insertItem:item atIndex:0];
		//    NSLog(@"added item to menu");
    }
}

-(void)queueTimer:(NSTimer *)timer
{
    // Does the songQueue currently contain more than one item? If not, then
    // this whole exercise is meaningless. Lets check that first.
    if([songQueue count] > 1)
    {
        // What was the last result? If it wasn't an OK, then don't bother
        // attempting a submission.
        if([self lastResult] != nil && [[self lastResult] hasPrefix:@"OK"])
        {
            // All good, lets try a submission.
        }
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
        [song setLastPlayed:[NSDate dateWithNaturalLanguageString:[data objectAtIndex:8]]];
    //NSLog(@"SongData allocated and filled");
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
	
    //NSLog(@"timer fired");
    //NSLog(@"%@",result);
	
    // For Debugging: Display the contents of the parsed result array
    // NSLog(@"Shit in parsed result array:\n%@\n",parsedResult);
    
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
            NSLog(@"adding first item");
            [songList insertObject:song atIndex:0];
        }
        else
        {
            // Is the track equal to the track that's
            // currently in first place in the song list? If so, find out what percentage
            // of the song has been played, and queue a submission if necessary.
            if([song isEqualToSong:[songList objectAtIndex:0]])
            {
                [[songList objectAtIndex:0] setLastPlayed:[song lastPlayed]];
                // If the song hasn't been queued yet, see if its ready.
                if(![[songList objectAtIndex:0] hasQueued])
                {
                    if([[[songList objectAtIndex:0] percentPlayed] floatValue] > 50 ||
                       [[[songList objectAtIndex:0] timePlayed] floatValue] > 120 )
                    {
                        NSLog(@"Ready to send.");
                        [[songList objectAtIndex:0] setHasQueued:YES];
                        [songQueue insertObject:[[[songList objectAtIndex:0] copy] autorelease]
                                        atIndex:0];
                        NSLog(@"Preparing send.");
                        [self sendData];
                        NSLog(@"Sent");
                        //NSLog(@"songQueue at timer: %@",songQueue);
                    }
                }
            } else {
                // Check to see if the current track is anywhere in the songlist
                // If it is, we set found equal to the index position where it was found
                // NSLog(@"Looking for track");
                int j;
                int found = 0;
                for(j = 0; j < [songList count]; j++) {
                    if([[songList objectAtIndex:j] isEqualToSong:song])
                    {
                        found = j;
                        break;
                    }
                }
                //NSLog(@"Found = %i",j);
				
                // If the track wasn't found anywhere in the list, we add a new item
                if(!found)
                {
                    NSLog(@"adding new item");
                    [songList insertObject:song atIndex:0];
                }
                // If the trackname was found elsewhere in the list, we remove the old
                // item, and add the new one onto the beginning of the list.
                else
                {
                    //NSLog(@"removing old, adding new");
                    [songList removeObjectAtIndex:found];
                    [songList insertObject:song atIndex:0];
                }
            }
        }
        // If there are more items in the list than the user wanted
        // Then we remove the last item in the songlist
        while([songList count]>[prefs integerForKey:@"Number of Songs to Save"]) {
            //NSLog(@"Removed an item from songList");
            [songList removeObject:[songList lastObject]];
        }
		
        //NSLog(@"About to release song and parsedResult");
        [self updateMenu];
        [song release];
        [parsedResult release];
        //NSLog(@"song and parsedResult released");
    }
    
    [result release];
    //NSLog(@"result released");
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
	
	NSLog(@"clearing menu");
    [songList removeAllObjects];
    
	while(item=[enumerator nextObject])
        if([item action]==@selector(playSong:))
            [theMenu removeItem:item];
	
	[mainTimer fire];
}

-(IBAction)openPrefs:(id)sender{
    // NSLog(@"opening prefs");
    if(!preferenceController)
        preferenceController=[[PreferenceController alloc] init];
	
    [preferenceController takeValue:[self lastResult] forKey:@"lastResult"];
    
    if([songQueue count] != 0)
        [preferenceController takeValue:[songQueue objectAtIndex:0] forKey:@"songData"];
	
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
    
	[myURLHandle release];
	[CURLHandle curlGoodbye];
	[nc removeObserver:self];
	[nc release];
	[lastResult release];
	[lastHandshakeResult release];
	[myKeyChain release];
	[songQueue release];
	[statusItem release];
	[songList release];
	[script release];
	[md5Challenge release];
	[submitURL release];
	[mainTimer invalidate];
	[mainTimer release];
	[prefs release];
	[preferenceController release];
	[super dealloc];
}

- (void)handshake
{
    NSString* url = [prefs stringForKey:@"url"];
	
    url = [url stringByAppendingString:@"?hs=true"];
	
    NSString* escapedusername=[(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[prefs stringForKey:@"username"], NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) 	autorelease];
	url = [url stringByAppendingString:@"&u="];
	url = [url stringByAppendingString:escapedusername];
	
	url = [url stringByAppendingString:@"&p="];
	url = [url stringByAppendingString:[prefs stringForKey:@"protocol"]];
	
	url = [url stringByAppendingString:@"&v="];
	url = [url stringByAppendingString:[prefs stringForKey:@"version"]];
	
	url = [url stringByAppendingString:@"&c="];
	url = [url stringByAppendingString:[prefs stringForKey:@"clientid"]];
	
	NSLog(@"Handshaking... %@", url);
	
	NSURL *nsurl = [NSURL URLWithString:url];
	//NSLog(@"nsurl: %@",nsurl);
	//NSLog(@"host: %@",[nsurl host]);
	//NSLog(@"query: %@", [nsurl query]);
	
	CURLHandle *handshakeHandle = (CURLHandle*)[CURLHandle cachedHandleForURL:nsurl];	
	
	// fail on errors (response code >= 300)
    [handshakeHandle setFailsOnError:YES];
	[handshakeHandle setFollowsRedirects:YES];
	[handshakeHandle setConnectionTimeout:30];
	
    // Set the user-agent to something Mozilla-compatible
    [handshakeHandle setUserAgent:[prefs stringForKey:@"useragent"]];
	
	NSData *data = [handshakeHandle loadInForeground];
	[handshakeHandle flushCachedData];
	NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
	NSLog(@"Result: %@", result);
	if ([result length] == 0) {
		NSLog(@"Connection failed");
		result = [[NSString alloc] initWithString:@"FAILED\nConnection failed"];
	}
	
	NSArray *splitResult = [result componentsSeparatedByString:@"\n"];
	NSString *handshakeResult = [splitResult objectAtIndex:0];
	[self changeLastHandshakeResult:handshakeResult];
	
	if ([handshakeResult hasPrefix:@"UPTODATE"] ||
		[handshakeResult hasPrefix:@"UPDATE"]) {
		
		md5Challenge = [[NSString alloc] initWithString:[splitResult objectAtIndex:1]];
		submitURL = [[NSString alloc] initWithString:[splitResult objectAtIndex:2]];
		
		NSURL *nsurl = [NSURL URLWithString:submitURL];
		[myURLHandle setURL:nsurl];
		
		//TODO: INTERVAL stuff
		
		haveHandshaked = YES;
	}
	
	// If we get any response other than "UPTODATE" or "FAILED", open
	// the preferences window to display the information.
	if ([handshakeResult hasPrefix:@"BADUSER"] ||
		[handshakeResult hasPrefix:@"UPDATE"]) {
		[self openPrefs:self];
	}
}

- (void)sendData
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    int submissionCount = [songQueue count];
    int i;
	
    // First things first, we must execute a server handshake before
    // doing anything else. If we've already handshaked, then no
    // worries.
    if(!haveHandshaked)
    {
		NSLog(@"Need to handshake");
		[self handshake];
    }
	
	if (haveHandshaked) {
		NSString* escapedusername=[(NSString*)
			CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[prefs 	stringForKey:@"username"], NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) 	autorelease];
		
		[dict setObject:escapedusername forKey:@"u"];
		
		//retrieve the password from the keychain, and hash it for sending
		NSString *pass = [[NSString alloc] initWithString:[myKeyChain genericPasswordForService:@"iScrobbler" account:[prefs 	stringForKey:@"username"]]];
		//NSLog(@"pass: %@", pass);
		NSString *hashedPass = [[NSString alloc] initWithString:[self md5hash:[pass autorelease]]];
		//NSLog(@"hashedPass: %@", hashedPass);
		//NSLog(@"md5Challenge: %@", md5Challenge);
		NSString *concat = [[NSString alloc] initWithString:[[hashedPass autorelease] stringByAppendingString:md5Challenge]];
		//NSLog(@"concat: %@", concat);
		NSString *response = [[NSString alloc] initWithString:[self md5hash:[concat autorelease]]];
		//NSLog(@"response: %@", response);
		
		[dict setObject:response forKey:@"s"];
		[response autorelease];
		
		// Fill the dictionary with every entry in the songQueue, ordering them from
		// oldest to newest.
		for(i=submissionCount-1; i >= 0; i--) {
			[dict addEntriesFromDictionary:[[songQueue objectAtIndex:i] postDict:
				(submissionCount - 1 - i)]];
		}
		
		// fail on errors (response code >= 300)
		[myURLHandle setFailsOnError:YES];
		[myURLHandle setFollowsRedirects:YES];
		
		// Set the user-agent to something Mozilla-compatible
		[myURLHandle setUserAgent:[prefs stringForKey:@"useragent"]];
		
		//NSLog(@"dict before sending: %@",dict);
		// Handle "POST"
		[myURLHandle setSpecialPostDictionary:dict encoding:NSUTF8StringEncoding];
		
		// And load in background...
		[myURLHandle addClient:self];
		[myURLHandle loadInBackground];
		
		[dict release];
		
		NSLog(@"Data loading...");
	}
}

- (void)URLHandleResourceDidFinishLoading:(NSURLHandle *)sender
{
    int i;
    NSData *data = [myURLHandle resourceData];
    NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
    [self changeLastResult:result];
    NSLog(@"songQueue count after loading: %d", [songQueue count]);
	
	NSLog(@"Server result: %@", result);
    // Process Body, if OK, then remove the last song from the queue
    if([result hasPrefix:@"OK"])
    {
		int count = [songQueue count];
        for(i=0; i < count; i++)
        {
            [songQueue removeObjectAtIndex:0];
        }
        NSLog(@"songQueue cleaned, count = %i",[songQueue count]);
    } else {
        NSLog(@"Server error, songs left in queue, count = %i",[songQueue count]);
		haveHandshaked = NO;
		
		// If the password is wrong, show the preferences window.
		if ([result hasPrefix:@"BADAUTH"]) {
			// Only show the preferences window if we get BADAUTH
			// twice in a row.
			if (lastAttemptBadAuth) {
				[self openPrefs:self];
			} else {
			    lastAttemptBadAuth = YES;
			}
		} else {
			lastAttemptBadAuth = NO;
		}
    }
	
    [myURLHandle removeClient:self];
    
    //NSLog(@"songQueue: %@",songQueue);
	
    //NSLog(@"lastResult: %@",lastResult);
    
}

-(void)URLHandleResourceDidBeginLoading:(NSURLHandle *)sender { }

-(void)URLHandleResourceDidCancelLoading:(NSURLHandle *)sender
{
    [myURLHandle removeClient:self];
}

-(void)URLHandle:(NSURLHandle *)sender resourceDataDidBecomeAvailable:(NSData *)newBytes { }

-(void)URLHandle:(NSURLHandle *)sender resourceDidFailLoadingWithReason:(NSString *)reason
{
    [self changeLastResult:reason];
    [myURLHandle removeClient:self];
	
    NSLog(@"Connection error, songQueue count: %d",[songQueue count]);
}

- (NSString *)lastResult
{
    return lastResult;
}

- (void)changeLastResult:(NSString *)newResult
{
    [self setLastResult:newResult];
	
    //NSLog(@"song data before sending: %@",[songQueue objectAtIndex:0]);
    [preferenceController takeValue:[self lastResult] forKey:@"lastResult"];
    if ([songQueue count]) {
        [preferenceController takeValue:[[[songQueue objectAtIndex:0] copy] autorelease]
                             forKey:@"songData"];
    }
    [nc postNotificationName:@"lastResultChanged" object:self];
	
    NSLog(@"result changed");
}


- (void)setLastResult:(NSString *)newResult
{
    [newResult retain];
    [lastResult release];
    lastResult = newResult;
}

- (NSString *)lastHandshakeResult
{
    return lastHandshakeResult;
}

- (void)changeLastHandshakeResult:(NSString *)newHandshakeResult
{
    [self setLastHandshakeResult:newHandshakeResult];
	
    [preferenceController setLastHandshakeResult:[self lastHandshakeResult]];
    [nc postNotificationName:@"lastHandshakeResultChanged" object:self];
	
    NSLog(@"Handshakeresult changed: %@", [self lastHandshakeResult]);
}


- (void)setLastHandshakeResult:(NSString *)newHandshakeResult
{
    [newHandshakeResult retain];
    [lastHandshakeResult release];
    lastHandshakeResult = newHandshakeResult;
}

- (void)setURLHandle:(CURLHandle *)inURLHandle
{
    [inURLHandle retain];
    [myURLHandle release];
    myURLHandle = inURLHandle;
}

- (NSString *)md5hash:(NSString *)input
{
    MHASH td;
    unsigned char *hash;
    char *buffer,*p;
    int digestByteSize, digestStringSize, i;
    static const char *hex_digits = "0123456789abcdef";
    NSString *digestHexText;
	
    // Define the digest byte size, then initialize the
    // hashing thread.
    digestByteSize=mhash_get_block_size(MHASH_MD5);
    td = mhash_init(MHASH_MD5);
    if (td == MHASH_FAILED) NSLog(@"Hash init failed..");
	
    // Perform the hash with the given data
    mhash(td, [input cString], strlen([input cString]));
	
    // Close the hashing thread and dump the data
    hash = mhash_end(td);
	
    // Convert the data returned into a string
    digestStringSize=2*digestByteSize+1;
    p=malloc(digestStringSize);
    buffer=p;
    
    for (i = 0; i <digestByteSize; i++) {
        *buffer++ = hex_digits[(*hash & 0xf0) >> 4];
        *buffer++ = hex_digits[*hash & 0x0f];
		hash++;
    }
    
    *buffer = (char)0;
    digestHexText=[NSString stringWithCString:p];
    free(p);
	
    //NSLog(@"Returning... %@",digestHexText);
    return digestHexText;
}

#define ONE_WEEK (3600.0 * 24.0 * 7.0)
- (void) restoreITunesLastPlayedTime
{
    NSTimeInterval ti = [prefs floatForKey:@"iTunesLastPlayedTime"];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDate *tr = [NSDate dateWithTimeIntervalSince1970:ti];

    if (!ti || ti > now || ti < (now - ONE_WEEK)) {
        NSLog(@"Discarding invalid iTunesLastPlayedTime value (ti=%.0lf, now=%.0lf).\n",
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
    [prefs setFloat:[iTunesLastPlayedTime timeIntervalSince1970] forKey:@"iTunesLastPlayedTime"];
}

- (void)queueSong:(SongData*)newSong
{
    SongData *song;
    NSEnumerator *en = [songQueue objectEnumerator];
    
    while ((song = [en nextObject])) {
        if ([song isEqualToSong:newSong])
            break;
    }
    
    if (song) {
        // Found in queue
        // Check to see if the song has been played again
        if (![[newSong lastPlayed] isGreaterThan:[song lastPlayed]] ||
             // And make sure the duration is valid
             [[newSong lastPlayed] timeIntervalSince1970] <=
             ([[song lastPlayed] timeIntervalSince1970] + [[song duration] doubleValue]) )
            return;
        // Otherwise, the song will be in the queue twice,
        // on the assumption that it has been played again
    }
    
    if ([songQueue count] > 0) {
        // Verify post date
        song = [songQueue objectAtIndex:0];
        if (![[newSong postDate] isGreaterThan:[song postDate]]) {
            NSLog(@"Discarding \"%@, %@, %@\", invalid post date (q=%@, s=%@)\n",
                [newSong title], [newSong album], [newSong artist], [song postDate], [newSong postDate]);
            return;
        }
    }
    
    // Add to top of list
    [newSong setHasQueued:YES];
    [songQueue insertObject:newSong atIndex:0];
}

#define IPOD_UPDATE_SCRIPT_DATE_FMT @"%A, %B %d, %Y %I:%M:%S %p"
#define IPOD_UPDATE_SCRIPT_DATE_TOKEN @"Thursday, January 1, 1970 12:00:00 AM"
#define IPOD_UPDATE_SCRIPT_SONG_TOKEN @"$$$"

- (void)syncIPod:(id)sender
{
    if (iPodUpdateScript && [prefs boolForKey:@"Sync iPod"]) {
        // Copy the script
        NSMutableString *text = [iPodUpdateScript mutableCopy];
        NSAppleScript *iuscript;
        NSAppleEventDescriptor *result;
        NSDictionary *errInfo;
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
        
        // Replace the token with our last update
        [text replaceOccurrencesOfString:IPOD_UPDATE_SCRIPT_DATE_TOKEN
            withString:[iTunesLastPlayedTime descriptionWithCalendarFormat:
                IPOD_UPDATE_SCRIPT_DATE_FMT timeZone:nil locale:nil]
            options:0 range:NSMakeRange(0, [iPodUpdateScript length])];
        
#ifdef IS_VERBOSE
        NSLog(@"syncIPod: Requesting songs played after '%@'\n",
            [iTunesLastPlayedTime descriptionWithCalendarFormat:IPOD_UPDATE_SCRIPT_DATE_FMT timeZone:nil locale:nil]);
#endif
        // Run script
        iuscript = [[NSAppleScript alloc] initWithSource:text];
        if ((result = [iuscript executeAndReturnError:&errInfo])) {
            if (![[result stringValue] hasPrefix:@"INACTIVE"]) {
                NSArray *songs = [[result stringValue]
                    componentsSeparatedByString:IPOD_UPDATE_SCRIPT_SONG_TOKEN];
                NSEnumerator *en = [songs objectEnumerator];
                NSString *data;
                SongData *song;
                NSMutableArray *iqueue;
                
                added = 0;
                iqueue = [[NSMutableArray alloc] init];
                while ((data = [en nextObject])) {
                    NSArray *components = [data componentsSeparatedByString:@"***"];
                    NSTimeInterval postDate;
                    
                    if ([components count] > 1) {
                        song = [self createSong:components];
                        if ([[song duration] doubleValue] < 30.0)
                            continue;
                        // Since this song was played "offline", we set the post date
                        // in the past 
                        postDate = [[song lastPlayed] timeIntervalSince1970] - [[song duration] doubleValue];
                        [song setPostDate:[NSCalendarDate dateWithTimeIntervalSince1970:postDate]];
                        [iqueue addObject:song];
                        [song release];
                        ++added;
                    }
                }
                [self setITunesLastPlayedTime:[NSDate date]];
                if (added > 0) {
                    // Order the array from oldest to newest so we don't trigger spam protection
                    // (sendData uses the queue order to determine submission order)
                    NSArray *submissions = [iqueue sortedArrayUsingSelector:@selector(syncIPodSortHelper:)];
                    int i = 0;
                    for (; i < [submissions count]; ++i) {
                        song = [submissions objectAtIndex:i];
                    #ifdef IS_VERBOSE
                        NSLog(@"syncIPod: Queuing '%@, %@, %@' with postDate '%@'\n",
                            [song title], [song album], [song artist], [song postDate]);
                    #endif
                        [self queueSong:song];
                    }
                    [self sendData];
                }
                    
                [iqueue release];
            }
        } else if (!iPodUpdateScript) {
            // Script error
            NSLog(@"iPodUpdateScript error: %@\n", errInfo);
        }
        
        [iuscript release];
        
        [text release];
    
    } else {
        NSLog(@"iPodUpdateScript missing\n");
    }
}

// ExtFSManager notifications
- (void)volMount:(NSNotification*)notification
{
    ExtFSMedia *media = [notification object];
    NSString *iPodCtl =
        [[media mountPoint] stringByAppendingPathComponent:@"iPod_Control"];
    BOOL isDir;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:iPodCtl isDirectory:&isDir]
         && isDir) {
        iPodDisk = [media retain];
    }
}

- (void)volUnmount:(NSNotification*)notification
{
    if (iPodDisk != [notification object])
        return;
    
    [iPodDisk release];
    iPodDisk = nil;
    
    [self syncIPod:nil];
}

@end

@implementation SongData (ControllerPrivate)

- (NSComparisonResult) syncIPodSortHelper:(SongData*)song
{
    return ([[self postDate] compare:[song postDate]]);
}

@end
