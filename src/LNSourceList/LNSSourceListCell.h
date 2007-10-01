//
//  LNSSourceListCell.h
//  SourceList
//
//  Created by Mark Alldritt on 07/09/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface LNSSourceListCell : NSTextFieldCell {
	NSDictionary*	mValue;
}

- (NSDictionary*) objectValue;
- (void) setObjectValue:(NSDictionary*) value;

@end
