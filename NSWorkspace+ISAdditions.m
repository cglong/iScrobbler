/*
    Copyright 2005,2006 Brian Bergstrand

    This program is free software; you can redistribute it and/or modify it under the terms of the
    GNU General Public License as published by the Free Software Foundation;
    either version 2 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
    without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program;
    if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
*/

@interface NSWorkspace (ISAdditions)
- (BOOL)addLoginItem:(NSString*)path hidden:(BOOL)hide;
- (BOOL)isLoginItem:(NSString*)path;
@end

@implementation NSWorkspace (ISAdditions)

// Note: The next two methods contain internal knowledge of the loginwindow preferences file.
// This is usually a bad thing, but Apple's own LoginItems API is just a C source file that
// does the same as below, only using CoreFoundataion.
//
// 1/2006 : Found out there is now a supported means of doing this through AppleEvents sent
// to the System Events app. Probably should update to that at some point.

#define LOGINWINDOW_DOMAIN @"loginwindow"
#define LOGINITEMS_KEY @"AutoLaunchedApplicationDictionary"
#define HIDE_KEY @"Hide"
#define PATH_KEY @"Path"

#define STRING_ERROR_ADD_LOGIN_ITEM @"ErrorAddLoginItem"

static BOOL g_updateLoginItemsPath = NO;

- (BOOL)addLoginItem:(NSString*)path hidden:(BOOL)hide
{
    NSDictionary *myEntry = nil;
    NSMutableDictionary *loginDict;
    NSMutableArray *entries;
    NSUserDefaults *ud = [[NSUserDefaults alloc] init];
    BOOL added = YES;

    // Make sure we are up to date with what's on disk
    [ud synchronize];
    // Get the loginwindow dict
    loginDict = [[ud persistentDomainForName:LOGINWINDOW_DOMAIN] mutableCopyWithZone:nil];
    if (nil == loginDict)
        loginDict = [[NSMutableDictionary alloc] initWithCapacity:1];
   
    // Get the login items array
    entries = [[loginDict objectForKey:LOGINITEMS_KEY] mutableCopyWithZone:nil];
    if (nil == entries)
        entries = [[NSMutableArray alloc] initWithCapacity:1];

    if (g_updateLoginItemsPath) {
        // Fix the bad entry
        NSString *leaf = [path lastPathComponent];
        NSString *bad;
        int i = 0;

        g_updateLoginItemsPath = NO;
        for (; i < [entries count]; ++i) {
            bad = [[entries objectAtIndex:i] objectForKey:PATH_KEY];
            if ([leaf isEqualTo:[bad lastPathComponent]]) {
                NSMutableDictionary *tmp = [[entries objectAtIndex:i] mutableCopyWithZone:nil]; 
                [tmp setObject:path forKey:PATH_KEY];
                [entries replaceObjectAtIndex:i withObject:tmp];
                [tmp release];
                goto update_prefs;
            }
        }
    }
   
    // Build our entry
    myEntry = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSNumber numberWithBool:hide], HIDE_KEY,
        path, PATH_KEY, nil];
   
    if (loginDict && entries && myEntry) {
        // Add our entry
        [entries insertObject:myEntry atIndex:0];

update_prefs:
        [loginDict setObject:entries forKey:LOGINITEMS_KEY];

        // Update the loginwindow prefs
        [ud removePersistentDomainForName:LOGINWINDOW_DOMAIN];
        [ud setPersistentDomain:loginDict forName:LOGINWINDOW_DOMAIN];
        [ud synchronize];
    } else
        added = NO;
   
    // Release everything
    [myEntry release];
    [entries release];
    [loginDict release];
    [ud release];
    
    return (added);
}

- (BOOL)isLoginItem:(NSString*)path
{
    id	obj;
    NSString *myLeaf, *leaf, *item;
    NSUserDefaults *ud = [[NSUserDefaults alloc] init];
    NSDictionary *loginDict = [ud persistentDomainForName:LOGINWINDOW_DOMAIN];
    NSEnumerator *itemEnumerator = [[loginDict objectForKey:LOGINITEMS_KEY]
        objectEnumerator];
    BOOL exists = NO;

    myLeaf = [path lastPathComponent];

    g_updateLoginItemsPath = NO;
    while ((obj = [itemEnumerator nextObject])) {
        item = [obj objectForKey:PATH_KEY];
        if ([item isEqualTo:path]) {
            exists = YES;
            break;
        } else {
            // Check and see if the leaf name is the same as our path.
            // If it is, than the user most likely moved the location of the app
            // during an upgrade, so fix the entry.
            leaf = [item lastPathComponent];
            if ([leaf isEqualTo:myLeaf]) {
                g_updateLoginItemsPath = YES;
                exists = [self addLoginItem:path hidden:NO];
                g_updateLoginItemsPath = NO;
                break;
            }
        }
    }

    [ud release];
    return (exists);
}

@end
