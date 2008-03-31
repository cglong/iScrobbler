//
//  PreferenceController.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Re-written in late 2004 by Eric Seidel.
//  Copyright 2004 Eric Seidel.
//  Copyright 2008 Brian Bergstrand
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "PreferenceController.h"
#import "keychain.h"
#import "SongData.h"
#import "iScrobblerController.h"
#import "ScrobLog.h"

@interface PreferenceController (PrivateMethods)
- (BOOL)savePrefs;
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
	
- (BOOL)savePrefs
{
    NSString *oldUserName = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
    
    [[self preferencesWindow] endEditingFor:nil];
    NSUserDefaultsController *udc = (NSUserDefaultsController*)[NSUserDefaultsController sharedUserDefaultsController];
    [udc save:self];
	
    #ifdef bug
    // why doesn't [NSUserDefaultsController save:] apply immediately to the defaults? 
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
    #endif
    NSString *username = [[udc values] valueForKey:@"username"];
    
    if (!username || 0 == [username length]) {
        NSBeginAlertSheet(NSLocalizedString(@"Invalid Username", ""), @"OK", nil, nil, [self preferencesWindow],
            nil, nil, nil, nil, NSLocalizedString(@"The username cannot be empty.", ""));
        return (NO);
    }
    
    if (oldUserName && ![oldUserName isEqualToString:username])
        [[KeyChain defaultKeyChain] removeGenericPasswordForService:@"iScrobbler" account:oldUserName];
    else
        oldUserName = nil;
    
    NSString *newPasswd = [passwordField stringValue];
	if(newPasswd && [newPasswd length] > 0) {
		NSString *curPasswd = [[KeyChain defaultKeyChain] genericPasswordForService:@"iScrobbler" account:username];
        if (![newPasswd isEqualToString:curPasswd]) {
            @try {
                [[KeyChain defaultKeyChain] setGenericPassword:newPasswd forService:@"iScrobbler" account:username];
                [[NSNotificationCenter defaultCenter] postNotificationName:iScrobblerAuthenticationDidChange object:self];
                #if 0
                // A few users have complained that this is a security hole -- even though it's only at TRACE level.
                ScrobTrace(@"password stored as: %@", [[KeyChain defaultKeyChain]
                    genericPasswordForService:@"iScrobbler" account:username]);
                #endif
             } @catch (NSException *exception) {
                NSBeginAlertSheet([exception name], @"OK", nil, nil, [self preferencesWindow],
                    nil, nil, nil, nil, [exception reason]);
                ScrobLog(SCROB_LOG_ERR, @"KeyChain Error: '%@' - %@\n", [exception reason], [exception userInfo]);
                return (NO);
             }
         }
	} else {
		[[KeyChain defaultKeyChain] removeGenericPasswordForService:@"iScrobbler" account:username];
	}
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SCROB_PREFS_CHANGED object:self];
    return (YES);
}

- (IBAction)cancel:(id)sender
{
	[[NSUserDefaultsController sharedUserDefaultsController] revert:self];
	[preferencesWindow performClose:sender];
}

- (IBAction)OK:(id)sender
{
    BOOL good = NO;
	@try {
        good = [self savePrefs];
    } @catch (NSException *e) {
        good = NO;
        ScrobLog(SCROB_LOG_ERR, @"exception saving prefs: %@", e);
    }
    if (good)
        [preferencesWindow performClose:sender];
    else
        NSBeep();
}
	
@end
