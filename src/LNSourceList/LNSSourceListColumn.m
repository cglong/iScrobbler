//
//  LNSSourceListColumn.m
//  SourceList
//
//  Created by Mark Alldritt on 07/09/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "LNSSourceListColumn.h"
#import "LNSSourceListCell.h"
#import "LNSSourceListSourceGroupCell.h"

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
@interface NSObject (LN_NSArrayControllerTreeNodePrivateMethod)
// observedObject is a method of the private _NSArrayControllerTreeNode class
// this has been made public in 10.5 with the [NSTreeNode representedObject] class
- (id)observedObject;
@end
#endif

@implementation LNSSourceListColumn

- (void) awakeFromNib
{
	LNSSourceListCell* dataCell = [[[LNSSourceListCell alloc] init] autorelease];

	[dataCell setFont:[[self dataCell] font]];
	[dataCell setLineBreakMode:[[self dataCell] lineBreakMode]];

	[self setDataCell:dataCell];
}

- (id) dataCellForRow:(int) row
{
	if (row >= 0)
	{
        id node = [(NSOutlineView*) [self tableView] itemAtRow:row];
		NSDictionary* value;
        #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
        if (NO == [node respondsToSelector:@selector(representedObject)])
            value = [node observedObject];
        else
        #endif
            value = [node representedObject];

		if ([[value objectForKey:@"isSourceGroup"] boolValue])
		{
			LNSSourceListSourceGroupCell* groupCell = [[[LNSSourceListSourceGroupCell alloc] init] autorelease];
			
			[groupCell setFont:[[self dataCell] font]];
			[groupCell setLineBreakMode:[[self dataCell] lineBreakMode]];
			return groupCell;			
		}
	}

	return [self dataCell];
}

@end
