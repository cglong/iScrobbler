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
#import "SongData.h"
#import "iScrobblerController.h"
#import "ScrobLog.h"

@interface PreferenceController (PrivateMethods)
- (void)savePrefs;
@end

@implementation PreferenceController

- (void)awakeFromNib {
	[[NSUserDefaultsController sharedUserDefaultsController] setAppliesImmediately:NO];
}

- (NSWindow *)preferencesWindow {
	if (!preferencesWindow) {
		if (![NSBundle loadNibNamed:@"Preferences" owner:self] || !preferencesWindow) {
			ScrobLog(SCROB_LOG_CRIT, @"Failed to load nib \"Preferences.nib\"");
			[[NSApp delegate] showApplicationIsDamagedDialog];
		}
	}
	return preferencesWindow;
}

- (void)showPreferencesWindow {
	// makes the window always visable
	[[self preferencesWindow] setLevel:NSModalPanelWindowLevel];
	// we could consider tying this window to iTunes, only make it visable when iTunes is frontmost...
	
	// lookup the password field
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
	NSString *password = [[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler" account:username];
	if (!password) password = @""; // the text field doesn't like nil.
	[passwordField setStringValue:password];
	
	// show the window
    [[self preferencesWindow] makeKeyAndOrderFront:self];
}

// ECS: This code might eventually go in a value transformer
// so we'll keep it around in comment form for a while -- 10/27/04

//- (void)generateResultText
//{
//	//ScrobTrace(@"lastHandshakeResult: %@", [self lastHandshakeResult]);
//	
//	if([self lastHandshakeResult] == nil) {
//		//ScrobTrace(@"No connection yet");
//        [self setLastResult:@"No connection yet."];
//        [self setLastResultLong:NO_CONNECTION_LONG];
//        [self setLastResultShort:NO_CONNECTION_SHORT];
//    }  else if([[self lastHandshakeResult] hasPrefix:@"UPTODATE"]) {
//		//ScrobTrace(@"iScrobbler is Up To Date");
//    }  else if([[self lastHandshakeResult] hasPrefix:@"UPDATE"]) {
//		//ScrobTrace(@"iScrobbler version is out of date");
//        NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
//		
//        NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
//        [style setAlignment:NSCenterTextAlignment];
//        [attribs setObject:[NSColor colorWithCalibratedRed:1.0
//                                                     green:0.0
//                                                      blue:0.0
//                                                     alpha:1.0]
//                    forKey:NSForegroundColorAttributeName];
//        [attribs setObject:style forKey:NSParagraphStyleAttributeName];
//		
//        [self setLastResultShort:SUBMISSION_SUCCESS_OUTOFDATE_SHORT];
//        [self setLastResultLong:SUBMISSION_SUCCESS_OUTOFDATE_LONG];
//		
//    } else if([[self lastHandshakeResult] hasPrefix:@"FAILED"]) {
//		//ScrobTrace(@"Handshaking Failed");
//        [self setLastResultShort:FAILURE_SHORT];
//        [self setLastResultLong:FAILURE_LONG];
//    } else if([[self lastHandshakeResult] hasPrefix:@"BADUSER"]) {
//		//ScrobTrace(@"Bad User!  Bad!");
//        [self setLastResultShort:AUTH_SHORT];
//        [self setLastResultLong:AUTH_LONG];
//    }
//	
//    //ScrobTrace(@"lastResult: %@", [self lastResult]);
//	//Check to see if the script returns OK
//    if([[self lastResult] hasPrefix:@"OK"]) {
//        [self setLastResultShort:SUBMISSION_SUCCESS_SHORT];
//        [self setLastResultLong:SUBMISSION_SUCCESS_LONG];
//    } else if([[self lastResult] hasPrefix:@"FAILED"]) {
//        [self setLastResultShort:FAILURE_SHORT];
//        [self setLastResultLong:FAILURE_LONG];
//    } else if([[self lastResult] hasPrefix:@"BADAUTH"]) {
//        [self setLastResultShort:AUTH_SHORT];
//        [self setLastResultLong:AUTH_LONG];
//    } else if([[self lastResult] hasPrefix:@"Couldn't resolve"]) {
//        [self setLastResultShort:COULDNT_RESOLVE_SHORT];
//        [self setLastResultLong:COULDNT_RESOLVE_LONG];
//    } else if([[self lastResult] hasPrefix:@"The requested file was not found"]) {
//        [self setLastResultShort:NOT_FOUND_SHORT];
//        [self setLastResultLong:NOT_FOUND_LONG];
//    }
//}    
	
#pragma mark -
	
- (void)savePrefs
{
    NSString *oldUserName = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
    
    [[NSUserDefaultsController sharedUserDefaultsController] save:self];
	
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
    
    if (![oldUserName isEqualToString:username])
        [[KeyChain defaultKeyChain] removeGenericPasswordForService:@"iScrobbler" account:oldUserName];
    
	if(![[passwordField stringValue] isEqualToString:@""])
	{
		[[KeyChain defaultKeyChain] setGenericPassword:[passwordField stringValue]
											forService:@"iScrobbler"
											   account:username];
		 ScrobTrace(@"password stored as: %@",[[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler" account:username]);
	} else {
		[[KeyChain defaultKeyChain] removeGenericPasswordForService:@"iScrobbler" account:username];
	}
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SCROB_PREFS_CHANGED object:self];
}

- (IBAction)cancel:(id)sender
{
	[[NSUserDefaultsController sharedUserDefaultsController] revert:self];
	[preferencesWindow performClose:sender];
}

- (IBAction)OK:(id)sender
{
	[self savePrefs];
	[preferencesWindow performClose:sender];
}

- (IBAction)submitWebBugReport:(id)sender
{
	NSURL *url = [NSURL URLWithString:@"http://www.audioscrobbler.com/forum/"];//@"http://sourceforge.net/tracker/?group_id=76514&atid=547327"];
	[[NSWorkspace sharedWorkspace] openURL:url];
}
	
//	- (IBAction)submitEmailBugReport:(id)sender
//	{
//		NSString *to = @"audioscrobbler-development@lists.sourceforge.net";
//		NSString *subject = @"iScrobbler Bug Report";
//		NSString *body = [NSString stringWithFormat:@"Please fill in the problem you're seeing below.  Before submitting, you might like to check http://www.audioscrobbler.com/ to see the status of the Audioscrobbler service.  Thanks for contributing!\n\n--Please explain the circumstances of the bug here--\n\n\n\nLast Server Result: %@\n", lastResult];
//		
//		NSString *mailtoLink = [NSString stringWithFormat:@"mailto:?subject=%@&body=%@", to, subject, body];
//		
//		NSURL *url = [NSURL URLWithString:[mailtoLink stringByAddingPercentEscapes]];
//		
//		[[NSWorkspace sharedWorkspace] openURL:url];
//	}
	
//- (IBAction)copy:(id)sender
//{
//  NSPasteboard *pb = [NSPasteboard generalPasteboard];
//  NSArray *pb_types = [NSArray arrayWithObjects:NSStringPboardType,NULL];
//  [pb declareTypes:pb_types owner:NULL];
//  [pb setData:[self selectedItemsAsData] forType:NSStringPboardType];
//}
	
@end
