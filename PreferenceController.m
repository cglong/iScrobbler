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
#import "NSString_iScrobblerAdditions.h"
#import "SongData.h"
#import "iScrobblerController.h"

@interface PreferenceController (PrivateMethods)
- (void)savePrefs;
@end

@implementation PreferenceController

- (void)awakeFromNib {
	[[NSUserDefaultsController sharedUserDefaultsController] setAppliesImmediately:NO];
}

- (NSWindow *)preferencesWindow {
	if (!_preferencesWindow) {
		if (![NSBundle loadNibNamed:@"Preferences" owner:self] || !_preferencesWindow) {
			NSLog(@"Failed to load nib \"Preferences.nib\"");
			[NSApp showApplicationIsDamagedDialog];
		}
	}
	return _preferencesWindow;
}

- (void)showPreferencesWindow {
	// makes the window always visable
	[[self preferencesWindow] setLevel:NSModalPanelWindowLevel];
	// we could consider tying this window to iTunes, only make it visable when iTunes is frontmost...
	
	// lookup the password field
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
	NSString *password = [[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler" account:username];
	if (!password) password = @""; // the text field doesn't like nil.
	[_passwordField setStringValue:password];
	
	// show the window
    [[self preferencesWindow] makeKeyAndOrderFront:self];
}

// ECS: This code might eventually go in a value transformer
// so we'll keep it around in comment form for a while -- 10/27/04

//- (void)generateResultText
//{
//	//NSLog(@"lastHandshakeResult: %@", [self lastHandshakeResult]);
//	
//	if([self lastHandshakeResult] == nil) {
//		//NSLog(@"No connection yet");
//        [self setLastResult:@"No connection yet."];
//        [self setLastResultLong:NO_CONNECTION_LONG];
//        [self setLastResultShort:NO_CONNECTION_SHORT];
//    }  else if([[self lastHandshakeResult] hasPrefix:@"UPTODATE"]) {
//		//NSLog(@"iScrobbler is Up To Date");
//    }  else if([[self lastHandshakeResult] hasPrefix:@"UPDATE"]) {
//		//NSLog(@"iScrobbler version is out of date");
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
//		//NSLog(@"Handshaking Failed");
//        [self setLastResultShort:FAILURE_SHORT];
//        [self setLastResultLong:FAILURE_LONG];
//    } else if([[self lastHandshakeResult] hasPrefix:@"BADUSER"]) {
//		//NSLog(@"Bad User!  Bad!");
//        [self setLastResultShort:AUTH_SHORT];
//        [self setLastResultLong:AUTH_LONG];
//    }
//	
//    //NSLog(@"lastResult: %@", [self lastResult]);
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
	[[NSUserDefaultsController sharedUserDefaultsController] save:self];
	
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
	if(![[_passwordField stringValue] isEqualToString:@""])
	{
		[[KeyChain defaultKeyChain] setGenericPassword:[_passwordField stringValue]
											forService:@"iScrobbler"
											   account:username];
		 NSLog(@"password stored as: %@",[[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler" account:username]);
	} else {
		[[KeyChain defaultKeyChain] removeGenericPasswordForService:@"iScrobbler" account:username];
	}
}

- (IBAction)cancel:(id)sender
{
	[[NSUserDefaultsController sharedUserDefaultsController] revert:self];
	[_preferencesWindow performClose:sender];
}

- (IBAction)OK:(id)sender
{
	[self savePrefs];
	[_preferencesWindow performClose:sender];
}

- (IBAction)submitWebBugReport:(id)sender
{
	NSURL *url = [NSURL URLWithString:@"http://sourceforge.net/tracker/?group_id=76514&atid=547327"];
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
	
#pragma mark -

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	return 4;
}
	
	
	// FIXME: This is a pretty ugly method -- ECS
//	- (id)tableView:(NSTableView *)tableView
//objectValueForTableColumn:(NSTableColumn *)tableColumn
//row:(int)row
//	{
//		NSArray *propertyArray = [NSArray arrayWithObjects:@"Album", @"Artist", @"Title", @"Duration", @"Path", nil];
//		NSArray *valueArray = nil;
//		NSMutableDictionary *attribs = [NSDictionary dictionaryWithObject:[NSFont fontWithName:@"Helvetica" size:12] forKey:NSFontAttributeName];
//		
//		if(songData != nil) {
//			valueArray = [NSArray arrayWithObjects:
//				[[self songData] album],
//				[[self songData] artist],
//				[[self songData] title],
//				[[[self songData] duration] stringValue],
//				[[self songData] path], nil];
//		}
//		
//		NSString *identifier = [tableColumn identifier];
//		
//		NSAttributedString *attribString = nil;
//		if([identifier isEqualToString:@"property"]) {
//			attribString = [[[NSAttributedString alloc] initWithString:[propertyArray objectAtIndex:row] attributes:attribs] autorelease];
//			[tableColumn setWidth:([[propertyArray objectAtIndex:2] sizeWithAttributes:attribs].width
//								   +5)];
//			return attribString;
//		} else {
//			if(songData != nil) {
//				[tableColumn setWidth:([[[self songData] path] sizeWithAttributes:attribs].width + 5)];
//				
//				attribString = [[[NSAttributedString alloc] initWithString:
//					[[valueArray objectAtIndex:row] stringByAddingPercentEscapes]
//																attributes:attribs] autorelease];
//				//[tableColumn setWidth:NSMakeSize([attribString size].width];
//				return attribString;
//		} else {
//			return nil;
//		}
//	}
//	}
	
@end
