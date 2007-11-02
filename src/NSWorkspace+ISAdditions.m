/*
    Copyright 2005-2007 Brian Bergstrand

    This program is free software; you can redistribute it and/or modify it under the terms of the
    GNU General Public License as published by the Free Software Foundation;
    either version 2 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
    without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program;
    if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
*/

#import "LoginItemsAE.h"

@interface NSWorkspace (ISAdditions)
- (BOOL)addLoginItem:(NSString*)path hidden:(BOOL)hide;
- (BOOL)isLoginItem:(NSString*)path;
@end

@implementation NSWorkspace (ISAdditions)

#define STRING_ERROR_ADD_LOGIN_ITEM @"ErrorAddLoginItem"

- (BOOL)addLoginItem:(NSString*)path hidden:(BOOL)hide
{
    OSStatus err;
    return (0 == (err = LIAEAddURLAtEnd((CFURLRef)[NSURL fileURLWithPath:path], hide)));
}

- (BOOL)isLoginItem:(NSString*)path
{
    NSArray *items = nil;
    OSStatus err;
    if (0 != (err = LIAECopyLoginItems((CFArrayRef*)&items)) || !items)
        return (YES); // if we fail, don't tell the caller to attempt an add
    
    [items autorelease];
    
    id	obj;
    NSString *myLeaf, *leaf, *item;
    NSEnumerator *itemEnumerator = [items objectEnumerator];
    BOOL exists = NO;

    myLeaf = [path lastPathComponent];
    while ((obj = [itemEnumerator nextObject])) {
        item = [[obj objectForKey:(NSString*)kLIAEURL] path];
        if ([item isEqualTo:path]) {
            exists = YES;
            break;
        } else {
            // Check and see if the leaf name is the same as our path.
            // If it is, than the user most likely moved the location of the app
            // during an upgrade, so fix the entry.
            leaf = [item lastPathComponent];
            if ([leaf isEqualTo:myLeaf]) {
                exists = YES;
                // Remove the old one and add the new one
                OSStatus err;
                err = LIAERemove([items indexOfObject:obj]);
                err = LIAEAddURLAtEnd((CFURLRef)[NSURL fileURLWithPath:path], [[obj objectForKey:(NSString*)kLIAEHidden] boolValue]);
                break;
            }
        }
    }
    
    return (exists);
}

@end
