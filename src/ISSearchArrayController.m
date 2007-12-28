//
//  ISSearchArrayController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/27/2005.
//  Copyright 2005-2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import "ISSearchArrayController.h"
#import "TopListsController.h"

@interface NSTableView (ISPasteboardCopyAddition)
- (void)copy:(id)sender;
// Aren't really supposed to use Categories to override methods, but screw it.
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal;
@end

@interface NSIndexSet (ISArrayAdditions)
- (NSArray*)arrayOfIndexes;
@end

@implementation ISSearchArrayController

- (void)awakeFromNib
{
    // register for drag and drop
    [tableView registerForDraggedTypes:[NSArray arrayWithObjects:NSTabularTextPboardType, NSStringPboardType, nil]];
}

- (IBAction)search:(id)sender
{
    [self setSearchString:[sender stringValue]];
    [super rearrangeObjects];
}

- (NSArray *)arrangeObjects:(NSArray *)objects
{
    if (!searchString || 0 == [searchString length]) {
        return ([super arrangeObjects:objects]);
    }
    
    NSMutableArray *matches = [NSMutableArray arrayWithCapacity:[objects count]];
    // case-insensitive search
    NSString *lowerSearch = [searchString lowercaseString];
    NSMutableString *keyString = [NSMutableString string];
    NSEnumerator *en = [objects objectEnumerator];
    id obj;
    Class nsstringClass = NSClassFromString(@"NSString");
    while ((obj = [en nextObject])) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSEnumerator *keyenum = [obj keyEnumerator];
        id value, key;
        while ((key = [keyenum nextObject])) {
            value = [obj objectForKey:key];
            /* ACK! Internal knowledge of dict. */
            if ([value isKindOfClass:nsstringClass] && ![key isEqualToString:@"Play Time"]) {
                [keyString appendString:[value lowercaseString]];
            }
        }
        if (NSNotFound != [keyString rangeOfString:lowerSearch].location)
            [matches addObject:obj];
        
        [pool release];
        [keyString setString:@""];
    }
    
    return ([super arrangeObjects:matches]);
}

- (NSString *)searchString
{
    return (searchString);
}

- (void)setSearchString:(NSString *)string
{
    if (string != searchString) {
        [string retain];
        [searchString release];
        searchString = string;
    }
}

- (BOOL)isSearchInProgress
{
    return (searchString && [searchString length]);
}

// required delegate methods (even with bindings)
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (0);
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    return (nil);
}

// drag & drop support
- (BOOL)tableView:(NSTableView *)table writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard*)pboard
{
    [pboard declareTypes:[NSArray arrayWithObjects:NSTabularTextPboardType, NSStringPboardType, nil] owner:self];
    NSArray *objects = [self arrangedObjects], *dataKeys = nil;
    NSDictionary *data;
    id key, value;
    NSUInteger row, i, count;
    // Copy the dict data into text
    NSMutableString *textData = [NSMutableString string];
    
    row = [rows firstIndex];
    if (NSNotFound != row) {
        data = [objects objectAtIndex:row];
        // Note: We only get the keys from one object, so that our tabulated colmns contain the correct data
        dataKeys = [[data allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        // Add keys into text
        count = [dataKeys count];
        for (i = 0; i < count; ++i) {
            key = [dataKeys objectAtIndex:i];
            if (![key isEqualToString:@"Play Time"] && ![key isEqualToString:@"objectID"]) /* ACK! Internal knowledge of dict. */
                [textData appendFormat:@"%@\t", key];
        }
        // Replace the last tab with a newline
        [textData replaceCharactersInRange:NSMakeRange([textData length]-1, 1) withString:@"\n"];
    } else
        return (NO);
    
    for (; NSNotFound != row; row = [rows indexGreaterThanIndex:row]) {
        data = [objects objectAtIndex:row];
        // Add values into text
        count = [dataKeys count];
        for (i = 0; i < count; ++i) {
            key = [dataKeys objectAtIndex:i];
            if (![key isEqualToString:@"Play Time"] && ![key isEqualToString:@"objectID"]) { /* ACK! Internal knowledge of dict. */ 
                value = [data objectForKey:[dataKeys objectAtIndex:i]];
                [textData appendFormat:@"%@\t", [value description]];
            }
        }
        // Replace the last tab with a newline
        [textData replaceCharactersInRange:NSMakeRange([textData length]-1, 1) withString:@"\n"];
    }
    
    // Just in case the receiver does not accept TabText type
    (void)[pboard setString:textData forType:NSStringPboardType];
    (void)[pboard setString:textData forType:NSTabularTextPboardType];
    
    return (YES);
}

- (BOOL)tableView:(NSTableView*)table acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)op
{
    return (NO);
}

- (NSString *)tableView:(NSTableView *)tv toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tc row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
    // forward it
    return ([[TopListsController sharedInstance] tableView:tv toolTipForCell:cell rect:rect tableColumn:tc row:row mouseLocation:mouseLocation]);
}

@end

@implementation NSTableView (ISPasteboardCopyAddition)

- (void)copy:(id)sender
{
    NSArray *idxs = [[self selectedRowIndexes] arrayOfIndexes];
    (void)[[self delegate] tableView:self writeRows:idxs toPasteboard:[NSPasteboard generalPasteboard]];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    if (isLocal)
        return (NSDragOperationNone);
    
    return (NSDragOperationCopy);
}

@end

@implementation NSIndexSet (ISArrayAdditions)

- (NSArray*)arrayOfIndexes
{
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[self count]];

    NSUInteger idx = [self firstIndex];
    for (; NSNotFound != idx; idx = [self indexGreaterThanIndex:idx])
        [array addObject:[NSNumber numberWithUnsignedLongLong:idx]];

    return (array);
}

@end
