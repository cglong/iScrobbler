//
//  PersistenceImport.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 10/3/2007.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

@interface PersistentProfileImport : NSObject {
    PersistentProfile *profile;
    NSString *currentArtist, *currentAlbum;
    NSManagedObjectContext *moc;
    NSManagedObject *moArtist, *moAlbum, *moSession, *mosArtist, *mosAlbum, *moPlayer;
}

- (void)importiTunesDB:(id)obj;
- (void)syncWithiTunes;
@end