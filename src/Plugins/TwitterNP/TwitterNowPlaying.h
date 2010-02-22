//
//  TwitterNowPlaying.h
//  iScrobbler Plugin
//
//  Copyright 2010 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import <Cocoa/Cocoa.h>
#import "ISPlugin.h"

@class SongData;
@class SimpleTwitter;

ISEXPORT_CLASS
@interface ISTwitterNowPlaying : NSObject <ISPlugin> {
    id mProxy;
    SongData *npSong;
    SimpleTwitter *twitter;
}

@end
