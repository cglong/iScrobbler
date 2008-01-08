//
//  iPodController.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/8/08.
//  Copyright 2004-2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

ISEXPORT_CLASS
@interface iPodController : NSObject {
    NSString *iPodMountPath;
    NSMutableDictionary *iPodMounts;
    NSImage *iPodIcon;
    int iPodMountCount;
    NSArray *iTunesPlaylists;
}

+ (iPodController*)sharedInstance;

- (IBAction)synciPod:(id)sender;

- (BOOL)isiPodMounted;

@end

#define IPOD_SYNC_BEGIN @"org.bergstrand.iscrobbler.ipod.sync.begin"
#define IPOD_SYNC_END @"org.bergstrand.iscrobbler.ipod.sync.end"
#define IPOD_SYNC_KEY_PATH @"Path"
#define IPOD_SYNC_KEY_ICON @"Icon"
#define IPOD_ICON_NAME @"iPod Icon"
#define IPOD_SYNC_KEY_TRACK_COUNT @"Track Count"
#define IPOD_SYNC_KEY_SCRIPT_MSG @"Script Msg"
