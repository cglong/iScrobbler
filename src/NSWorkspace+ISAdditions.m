/*
    Copyright 2005-2008 Brian Bergstrand

    This program is free software; you can redistribute it and/or modify it under the terms of the
    GNU General Public License as published by the Free Software Foundation;
    either version 2 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
    without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program;
    if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
*/

@interface NSWorkspace (BBLoginAdditions)
- (BOOL)addLoginItem:(NSString*)path hidden:(BOOL)hide;
- (BOOL)isLoginItem:(NSString*)path;
@end

@implementation NSWorkspace (BBLoginAdditions)

- (BOOL)addLoginItem:(NSString*)path hidden:(BOOL)hide
{
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
}

- (BOOL)isLoginItem:(NSString*)path remove:(BOOL)rem
{
    BOOL exists = NO;
    OSStatus err;
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
                        if (!rem)
                            exists = YES;
                        else {
                            err = LSSharedFileListItemRemove(list, item);
                        }
                        break;
                    } else if ([[itemPath lastPathComponent] isEqualToString:myLeaf]) {
                        // probably moved to a different volume
                        CFBooleanRef hidden = LSSharedFileListItemCopyProperty(item, kLSSharedFileListItemHidden);
                        err = LSSharedFileListItemRemove(list, item);
                        if (!rem) {
                            exists = [self addLoginItem:path hidden:hidden ? CFBooleanGetValue(hidden) : NO];
                            if (hidden)
                                CFRelease(hidden);
                        }
                        break;
                    }
                }
            }
            CFRelease(items);
        }
        CFRelease(list);
    }
    return (exists);
}

- (BOOL)isLoginItem:(NSString*)path
{
    return ([self isLoginItem:path remove:NO]);
}

- (void)removeLoginItem:(NSString*)path
{
    (void)[self isLoginItem:path remove:YES];
}

@end
