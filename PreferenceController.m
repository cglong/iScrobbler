//
//  PreferenceController.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "PreferenceController.h"
// PreferenceControllerStrings.h contains definitions of program strings.
#import "PreferenceControllerStrings.h"
#import "keychain.h"

NSString *CDCNumSongsKey=@"Number of Songs to Save";

@implementation PreferenceController

-(id)init
{
    if(self=[super initWithWindowNibName:@"Preferences"]){
        [self setWindowFrameAutosaveName:@"PrefWindow"];
    }
    if(!myKeyChain)
        myKeyChain=[[KeyChain alloc] init];

    prefs = [[NSUserDefaults standardUserDefaults] retain];
    nc=[NSNotificationCenter defaultCenter];
    return self;
}

-(void)awakeFromNib
{
    [nc addObserver:self selector:@selector(handleLastResultChanged:)
               name:@"lastResultChanged"
             object:nil];
}

-(void)windowDidLoad
{
    [versionNumber setStringValue:[[prefs stringForKey:@"version"] substringToIndex:5]];
    [self updateFields];
    [window makeMainWindow];
}


-(void)savePrefs
{
    [prefs setObject:[username stringValue] forKey:@"username"];
    [prefs setInteger:[numRecentSongsField intValue] forKey:CDCNumSongsKey];
        
    [prefs synchronize];
    //NSLog(@"prefs saved");

    if(![[password stringValue] isEqualToString:@""])
    {
        [myKeyChain setGenericPassword:[password stringValue]
                                 forService:@"iScrobbler"
                                    account:[prefs stringForKey:@"username"]];
        // NSLog(@"password stored as: %@",[myKeyChain genericPasswordForService:@"iScrobbler"
        //                                                account:[prefs stringForKey:@"username"]]);
    }
    [nc postNotificationName:@"CDCNumRecentSongsChanged" object:self];
}

- (void)handleLastResultChanged:(NSNotification *)notification
{
    [self updateFields];
}

-(void)generateResultText
{
    if([self lastResult] == nil) {
        [self setLastResult:@"No connection yet."];
        [self setLastResultLong:NO_CONNECTION_LONG];
        [self setLastResultShort:NO_CONNECTION_SHORT];
    } else if([[self lastResult] hasPrefix:@"No data sent yet."]) {
        [self setLastResultLong:NO_CONNECTION_LONG];
        [self setLastResultShort:NO_CONNECTION_SHORT];        
    //Check to see if the program is up to date..
    } else if([[self lastResult] hasPrefix:@"OK OUTOFDATE"]) {
        NSMutableDictionary * attribs = [NSMutableDictionary dictionary];
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        [style setAlignment:NSCenterTextAlignment];
        [attribs setObject:[NSColor colorWithCalibratedRed:1.0
                                                     green:0.0
                                                      blue:0.0
                                                     alpha:1.0]
                    forKey:NSForegroundColorAttributeName];
        [attribs setObject:[style autorelease] forKey:NSParagraphStyleAttributeName];
        NSAttributedString * attribString = [[NSAttributedString alloc] initWithString:NOT_UPTODATE 		attributes:attribs];
        [self setLastResultShort:SUBMISSION_SUCCESS_OUTOFDATE_SHORT];
        [self setLastResultLong:SUBMISSION_SUCCESS_OUTOFDATE_LONG];
        [versionWarning setStringValue:[attribString autorelease]];
        [updateButton setEnabled:YES];
        [self setDownloadURL:[[lastResult componentsSeparatedByString:@" "] objectAtIndex:2]];
    //Check for spam protection.
    } else if([[self lastResult] hasPrefix:@"OK\nNot really ok"]) {
        [self setLastResultShort:SPAM_PROTECT_SHORT];
        [self setLastResultLong:SPAM_PROTECT_LONG];
    //Check to see if the script returns OK
    } else if([[self lastResult] hasPrefix:@"OK"]) {
        [self setLastResultShort:SUBMISSION_SUCCESS_SHORT];
        [self setLastResultLong:SUBMISSION_SUCCESS_LONG];
    } else if([[self lastResult] hasPrefix:@"FAIL"]) {
        [self setLastResultShort:FAILURE_SHORT];
        [self setLastResultLong:FAILURE_LONG];
    } else if([[self lastResult] hasPrefix:@"BAD"]) {
        [self setLastResultShort:AUTH_SHORT];
        [self setLastResultLong:AUTH_LONG];
    } else if([[self lastResult] hasPrefix:@"Couldn't resolve"]) {
        [self setLastResultShort:COULDNT_RESOLVE_SHORT];
        [self setLastResultLong:COULDNT_RESOLVE_LONG];
    } else if([[self lastResult] hasPrefix:@"The requested file was not found"]) {
        [self setLastResultShort:NOT_FOUND_SHORT];
        [self setLastResultLong:NOT_FOUND_LONG];
    } else {
        [self setLastResultShort:UNKNOWN_SHORT];
        [self setLastResultLong:UNKNOWN_LONG];
    }
}    

- (void)updateFields
{
    [self generateResultText];
    [numRecentSongsField setIntValue:[prefs integerForKey:CDCNumSongsKey]];
    [username setStringValue:[prefs stringForKey:@"username"]];
    [lastResultDataField setString:[self lastResult]];
    [lastResultLongField setString:[self lastResultLong]];
    [lastResultShortField setStringValue:[self lastResultShort]];

    //NSLog(@"songdata: %@",songData);
    
    if(songData != nil)
    {
        NSMutableString* unEscapedTitle = [NSMutableString stringWithString:[(NSString*)
        CFURLCreateStringByReplacingPercentEscapes(NULL, (CFStringRef)[songData 		objectForKey:@"title"], (CFStringRef)@"") autorelease]];
        
        if(![[songData objectForKey:@"artist"] isEqualToString:@""])
        {
            [unEscapedTitle insertString:@" - " atIndex:0];
            NSString* unEscapedArtist = [(NSString*) 		CFURLCreateStringByReplacingPercentEscapes(NULL, (CFStringRef)[songData 			objectForKey:@"artist"], (CFStringRef)@"") autorelease];

            [unEscapedTitle insertString:unEscapedArtist atIndex:0];
        }
        [lastSongSubmitted setStringValue:unEscapedTitle];
        [songDataTable reloadData];
        
    }

    if(![[myKeyChain genericPasswordForService:@"iScrobbler"
                                       account:[prefs stringForKey:@"username"]] 			isEqualToString:@""])
    {
        [passwordStored setStringValue:PASS_STORED];
    } else {
        [passwordStored setStringValue:PASS_NOT_STORED];
    }
    
    [password setStringValue:@""];
    //NSLog(@"Fields updated");
}

- (IBAction)forgetPassword:(id)sender
{
    [myKeyChain removeGenericPasswordForService:@"iScrobbler"
                                        account:[prefs stringForKey:@"username"]];
    [self updateFields];
}

- (IBAction)apply:(id)sender
{
    [self savePrefs];
    [self updateFields];
}

- (IBAction)cancel:(id)sender
{
    [self updateFields];
    [[self window] performClose:nil];
}

- (IBAction)OK:(id)sender
{
    [self savePrefs];
    [self updateFields];
    [[self window] performClose:nil];
}

-(IBAction)submitWebBugReport:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"http://www.flexistentialist.org/contact.shtml"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

-(IBAction)submitEmailBugReport:(id)sender
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:songData];
    [dict removeObjectForKey:@"password"];

    NSString* mailtoLink = [NSString stringWithFormat:@"mailto:sam@flexistentialist.org?subject=iScrobbler Bug Report&body=--Please explain the circumstances of the bug here--\nThanks for contributing!\n\nResult Data Dump:\n\n%@\n\n%@",lastResult,dict];
    
    NSURL *url = [NSURL URLWithString:[(NSString*)
        CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)mailtoLink, NULL, NULL, 	kCFStringEncodingUTF8) autorelease]];

    [[NSWorkspace sharedWorkspace] openURL:url];

}


- (void)windowWillClose:(NSNotification *)aNotification
{
    [self savePrefs];
    [self updateFields];
}

-(void)setLastResult: (NSString *)newLastResult
{
    [newLastResult retain];
    [lastResult release];
    lastResult = newLastResult;
}

-(NSString *)lastResult;
{
    return lastResult;
}
-(void)setLastResultShort: (NSString *)newLastResultShort
{
    [newLastResultShort retain];
    [lastResultShort release];
    lastResultShort = newLastResultShort;
}

-(NSString *)lastResultShort;
{
    return lastResultShort;
}

-(void)setLastResultLong: (NSString *)newLastResultLong
{
    [newLastResultLong retain];
    [lastResultLong release];
    lastResultLong = newLastResultLong;
}

-(NSString *)lastResultLong;
{
    return lastResultLong;
}


-(IBAction)queryiTunes:(id)sender {}
-(IBAction)queryAudion:(id)sender {}

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

-(IBAction)downloadUpdate:(id)sender
{
    NSURL *url = [NSURL URLWithString:[self downloadURL]];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

//-(IBAction)copy:(id)sender
//{
//    NSPasteboard *pb = [NSPasteboard generalPasteboard];
//    NSArray *pb_types = [NSArray arrayWithObjects:NSStringPboardType,NULL];
//    [pb declareTypes:pb_types owner:NULL];
//[pb setData:[self selectedItemsAsData] forType:NSStringPboardType];
//}

-(NSString *)downloadURL
{
    return downloadURL;
}

-(void)setDownloadURL:(NSString *)newDownloadURL 
{
    [newDownloadURL retain];
    [downloadURL release];
    downloadURL = newDownloadURL;
}

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
    return 5;
}

- (id)tableView:(NSTableView *)tableView
     objectValueForTableColumn:(NSTableColumn *)tableColumn
                           row:(int)row
{
    NSMutableArray * array = [NSMutableArray array];
    NSMutableDictionary * attribs = [NSMutableDictionary dictionary];
    [attribs setObject:[NSFont fontWithName:@"Helvetica" size:12]
                forKey:NSFontAttributeName];
    NSAttributedString * attribString = [NSAttributedString alloc];
    
    [array insertObject:@"Time"
                atIndex:0];
    [array insertObject:@"Filename"
                atIndex:0];
    [array insertObject:@"Duration"
                atIndex:0];
    [array insertObject:@"Title"
                atIndex:0];
    [array insertObject:@"Artist"
                atIndex:0];
    
    
    NSString * identifier = [[[NSString alloc] initWithString:[tableColumn identifier]] 	autorelease];
    

    if([identifier isEqualToString:@"property"]) {
        attribString = [attribString initWithString:[array 			objectAtIndex:row] attributes:attribs];
        //[tableColumn setWidth:[attribString size]];
        return [attribString autorelease];
    } else {
        [tableColumn setWidth:([[[self songData] objectForKey:@"filename"] 	sizeWithAttributes:attribs].width + 5)];
        
        attribString = [attribString initWithString:[(NSString*) 	CFURLCreateStringByReplacingPercentEscapes(NULL, (CFStringRef)[[self songData] 	objectForKey:[[array objectAtIndex:row] lowercaseString]], (CFStringRef)@"") 	autorelease] attributes:attribs];
        //[tableColumn setWidth:NSMakeSize([attribString size].width];
        return [attribString autorelease];
    }
}

- (void)dealloc
{
    [nc removeObserver:self];
    [nc release];
    [downloadURL release];
    [prefs release];
    [lastResult release];
    [songData release];
    [myKeyChain release];
    [lastResultLong release];
    [lastResultShort release];
    [super dealloc];
}

@end
