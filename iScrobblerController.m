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

    prefs = [[NSUserDefaults standardUserDefaults] retain];
    [prefs registerDefaults:defaultPrefs];

    if(!myKeyChain)
        myKeyChain=[[KeyChain alloc] init];
    
    // Activate CURLHandle
    [CURLHandle curlHelloSignature:@"XxXx" acceptAll:YES];
    
    // Set the URL for CURLHandle
    NSURL * mainurl = [NSURL URLWithString:[prefs stringForKey:@"url"]];
    [self setURLHandle:(CURLHandle *)[mainurl URLHandleUsingCache:NO]];
    
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
                                                selector:@selector(timer:)
                                                userInfo:nil
                                                 repeats:YES] retain];

    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];

    [statusItem setTitle:[NSString stringWithFormat:@"%C",0x266B]];
    [statusItem setHighlightMode:YES];
    [statusItem setMenu:theMenu];
    [statusItem setEnabled:YES];

    [mainTimer fire];
}

- (void)updateMenu
{
    NSMenuItem *item;
    NSEnumerator *enumerator = [[theMenu itemArray] objectEnumerator];
    SongData *song;
       NSLog(@"updating menu");

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
        NSLog(@"added item to menu");
    }
}

-(void)timer:(NSTimer *)timer
{
    NSLog(@"timer ready");
    NSString *result=[[NSString alloc] initWithString:[[script executeAndReturnError:nil]  	stringValue]];

    //NSLog(@"timer fired");
    //NSLog(@"%@",result);

    // For Debugging: Display the contents of the parsed result array
    // NSLog(@"Shit in parsed result array:\n%@\n",parsedResult);
    
    // If the script didn't return an error, continue
    if([result isEqualToString:@"NOT PLAYING"]) {

    } else if([result isEqualToString:@"RADIO"]) {

    } else if([result isEqualToString:@"INACTIVE"]) {
        
    } else {
        // Parse the result and create an array
        NSArray *parsedResult = [[NSArray alloc] initWithArray:[result 				componentsSeparatedByString:@"***"]];

        // Make a SongData object out of the array
        SongData * song = [[SongData alloc] init];
        [song setTrackIndex:[NSNumber numberWithFloat:[[parsedResult objectAtIndex:0] floatValue]]];
        [song setPlaylistIndex:[NSNumber numberWithFloat:[[parsedResult objectAtIndex:1] floatValue]]];
        [song setTitle:[parsedResult objectAtIndex:2]];
        [song setDuration:[NSNumber numberWithFloat:[[parsedResult objectAtIndex:3] floatValue]]];
        [song setPosition:[NSNumber numberWithFloat:[[parsedResult objectAtIndex:4] floatValue]]];
        [song setArtist:[parsedResult objectAtIndex:5]];
        [song setPath:[parsedResult objectAtIndex:6]];
        NSLog(@"SongData allocated and filled");

        // If the songlist is empty, then simply add the song object to the songlist
        if([songList count]==0)
        {
            NSLog(@"adding first item");
            [songList addObject:song];
        }
        else
        {
            // is the title of the result track the same as the title of the track thats
            // currently in first place in the song list? If so, find out what percentage
            // of the song has been played, and queue a submission if necessary.
            if([[song title] isEqualToString:[[songList objectAtIndex:0] title]])
            {
                printf("Song position: %.1f\n",[[song percentPlayed] floatValue]);
                
                if([[song percentPlayed] floatValue] > 50)
                {
                    NSLog(@"Ready to queue.");
                    [self queueData:song];
                }
            } else {
                // Check to see if the current result's track name is anywhere in the songlist
                // If it is, we set found equal to the index position where it was found
                 NSLog(@"Looking for track");
                int j;
                int found = 0;
                for(j = 0; j < [songList count]; j++) {
                    if([[[songList objectAtIndex:j] title] isEqualToString:[song title]])
                    {
                        found = j;
                        break;
                    }
                }
                NSLog(@"Found = %i",j);

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
                   NSLog(@"removing old, adding new");
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

        NSLog(@"About to release song and parsedResult");
        [self updateMenu];
        [song release];
        [parsedResult release];
        NSLog(@"song and parsedResult released");
    }
    
    [result release];
    NSLog(@"result released");
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

    [preferenceController takeValue:lastResult forKey:@"lastResult"];
    [preferenceController takeValue:songData forKey:@"songData"];

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
    NSString *prefix = @"http://www.audioscrobbler.com/modules.php?op=modload&name=top10&file=userinfo&user=";
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
     [myKeyChain release];
     //[queue release];
     [statusItem release];
     [songList release];
     [songData release];
     [script release];
     [mainTimer invalidate];
     [mainTimer release];
     [prefs release];
     [preferenceController release];
     [super dealloc];
}

- (void)queueData:(SongData *)song
{
    //int ready = 0;
    [song retain];

    NSLog(@"Queuing");
        
    [song release];
}

- (void)sendData:(SongData *)song
{
    //NSLog(@"myURLHandle: %@",myURLHandle);
    //printf("URL: %s\n",[[url absoluteString] UTF8String]);
    //NSLog(@"Array for dictionarying: %@",array);
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[song postDict]];

    NSString* escapedusername=[(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[prefs 	stringForKey:@"username"], NULL, (CFStringRef)@"&+", kCFStringEncodingUTF8) 	autorelease];
    
    [dict setObject:escapedusername forKey:@"username"];
    [dict setObject:[prefs stringForKey:@"version"] forKey:@"version"];

    //retrieve the password from the keychain, and hash it for sending
    
    NSString *toHash = [[NSString alloc] initWithString:[myKeyChain 	genericPasswordForService:@"iScrobbler" account:[prefs 	stringForKey:@"username"]]];

    NSString *pass = [[NSString alloc] initWithString:[self md5hash:[toHash 	autorelease]]];

    //NSLog(@"hashed password: %@",pass);
    [dict setObject:pass forKey:@"password"];

    [pass autorelease];

    //NSLog(@"pass released");
    [self setSongData:dict];
    [dict release];
    
    //NSLog(@"Dictionary Created: %@",[self songData]);
    
    // fail on errors (response code >= 300)
     [myURLHandle setFailsOnError:YES];
     [myURLHandle setFollowsRedirects:YES];

    // Set the user-agent to something Mozilla-compatible
    [myURLHandle setUserAgent:[prefs stringForKey:@"useragent"]];
    
    // Handle "POST"
    [myURLHandle setPostDictionary:[self songData] encoding:NSASCIIStringEncoding];

    // And load in background...
    [myURLHandle addClient:self];
    [myURLHandle loadInBackground];

    // NSLog(@"Data loading...");
}

- (void)URLHandleResourceDidFinishLoading:(NSURLHandle *)sender
{
    NSData *data = [myURLHandle resourceData];	

    // Process Body
    [self changeLastResult:[[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding]];
    //NSLog(@"lastResult: %@",lastResult);
    
}

-(void)URLHandleResourceDidBeginLoading:(NSURLHandle *)sender {}

-(void)URLHandleResourceDidCancelLoading:(NSURLHandle *)sender
{
    [myURLHandle removeClient:self];
}

-(void)URLHandle:(NSURLHandle *)sender resourceDataDidBecomeAvailable:(NSData *)newBytes {}

-(void)URLHandle:(NSURLHandle *)sender resourceDidFailLoadingWithReason:(NSString *)reason
{
    [self changeLastResult:reason];
    [myURLHandle removeClient:self];
}

- (NSString *)lastResult
{
    return lastResult;
}

- (void)changeLastResult:(NSString *)newResult
{
    [self setLastResult:newResult];
    
    //NSLog(@"song data before sending: %@",songData);
    [preferenceController takeValue:[self lastResult] forKey:@"lastResult"];
    [preferenceController takeValue:[self songData] forKey:@"songData"];
    [nc postNotificationName:@"lastResultChanged" object:self];
   
    //NSLog(@"result changed");

   
}


- (void)setLastResult:(NSString *)newResult
{
    [newResult retain];
    [lastResult release];
    lastResult = newResult;
}

-(void)setSongData: (NSMutableDictionary *)newSongData
{
    [newSongData retain];
    [songData release];
    songData = newSongData;
}

-(NSMutableDictionary *)songData
{
    return songData;
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
