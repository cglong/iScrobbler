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

@interface iScrobblerController ( private )

- (void) setURLHandle:(CURLHandle *)inURLHandle;

@end


@implementation iScrobblerController

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    //NSLog(@"%@",[anItem title]);
    if([[anItem title] isEqualToString:@"Clear Menu"])
        [mainTimer fire];
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
	
    // Request the password and release it, this will force it to ask
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
    
	// Create an instance of the preferenceController
    if(!preferenceController)
        preferenceController=[[PreferenceController alloc] init];
	
	// Set the script locations
    NSURL *url=[NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath]
                stringByAppendingPathComponent:@"Scripts/controlscript.scpt"] ];
	
    if(self=[super init])
    {
        script=[[NSAppleScript alloc] initWithContentsOfURL:url error:nil];
        nc=[NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(handleChangedNumRecentTunes:)
                   name:@"CDCNumRecentSongsChanged"
                 object:nil];
    }
    return self;
}

- (void)awakeFromNib
{
    songList=[[NSMutableArray alloc ]init];
    
    [self setLastResult:@"No data sent yet."];
    //NSLog(@"lastResult: %@",lastResult);
	
    mainTimer = [[NSTimer scheduledTimerWithTimeInterval:(10.0)
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

-(void)mainTimer:(NSTimer *)timer
{
    //NSLog(@"timer ready");
    NSString *result=[[NSString alloc] initWithString:[[script executeAndReturnError:nil]  	stringValue]];
	
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
		
        // Make a SongData object out of the array
        SongData * song = [[SongData alloc] init];
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
        //NSLog(@"SongData allocated and filled");
		
        // If the songlist is empty, then simply add the song object to the songlist
        if([songList count]==0)
        {
            NSLog(@"adding first item");
            [songList insertObject:song atIndex:0];
        }
        else
        {
            // is the title of the result track the same as the title of the track thats
            // currently in first place in the song list? If so, find out what percentage
            // of the song has been played, and queue a submission if necessary.
            if([[song title] isEqualToString:[[songList objectAtIndex:0] title]])
            {
                printf("percentPlayed: %.1f\n",[[[songList objectAtIndex:0] percentPlayed]
                    floatValue]);
                printf("timePlayed: %.1f\n",[[[songList objectAtIndex:0] timePlayed]
                    floatValue]);
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
                // Check to see if the current result's track name is anywhere in the songlist
                // If it is, we set found equal to the index position where it was found
                // NSLog(@"Looking for track");
                int j;
                int found = 0;
                for(j = 0; j < [songList count]; j++) {
                    if([[[songList objectAtIndex:j] title] isEqualToString:[song title]])
                    {
                        found = j;
                        break;
                    }
                }
                //NSLog(@"Found = %i",j);
				
                // If the trackname wasn't found anywhere in the list, we add a new item
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
	
	CURLHandle *handshakeHandle = [CURLHandle cachedHandleForURL:nsurl];	
	
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
			[self openPrefs:self];
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
	
    NSLog(@"song data before sending: %@",[songQueue objectAtIndex:0]);
    [preferenceController takeValue:[self lastResult] forKey:@"lastResult"];
    [preferenceController takeValue:[[[songQueue objectAtIndex:0] copy] autorelease]
                             forKey:@"songData"];
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


@end
