//
//  ProtocolManager_v12.h
//  iScrobbler
//
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ProtocolManager.h"
#import "ProtocolManager+Subclassers.h"

@interface ProtocolManager_v12 : ProtocolManager {

}

- (NSData*)nowPlayingDataForSong:(SongData*)song;

@end
