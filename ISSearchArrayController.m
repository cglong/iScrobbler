//
//  ISSearchArrayController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/27/2005.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//
#import "ISSearchArrayController.h"

@implementation ISSearchArrayController

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
            if ([value isKindOfClass:nsstringClass]) {
                [keyString appendString:[value lowercaseString]];
            }
        }
        if (NSNotFound != [keyString rangeOfString:lowerSearch].location)
            [matches addObject:obj];
        
        [pool release];
        [keyString setString:@""];
    }
    
    // Hack! The search field loses focus, presumbably because the table takes it while the contents are refreshed.
    //[[NSApp keyWindow] performSelector:@selector(makeFirstResponder:) withObject:searchField afterDelay:0.02];
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

@end
