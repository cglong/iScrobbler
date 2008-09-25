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

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
#import "LoginItemsAE/LoginItemsAE.c"
#endif

@interface NSWorkspace (ISAdditions)
- (BOOL)addLoginItem:(NSString*)path hidden:(BOOL)hide;
- (BOOL)isLoginItem:(NSString*)path;
@end

@implementation NSWorkspace (ISAdditions)

- (BOOL)addLoginItem:(NSString*)path hidden:(BOOL)hide
{
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    BOOL added = NO;
    LSSharedFileListRef list = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, NULL);
    if (list) {
        NSDictionary *props = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:hide]
            forKey:(NSString*)kLSSharedFileListItemHidden];
        LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(list, kLSSharedFileListItemLast, NULL, NULL,
            (CFURLRef)[NSURL fileURLWithPath:path], (CFDictionaryRef)props, NULL);
        if (item) {
            added = YES;
            CFRelease(item);
        }
        CFRelease(list);
    }
    return (added);
#else
    OSStatus err;
    return (0 == (err = LIAEAddURLAtEnd((CFURLRef)[NSURL fileURLWithPath:path], hide)));
#endif //  MAC_OS_X_VERSION_10_5
}

- (BOOL)isLoginItem:(NSString*)path
{
     BOOL exists = NO;
     OSStatus err;
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    LSSharedFileListRef list = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, NULL);
    if (list) {
        UInt32 seed;
        CFArrayRef items = LSSharedFileListCopySnapshot(list, &seed);
        if (items) {
            LSSharedFileListItemRef item;
            CFIndex count = CFArrayGetCount(items);
            NSURL *url;
            NSString *itemPath, *myLeaf = [path lastPathComponent];
            for (CFIndex i = 0; i < count; ++i) {
                item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
                if (0 == (err = LSSharedFileListItemResolve(item, kLSSharedFileListNoUserInteraction|kLSSharedFileListDoNotMountVolumes,
                    (CFURLRef*)&url, NULL))) {
                    itemPath = [url path];
                    [url autorelease];
                    if ([itemPath isEqualToString:path]) {
                        exists = YES;
                        break;
                    } else if ([[itemPath lastPathComponent] isEqualToString:myLeaf]) {
                        // probably moved to a different volume
                        CFBooleanRef hidden = LSSharedFileListItemCopyProperty(item, kLSSharedFileListItemHidden);
                        err = LSSharedFileListItemRemove(list, item);
                        exists = [self addLoginItem:path hidden:hidden ? CFBooleanGetValue(hidden) : NO];
                        if (hidden)
                            CFRelease(hidden);
                        break;
                    }
                }
            }
            CFRelease(items);
        }
        CFRelease(list);
    }
    return (exists);
#else
    NSArray *items = nil;
    if (0 != (err = LIAECopyLoginItems((CFArrayRef*)&items)) || !items)
        return (YES); // if we fail, don't tell the caller to attempt an add
    
    [items autorelease];
    
    id	obj;
    NSString *myLeaf, *leaf, *item;
    NSEnumerator *itemEnumerator = [items objectEnumerator];
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
                err = LIAERemove([items indexOfObject:obj]);
                err = LIAEAddURLAtEnd((CFURLRef)[NSURL fileURLWithPath:path], [[obj objectForKey:(NSString*)kLIAEHidden] boolValue]);
                break;
            }
        }
    }
    
    return (exists);
#endif // MAC_OS_X_VERSION_10_5
}

@end
