//
//  TopListsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/18/04.
//  Copyright 2004-2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "iScrobblerController.h"
#import "TopListsController.h"
#import "QueueManager.h"
#import "SongData.h"
#import "ISSearchArrayController.h"
#import "ISProfileDocumentController.h"
#import "ScrobLog.h"
#import "ISArtistDetailsController.h"
#import "ProtocolManager.h"
#import "ASXMLRPC.h"
#import "ASXMLFile.h"
#import "ASWebServices.h"
#import "ISRecommendController.h"
#import "ISTagController.h"
#import "ISLoveBanListController.h"
#import "PlayHistoryController.h"
#import "DBEditController.h"
#import "ISThreadMessenger.h"
#import "ISPluginController.h"
#import "ISBusyView.h"

#import "Persistence.h"
#import "PersistentSessionManager.h"

#define OPEN_HIST_WINDOW_AT_LAUNCH @"History Window Open"

enum {
    kTBItemRequiresSelection      = 0x00000001,
    kTBItemRequiresTrackSelection = 0x00000002,
    kTBItemNoMultipleSelection    = 0x00000004,
    kTBItemDisabledForFeedback    = 0x00000008,
};

static TopListsController *g_topLists = nil;
static NSMutableDictionary *topRatings = nil;
static NSMutableDictionary *artistComparisonData = nil;
static NSMutableArray *topHours = nil;


// This is the ASCII Record Separator char code
#define TOP_ALBUMS_KEY_TOKEN @"\x1e"

@interface NSString (ISHTMLConversion)
- (NSString *)stringByConvertingCharactersToHTMLEntities;
@end

@interface NSMutableDictionary (ISTopListsAdditions)
- (NSComparisonResult)sortByPlayCount:(NSDictionary*)entry;
- (NSComparisonResult)sortByDuration:(NSDictionary*)entry;
@end

@interface NSString (ISTopListsAdditions)
- (NSComparisonResult)caseInsensitiveNumericCompare:(NSString *)string;
@end

@interface TopListsController (PersistenceAdaptor)
- (void)sessionDidChange:(id)arg;
- (void)resetPersistenceManager;
@end

@implementation TopListsController

// session support
- (PersistentProfile*)persistence
{
    return (persistence);
}

- (id)selectedSession
{
    NSArray *a = [sessionController selectedObjects];
    return ([a count] > 0 ? [a objectAtIndex:0] : nil);
}

- (id)currentSession
{
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"LocalChartsSessionName"];
    if (!saved)
        saved = @"lastfm";
    
    id s = [self selectedSession];
    if (s && ![s valueForKey:@"name"])
        return (nil); // separator item
    
    if (!s || [[s valueForKey:@"name"] isNotEqualTo:saved]) {
        if (!s || nil == [s valueForKey:@"archive"]) {
            // Get the default session
            s = [[persistence sessionManager] sessionWithName:saved
                moc:[persistence performSelector:@selector(mainMOC)]];
            if (!s) {
                // somethings wrong, retry with the default of lastfm
                s = [[persistence sessionManager] sessionWithName:@"lastfm"
                    moc:[persistence performSelector:@selector(mainMOC)]];
                if (s)
                    [[NSUserDefaults standardUserDefaults] setObject:[s valueForKey:@"name"] forKey:@"LocalChartsSessionName"];
            }
        } // else
        // it's an archive and since archive's cannot be defaults, it's ok for them not to match the saved session
        if (s) // nil can occur if the object is turned into a fault and we are called (because of KVO) in the middle of the re-fault
            [sessionController setSelectedObjects:[NSArray arrayWithObject:s]];
    }
    return (s);
}

- (void)setCurrentSession:(id)s
{   
    if (s) {
        if (![s valueForKey:@"name"])
            return; // separator item
        
        [sessionController setSelectedObjects:[NSArray arrayWithObject:s]];
        // Don't save archive selections, since they may disappear from the menu
        if (nil == [s valueForKey:@"archive"])
            [[NSUserDefaults standardUserDefaults] setObject:[s valueForKey:@"name"] forKey:@"LocalChartsSessionName"];
        [self performSelector:@selector(sessionDidChange:) withObject:nil afterDelay:0.0];
    }
}

- (NSArray*)allSessions
{
    if (!persistenceTh || ![persistenceTh isKindOfClass:[ISThreadMessenger class]])
        return ([NSMutableArray array]);
    
    PersistentSessionManager *psm = [persistence sessionManager];
    NSManagedObjectContext *moc = [persistence valueForKey:@"mainMOC"];
    
    NSMutableArray *arrangedSessions = [NSMutableArray arrayWithObjects:
        @"lastfm", @"pastday", @"yesterday", @"pastweek", @"monthtodate", @"pastmonth", @"past3months",
        @"pastsixmonths", @"yeartodate", @"pastyear", @"all", nil];
    NSEnumerator *en = [[psm activeSessionsWithMOC:moc] objectEnumerator];
    id s;
    NSUInteger i;
    while ((s = [en nextObject])) {
        if (NSNotFound != (i = [arrangedSessions indexOfObject:[s valueForKey:@"name"]]))
            [arrangedSessions replaceObjectAtIndex:i withObject:s];
    }
    
    // make sure we only return actual session objects
    NSMutableArray *rem = [NSMutableArray array];
    en = [arrangedSessions objectEnumerator];
    while ((s = [en nextObject])) {
        if ([s isKindOfClass:[NSString class]])
            [rem addObject:s];
    }
    [arrangedSessions removeObjectsInArray:rem];
    
    // finally, sort the archived sessions by ascending date and then add them
    NSArray *archivedSessions = [psm archivedSessionsWithMOC:moc weekLimit:10];
    if ([archivedSessions count] > 0) {
        #ifdef notyet
        // this works, but the item is selectable and I'm not sure how to make it not selectable
        // add a separator item
        [arrangedSessions addObject:[NSDictionary dictionaryWithObject:[[NSMenuItem separatorItem] title] forKey:@"localizedName"]];
        #endif
        
        archivedSessions = [archivedSessions sortedArrayUsingDescriptors:
            [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"epoch" ascending:NO] autorelease]]];
        [arrangedSessions addObjectsFromArray:archivedSessions];
    }
    
    return (arrangedSessions);
}

- (void)setAllSessions:(id)val
{
    // just for bindings completeness
}

#define PLAY_TIME_FORMAT @"%u:%02u:%02u:%02u"

- (void)songDidQueuedHandler:(NSNotification*)note
{
    SongData *s = [[note userInfo] objectForKey:QM_NOTIFICATION_USERINFO_KEY_SONG];
    if (![s banned] && ![s skipped])
        [persistence addSongPlay:s];
}

- (void)forceBusyViewOut
{
    if ([busyView window] != nil) {
        NSView *cv = [[self window] contentView];
        [[busyView animator] removeFromSuperview];
        [cv setWantsLayer:NO];
        [cv addSubview:busyProgress];
    }
}

- (void)transitionBusyView
{
    NSView *cv = [[self window] contentView];
    if ([[self valueForKey:@"loading"] boolValue]) {
        if (![busyView window]) {
            [busyProgress removeFromSuperview];
            // We set this here instead of [awakeFromNib:] because NSTableView uses cell transitions when
            // a layer is active and with a large number of rows, this SEVERLY slows down the table display.
            [cv setWantsLayer:YES];
            NSRect r = [cv frame];
            NSInsetRect(r, 20, 20);
            [busyView setFrame:r];
            [[cv animator] addSubview:busyView];
        }
    } else if ([busyView window] != nil) {
        [[busyView animator] removeFromSuperview];
        [cv setWantsLayer:NO];
        [cv addSubview:busyProgress];
    }
}

- (void)persistentProfileDidInitialize:(NSNotification*)note
{
    persistenceTh = (id)[NSNull null]; // just to prevent any race while the thread is initializing
    [NSThread detachNewThreadSelector:@selector(persistenceManagerThread:) toTarget:self withObject:nil];
    
    if ([[self window] isVisible] && [[NSUserDefaults standardUserDefaults] boolForKey:OPEN_HIST_WINDOW_AT_LAUNCH]) {
        [self performSelector:@selector(showTrackHistory:) withObject:nil afterDelay:0.1];
    }
}

- (void)persistentProfileImportProgress:(NSNotification*)note
{
    NSDictionary *d = [note userInfo];
    
    NSNumber *total = [d objectForKey:@"total"];
    // imported will be 0 for the begin note and wil be missing for the end note
    NSNumber *imported = [d objectForKey:@"imported"];
    
    NSString *msg;
    if (!imported) {
        #ifndef busy_overlay_during_load
        [self forceBusyViewOut];
        #endif
        msg = NSLocalizedString(@"Import finished.", "");
        [self willChangeValueForKey:@"loading"];
        [self didChangeValueForKey:@"loading"];
    } else if ([imported unsignedIntValue] > 0)
        msg = [NSString stringWithFormat:NSLocalizedString(@"%@ of %@", "import progress"), imported, total];
    else {
        #ifndef busy_overlay_during_load
        [self transitionBusyView];
        #endif
        msg = NSLocalizedString(@"Reading iTunes library.", "");
        [self willChangeValueForKey:@"loading"];
        [self didChangeValueForKey:@"loading"];
    }
    
    if ([[self window] isVisible] && busyView && [busyView window]) {
        if ([imported unsignedIntValue] > 0)
            [busyView setStringValue:[NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Importing", ""), msg]];
        else
            [busyView setStringValue:msg];
    } else
        [[NSApp delegate] displayWarningWithTitle:NSLocalizedString(@"Local Charts Import Progress", "") message:msg];
}

- (void)persistentProfileDidMigrate:(NSNotification*)note
{
    [[NSApp delegate] displayWarningWithTitle:NSLocalizedString(@"Local Charts Update Successful", "")
        message:NSLocalizedString(@"The Local Charts conversion succeeded.", "")];
}

- (void)persistentProfileWillMigrate:(NSNotification*)note
{
    [[NSApp delegate] displayWarningWithTitle:NSLocalizedString(@"Local Charts Update", "")
        message:NSLocalizedString(@"The Local Charts database format has changed and is now being converted. This may take several minutes.", "")];
}

- (void)persistentProfileMigrateFailed:(NSNotification*)note
{
    NSString *msg = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"The Local Charts conversion failed.", ""),
        /*[[note userInfo] objectForKey:@"NSError"]*/
        NSLocalizedString(@"Please see the log file for further information.", "")];
    [[NSApp delegate] displayWarningWithTitle:NSLocalizedString(@"Local Charts Update Failed", "") message:msg];
    // update our bindings
    [self willChangeValueForKey:@"loading"];
    [self didChangeValueForKey:@"loading"];
}

- (void)persistentProfileDidExport:(NSNotification*)note
{
    NSString *path = [[note userInfo] objectForKey:@"exportPath"];
    if (path && [path isEqualToString:PERSISTENT_STORE_XML]) {
        NSError *error = [NSError errorWithDomain:@"iscrobbler" code:0 userInfo:
        [NSDictionary dictionaryWithObjectsAndKeys:
            NSLocalizedString(@"Relaunch Needed", nil), NSLocalizedFailureReasonErrorKey,
            NSLocalizedString(@"To complete the local charts recreation, a relaunch is required.", nil), NSLocalizedDescriptionKey,
            NSLocalizedString(@"Relaunch", nil), @"defaultButton",
            nil]];
        
        [persistence performSelector:@selector(backupDatabase) withObject:nil];
        [[NSApp delegate] presentError:error modalDelegate:self
            didEndHandler:@selector(relaunchNowDidEnd:returnCode:contextInfo:)];
    }
}

- (void)relaunchApp:(NSNotification*)note
{
    // backup was made in [persistentProfileDidExport:]
    (void)[[NSFileManager defaultManager] removeItemAtPath:PERSISTENT_STORE_DB error:nil];
    
    (void)[NSTask launchedTaskWithLaunchPath:@"/usr/bin/env" arguments:
        [NSArray arrayWithObjects:@"perl", @"-e",
            [NSString stringWithFormat:
                @"use Time::HiRes qw(usleep); do {usleep(200000); $exists = kill(0, %d);} while($exists); system('open \"%@\"')",
                getpid(),
                [[NSBundle mainBundle] bundlePath]],
                nil]];
}

- (void)relaunchNowDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void*)contextInfo
{
    [(id)contextInfo performSelector:@selector(close) withObject:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(relaunchApp:)
        name:NSApplicationWillTerminateNotification object:NSApp];
    
    [NSApp terminate:nil];
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    if ((self = [super initWithWindowNibName:windowNibName])) {
        // load the persistence plugin
        persistence = (PersistentProfile*)[[ISPluginController sharedInstance] loadCorePlugin:@"Persistence"];
        
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"SeenTopListsUpdateAlert"]
            && [[self class] willCreateNewProfile]) {
            [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"New Local Charts", "") message:
                NSLocalizedString(@"The local chart data used in previous versions is incompatible with this version. A new data store will be created.", "")];
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SeenTopListsUpdateAlert"];
        }
        
        // Persistence notes
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileDidInitialize:)
            name:PersistentProfileDidFinishInitialization
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileImportProgress:)
            name:PersistentProfileImportProgress
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileDidMigrate:)
            name:PersistentProfileDidMigrateNotification
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileWillMigrate:)
            name:PersistentProfileWillMigrateNotification
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileMigrateFailed:)
            name:PersistentProfileMigrateFailedNotification
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileDidExport:)
            name:PersistentProfileDidExportNotification
            object:nil];
        
        NSError *error;
        if (NO == [persistence initDatabase:&error]) {
            persistence = nil; // XXX: the plugin is still valid, we just lose our ref to it
            [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Failed to Open Local Charts Database", "")
                message:[error localizedDescription]];
        }
        
        if ([persistence importInProgress]) {
            [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"iTunes Import", "") message:
                NSLocalizedString(@"Your iTunes library is now being imported into the new local charts. This can take several hours of intense CPU time and should not be interrupted.", "")];
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(songDidQueuedHandler:)
            name:QM_NOTIFICATION_SONG_QUEUED
            object:nil];
    }
    return (self);
}

// details, table selection and IB actions
- (NSArrayController*)currentDataController
{
    NSString *viewID = [[tabView selectedTabViewItem] identifier];
    if ([viewID isEqualToString:@"Tracks"])
        return (topTracksController);
    else if ([viewID isEqualToString:@"Artists"])
        return (topArtistsController);
    else if ([viewID isEqualToString:@"Albums"])
        return (topAlbumsController);
    
    return (nil);
}

- (void)selectionDidChange:(NSNotification*)note
{
    @try {
    NSString *artist = [(id)[[note object] dataSource] valueForKeyPath:@"selection.Artist"];
    [artistDetails setArtist:artist];
    
    NSArray *selection = [topTracksController selectedObjects];
    if ([selection count] > 0 && [[[tabView selectedTabViewItem] identifier] isEqualToString:@"Tracks"])
        [[PlayHistoryController sharedController] loadHistoryForTrack:[selection objectAtIndex:0]];
    } @catch (id e) {}
}

- (NSString *)tableView:(NSTableView *)tv toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tc row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
    if ([[[tabView selectedTabViewItem] identifier] isEqualToString:@"Tracks"]) {
        NSArray *contents = [topTracksController arrangedObjects];
        if (row >= 0 && row < [contents count])
            [[PlayHistoryController sharedController] loadHistoryForTrack:[contents objectAtIndex:row]];
    }
    return (nil);
}

- (IBAction)hideDetails:(id)sender
{
#ifdef obsolete
    [topArtistsTable deselectAll:nil];
    [topTracksTable deselectAll:nil];
#endif
    [artistDetails closeDetails:nil];
}

- (IBAction)showArtistDetails:(id)sender
{
    [artistDetails performSelector:@selector(showWindow:) withObject:sender];
    
    NSArrayController *data = [self currentDataController];
    NSArray *selection;
    if (NO == ((selection = [topTracksController selectedObjects]) && [selection count] > 0)) {
        if ([[data arrangedObjects] count] > 0)
            [data setSelectionIndex:0];
        else
            return;
    }
    
    [artistDetails setArtist:[data valueForKeyPath:@"selection.Artist"]];
}

- (void)loadDetails
{
    id details;
    if ((details = [[ISArtistDetailsController artistDetailsWithDelegate:self] retain])) {
        [self setValue:details forKey:@"artistDetails"];
        ISASSERT(nil != artistDetails, "setValue failed!");
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectionDidChange:)
            name:NSTableViewSelectionDidChangeNotification object:topArtistsTable];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectionDidChange:)
            name:NSTableViewSelectionDidChangeNotification object:topTracksTable];
    }
}

- (IBAction)showWindow:(id)sender
{
    if (!persistence) {
        NSBeep();
        return;
    }
    
    windowIsVisisble = YES;
    if (persistenceTh && ![super isWindowLoaded]) {
        (void)[super window];
        [self sessionDidChange:nil];
    }
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH];
    
    [super showWindow:sender];
     
    if ([[NSUserDefaults standardUserDefaults] boolForKey:OPEN_HIST_WINDOW_AT_LAUNCH]) {
        [self performSelector:@selector(showTrackHistory:) withObject:nil afterDelay:0.1];
    }
    
    if (!artistDetails)
        [self loadDetails];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    windowIsVisisble = NO;
    if ([[self valueForKey:@"loading"] boolValue])
        cancelLoad = 1;
    //[rpcreqs removeAll];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH];
    [self hideDetails:nil];
}

- (void)keyDown:(NSEvent*)event
{
    NSString *chars = [event charactersIgnoringModifiers];
    unichar ch = [chars length] == 1 ? [chars characterAtIndex:0] : 0;
    NSArrayController *data = [self currentDataController];
    NSArray *selection;
    if ((selection = [data selectedObjects]) && [selection count] == 1) {
        DBEditController *ec;
        switch (ch) {
            case NSF1FunctionKey:
                ec = [[DBRenameController alloc] init]; // released when closed by self
            break;
            case NSF2FunctionKey:
                if (data == topTracksController && [persistence isVersion2])
                    ec = [[DBRemoveController alloc] init]; // released when closed by self
                else
                    return;
            break;
            default:
                return;
            break;
        }
        [ec setObject:[selection objectAtIndex:0]];
        [ec showWindow:nil];
    }
}

- (void)handleDoubleClick:(NSTableView*)sender
{
    NSArray *selection;
    // Legacy support
    // Command and Shift are used for multiple selection, so we can't use those
    if (NSAlternateKeyMask == ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask)) {
        if ((selection = [(id)[sender dataSource] selectedObjects]) && [selection count] == 1) {
            DBRenameController *ec = [[DBRenameController alloc] init];
            [ec setObject:[selection objectAtIndex:0]];
            [ec showWindow:nil];
        } else
            NSBeep();
        return;
    }

    NSIndexSet *indices = [sender selectedRowIndexes];
    if (indices) {
        NSArray *data;
        
        @try {
            data = [(id)[sender dataSource] arrangedObjects];
        } @catch (NSException *exception) {
            return;
        }
        
        NSURL *url;
        NSMutableArray *urls = [NSMutableArray arrayWithCapacity:[indices count]];
        NSUInteger idx = [indices firstIndex];
        for (; NSNotFound != idx; idx = [indices indexGreaterThanIndex:idx]) {
            @try {
                NSDictionary *entry = [data objectAtIndex:idx];
                NSString *artist = [entry objectForKey:@"Artist"];
                NSString *track  = [entry objectForKey:@"Track"];
                if (!artist)
                    continue;
                
                url = [[NSApp delegate] audioScrobblerURLWithArtist:artist trackTitle:track];
                [urls addObject:url]; 
            } @catch (NSException *exception) {
                ScrobLog (SCROB_LOG_TRACE, @"Exception generating URL: %@", exception);
            }
        } // for
        
        NSEnumerator *en = [urls objectEnumerator];
        while ((url = [en nextObject])) {
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
    }
}

- (void)awakeFromNib
{
    [super setWindowFrameAutosaveName:@"Top Lists"];
    
    NSString *title = [NSString stringWithFormat:@"%@ - %@", [[super window] title],
        [[NSUserDefaults standardUserDefaults] objectForKey:@"version"]];
    [[self window] setTitle:title];
    
    // Seems NSArrayController adds an empty object for us, remove it
    if ([[topArtistsController content] count])
        [topArtistsController removeObjects:[topArtistsController content]];
    if ([[topTracksController content] count])
        [topTracksController removeObjects:[topTracksController content]];
    if ([[topAlbumsController content] count])
        [topAlbumsController removeObjects:[topAlbumsController content]];
    
    // Setup our sort descriptors
    NSSortDescriptor *playCountSort = [[NSSortDescriptor alloc] initWithKey:@"Play Count" ascending:NO];
    NSSortDescriptor *artistSort = [[NSSortDescriptor alloc] initWithKey:@"Artist" ascending:YES
        selector:@selector(caseInsensitiveNumericCompare:)];
    NSSortDescriptor *playTimeSort = [[NSSortDescriptor alloc] initWithKey:@"Play Time" ascending:YES
        selector:@selector(caseInsensitiveNumericCompare:)];
    NSArray *sorters = [NSArray arrayWithObjects:playCountSort, artistSort, playTimeSort, nil];
    [topArtistsController setSortDescriptors:sorters];
    
    NSSortDescriptor *trackSort = [[NSSortDescriptor alloc] initWithKey:@"Track" ascending:YES
        selector:@selector(caseInsensitiveNumericCompare:)];
    sorters = [NSArray arrayWithObjects:playCountSort, artistSort, trackSort, nil];
    [topTracksController setSortDescriptors:sorters];
    
    NSSortDescriptor *albumSort = [[NSSortDescriptor alloc] initWithKey:@"Album" ascending:YES
        selector:@selector(caseInsensitiveNumericCompare:)];
    sorters = [NSArray arrayWithObjects:playCountSort, artistSort, albumSort, nil];
    [topAlbumsController setSortDescriptors:sorters];
    
    [playCountSort release];
    [artistSort release];
    [playTimeSort release];
    [trackSort release];
    [albumSort release];
    
    [topArtistsTable setTarget:self];
    [topArtistsTable setDoubleAction:@selector(handleDoubleClick:)];
    [topTracksTable setTarget:self];
    [topTracksTable setDoubleAction:@selector(handleDoubleClick:)];
    [topAlbumsTable setTarget:self];
    [topAlbumsTable setDoubleAction:@selector(handleDoubleClick:)];
    
    
    [busyProgress retain];
    [busyView retain];
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_4) {
        // This is disabled because NSTableView uses cell transitions when
        // a layer is active and with a large number of rows, this SEVERLY slows down the table display.
        // I can't figure out how to turn off the table view transistions
        #ifdef busy_overlay_during_load
        [self addObserver:self forKeyPath:@"loading" options:0 context:nil];
        #endif
    } else
        busyView = nil;
    
    [self hideDetails:nil];
    
    // Create toolbar
    toolbarItems = [[NSMutableDictionary alloc] init];
    
    NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"toplists"];
    [tb setDisplayMode:NSToolbarDisplayModeLabelOnly]; // XXX
    [tb setSizeMode:NSToolbarSizeModeSmall];
    [tb setDelegate:self];
    [tb setAllowsUserCustomization:NO];
    [tb setAutosavesConfiguration:NO];
    #ifdef looksalittleweird
    [tb setShowsBaselineSeparator:NO];
    #endif
    
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:@"love"];
    title = [NSString stringWithFormat:@"%C ", 0x2665];
    [item setLabel:[title stringByAppendingString:NSLocalizedString(@"Love", "")]];
    [item setToolTip:NSLocalizedString(@"Love the selected track.", "")];
    [item setPaletteLabel:[item label]];
    [item setTarget:self];
    [item setAction:@selector(loveTrack:)];
    // [item setImage:[NSImage imageNamed:@""]];
    [item setTag:kTBItemRequiresSelection|kTBItemRequiresTrackSelection];
    [toolbarItems setObject:item forKey:@"love"];
    [item release];
    
    item = [[NSToolbarItem alloc] initWithItemIdentifier:@"ban"];
    title = [NSString stringWithFormat:@"%C ", 0x2298];
    [item setLabel:[title stringByAppendingString:NSLocalizedString(@"Ban", "")]];
    [item setToolTip:NSLocalizedString(@"Ban the selected track from last.fm.", "")];
    [item setPaletteLabel:[item label]];
    [item setTarget:self];
    [item setAction:@selector(banTrack:)];
    // [item setImage:[NSImage imageNamed:@""]];
    [item setTag:kTBItemRequiresSelection|kTBItemRequiresTrackSelection];
    [toolbarItems setObject:item forKey:@"ban"];
    [item release];
    
    item = [[NSToolbarItem alloc] initWithItemIdentifier:@"recommend"];
    title = [NSString stringWithFormat:@"%C ", 0x2709];
    [item setLabel:[title stringByAppendingString:NSLocalizedString(@"Recommend", "")]];
    [item setToolTip:NSLocalizedString(@"Recommend the selected track or artist to another last.fm user.", "")];
    [item setPaletteLabel:[item label]];
    [item setTarget:self];
    [item setAction:@selector(recommend:)];
    // [item setImage:[NSImage imageNamed:@""]];
    [item setTag:kTBItemRequiresSelection|kTBItemNoMultipleSelection];
    [toolbarItems setObject:item forKey:@"recommend"];
    [item release];
    
    item = [[NSToolbarItem alloc] initWithItemIdentifier:@"tag"];
    title = [NSString stringWithFormat:@"%C ", 0x270E];
    [item setLabel:[title stringByAppendingString:NSLocalizedString(@"Tag", "")]];
    [item setToolTip:NSLocalizedString(@"Tag the selected track or artist.", "")];
    [item setPaletteLabel:[item label]];
    [item setTarget:self];
    [item setAction:@selector(tag:)];
    // [item setImage:[NSImage imageNamed:@""]];
    [item setTag:kTBItemRequiresSelection];
    [toolbarItems setObject:item forKey:@"tag"];
    [item release];
    
    item = [[NSToolbarItem alloc] initWithItemIdentifier:@"showloveban"];
    [item setLabel:NSLocalizedString(@"Show Loved/Banned", "")];
    [item setToolTip:NSLocalizedString(@"Show recently Loved or Banned tracks.", "")];
    [item setPaletteLabel:[item label]];
    [item setTarget:self];
    [item setAction:@selector(showLovedBanned:)];
    // [item setImage:[NSImage imageNamed:@""]];
    [item setTag:0];
    [toolbarItems setObject:item forKey:@"showloveban"];
    [item release];
    
    item = [[NSToolbarItem alloc] initWithItemIdentifier:@"trackhistory"];
    [item setLabel:NSLocalizedString(@"History", "")];
    [item setToolTip:NSLocalizedString(@"Display track play history.", "")];
    [item setPaletteLabel:[item label]];
    [item setTarget:self];
    [item setAction:@selector(showTrackHistory:)];
    // [item setImage:[NSImage imageNamed:@""]];
    [item setTag:0]; // kTBItemRequiresSelection|kTBItemNoMultipleSelection|kTBItemRequiresTrackSelection
    [toolbarItems setObject:item forKey:@"trackhistory"];
    [item release];
    
    item = [[NSToolbarItem alloc] initWithItemIdentifier:@"artistdetails"];
    [item setLabel:NSLocalizedString(@"Artist Details", "")];
    [item setToolTip:NSLocalizedString(@"Display detailed artist information.", "")];
    [item setPaletteLabel:[item label]];
    [item setTarget:self];
    [item setAction:@selector(showArtistDetails:)];
    // [item setImage:[NSImage imageNamed:@""]];
    [item setTag:0]; // kTBItemRequiresSelection|kTBItemNoMultipleSelection|kTBItemRequiresTrackSelection
    [toolbarItems setObject:item forKey:@"artistdetails"];
    [item release];
    
    [toolbarItems setObject:[NSNull null] forKey:NSToolbarSeparatorItemIdentifier];
    [toolbarItems setObject:[NSNull null] forKey:NSToolbarFlexibleSpaceItemIdentifier];
    [toolbarItems setObject:[NSNull null] forKey:NSToolbarSpaceItemIdentifier];
    
    [[self window] setToolbar:tb];
    [tb release];
    
    rpcreqs = [[NSMutableArray alloc] init];
}

#ifdef busy_overlay_during_load
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([key isEqualToString:@"loading"]) {
        //[self performSelector:@selector(transitionBusyView) withObject:nil afterDelay:0.0];
        [self transitionBusyView];
    }
}
#endif

// ================= Toolbar support ================= //

- (void)clearUserFeedbackForItem:(NSString*)key
{
    NSToolbarItem *item = [toolbarItems objectForKey:key];
    NSInteger flags = [item tag] & ~kTBItemDisabledForFeedback;
    [item setTag:flags];
    [[[self window] toolbar] validateVisibleItems];
}

- (void)clearUserFeedbackDelayed:(NSTimer*)timer
{
    [self clearUserFeedbackForItem:[timer userInfo]];
}

- (void)setUserFeedbackForItem:(NSString*)key
{
    NSToolbarItem *item = [toolbarItems objectForKey:key];
    NSInteger flags = [item tag] | kTBItemDisabledForFeedback;
    [item setTag:flags];
    [[[self window] toolbar] validateVisibleItems];
    [NSTimer scheduledTimerWithTimeInterval:0.65 target:self selector:@selector(clearUserFeedbackDelayed:) userInfo:key repeats:NO];
}

- (void)loveBan:(NSString*)method track:(NSDictionary*)track
{
    NSString *artist = [track objectForKey:@"Artist"];
    NSString *title = [track objectForKey:@"Track"];
    if (!artist || !title)
        return;
    
    ASXMLRPC *req = [[[ASXMLRPC alloc] init] autorelease];
    [req setMethod:method];
    NSMutableArray *p = [req standardParams];
    [p addObject:artist];
    [p addObject:title];
    [req setParameters:p];
    [req setDelegate:self];
    [req setRepresentedObject:track];
    [req sendRequest];
    [rpcreqs addObject:req];
}

- (IBAction)loveTrack:(id)sender
{
    @try {
        NSArray *tracks = [topTracksController selectedObjects];
        NSEnumerator *en = [tracks objectEnumerator];
        NSDictionary *track;
        while ((track = [en nextObject])) {
            if (![track isKindOfClass:[NSDictionary class]])
                continue;
            [self loveBan:@"loveTrack" track:track];
        }
        
        [self setUserFeedbackForItem:@"love"];
    } @catch (id e) {}
}

- (IBAction)banTrack:(id)sender
{
    @try {
        NSArray *tracks = [topTracksController selectedObjects];
        NSEnumerator *en = [tracks objectEnumerator];
        NSDictionary *track;
        while ((track = [en nextObject])) {
            if (![track isKindOfClass:[NSDictionary class]])
                continue;
            [self loveBan:@"banTrack" track:track];
        }
        
        [self setUserFeedbackForItem:@"ban"];
    } @catch (id e) {}
}

- (void)recommendSheetDidEnd:(NSNotification*)note
{
    ISRecommendController *rc = [note object];
    NSDictionary *song = [rc representedObject];
    if ([rc send] && song && [song isKindOfClass:[NSDictionary class]]) {
        NSString *artist = [song objectForKey:@"Artist"];
        if (!artist)
            goto exit;
        
        ASXMLRPC *req = [[[ASXMLRPC alloc] init] autorelease];
        NSMutableArray *p = [req standardParams];
        
        NSString *title;
        [req setMethod:@"recommendItem"];
        switch ([rc type]) {
            case rt_track: {
                title = [song objectForKey:@"Track"];
                if (!title) {
                    [req release];
                    goto exit;
                }
                [p addObject:artist];
                [p addObject:title];
                [p addObject:@"track"]; // type
            } break;
            
            case rt_artist:
                [p addObject:artist];
                [p addObject:@""]; // title, must be an empty string
                [p addObject:@"artist"]; // type
            break;
            
            case rt_album:
                title = [song objectForKey:@"Album"];
                if (!title) {
                    [req release];
                    goto exit;
                }
                [p addObject:artist];
                [p addObject:title];
                [p addObject:@"album"]; // type
            break;
            default:
                [req release];
                goto exit;
            break;
        }
        [p addObject:[rc who]]; // reciever
        [p addObject:[rc message]]; // message
        [p addObject:WS_LANG]; // language - only english for now
        
        [req setParameters:p];
        [req setDelegate:self];
        [req setRepresentedObject:song];
        [req sendRequest];
        [rpcreqs addObject:req];
    }
    
exit:
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISRecommendDidEnd object:rc];
    [rc release];
}

- (IBAction)recommend:(id)sender
{
    id data, obj;
    @try {
    data = [self currentDataController];
    obj = [[data selectedObjects] objectAtIndex:0];
    } @catch (id e) {
        return;
    }
    if (!obj || ![obj isKindOfClass:[NSDictionary class]])
        return;
    
    ISRecommendController *rc = [[ISRecommendController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recommendSheetDidEnd:)
        name:ISRecommendDidEnd object:rc];
    if (data == topArtistsController) {
        [rc setTrackEnabled:NO];
        [rc setAlbumEnabled:NO];
        [rc setType:rt_artist];
    } else if (data == topAlbumsController) {
        [rc setTrackEnabled:NO];
        [rc setType:rt_album];
    }
    [rc setRepresentedObject:obj];
    [rc showWindow:[self window]];
}

- (void)tagSheetDidEnd:(NSNotification*)note
{
    ISTagController *tc = [note object];
    NSArray *tracks = [tc representedObject];
    NSArray *tags = [tc tags];
    NSString *title;
    if (tags && [tc send] && tracks && [tracks isKindOfClass:[NSArray class]]) {
        NSEnumerator *en = [tracks objectEnumerator];
        NSDictionary *song;
        while ((song = [en nextObject])) {
            if (![song isKindOfClass:[NSDictionary class]])
                continue;
            NSString *artist = [song objectForKey:@"Artist"];
            if (!artist)
                continue;
            
            ASXMLRPC *req = [[[ASXMLRPC alloc] init] autorelease];
            NSMutableArray *p = [req standardParams];
            NSString *mode = [tc editMode] == tt_overwrite ? @"set" : @"append";
            switch ([tc type]) {
                case tt_track: {
                    title = [song objectForKey:@"Track"];
                    if (!title) {
                        [req release];
                        continue;
                    }
                    [req setMethod:@"tagTrack"];
                    [p addObject:artist];
                    [p addObject:title];
                } break;
                
                case tt_artist:
                    [req setMethod:@"tagArtist"];
                    [p addObject:artist];
                break;
                
                case tt_album:
                    title = [song objectForKey:@"Album"];
                    if (!title) {
                        [req release];
                        continue;
                    }
                    [req setMethod:@"tagAlbum"];
                    [p addObject:artist];
                    [p addObject:title];
                break;               
                default:
                    [req release];
                    continue;
                break;
            }
            [p addObject:tags];
            [p addObject:mode];
            
            [req setParameters:p];
            [req setDelegate:self];
            [req setRepresentedObject:song];
            [req sendRequest];
            [rpcreqs addObject:req];
        } // while(song)
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISTagDidEnd object:tc];
    [tc release];
}

- (IBAction)tag:(id)sender
{
    id data, obj;
    @try {
    data = [self currentDataController];
    obj = [data selectedObjects];
    } @catch (id e) {
        return;
    }
    
    ISTagController *tc = [[ISTagController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tagSheetDidEnd:)
        name:ISTagDidEnd object:tc];
    if (data == topArtistsController) {
        [tc setTrackEnabled:NO];
        [tc setAlbumEnabled:NO];
        [tc setType:tt_artist];
    } else if (data == topAlbumsController) {
        [tc setTrackEnabled:NO];
        [tc setType:tt_album];
    }
    [tc setRepresentedObject:obj];
    [tc showWindow:[self window]];
}

- (IBAction)showLovedBanned:(id)sender
{
    [[ISLoveBanListController sharedController] showWindow:[self window]];
}

- (IBAction)showTrackHistory:(id)sender
{
    if (persistenceTh && ![PlayHistoryController sharedController]) {
        PlayHistoryController *hc = [[PlayHistoryController alloc] init]; // released when closed by self
        [hc showWindow:nil];
        NSArray *selection;
        if ((selection = [topTracksController selectedObjects]) && [selection count] > 0)
            [hc loadHistoryForTrack:[selection objectAtIndex:0]];
    }
}

// ASXMLRPC
- (void)responseReceivedForRequest:(ASXMLRPC*)request
{
    if (NSOrderedSame != [[request response] compare:@"OK" options:NSCaseInsensitiveSearch]) {
        NSError *err = [NSError errorWithDomain:@"iScrobbler" code:-1 userInfo:
            [NSDictionary dictionaryWithObject:[request response] forKey:@"Response"]];
        [self error:err receivedForRequest:request];
        return;
    }
    
    NSString *method = [request method];
    NSString *tag = nil;
    if ([method isEqualToString:@"loveTrack"]) {
        tag = @"loved";
    } else if ([method isEqualToString:@"banTrack"]) {
        tag = @"banned";
    } else if ([method hasPrefix:@"tag"])
        [ASXMLFile expireCacheEntryForURL:[ASWebServices currentUserTagsURL]];
    
    id obj = [request representedObject];
    ScrobLog(SCROB_LOG_TRACE, @"RPC request '%@' successful (%@)", method, obj);
    
    NSString *artist, *title;
    if (tag && [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTagLovedBanned"]
        && [obj isKindOfClass:[NSDictionary class]]
        && (artist = [obj objectForKey:@"Artist"])
        && (title = [obj objectForKey:@"Track"])) {
        ASXMLRPC *tagReq = [[[ASXMLRPC alloc] init] autorelease];
        NSMutableArray *p = [tagReq standardParams];
        [tagReq setMethod:@"tagTrack"];
        [p addObject:artist];
        [p addObject:title];
        [p addObject:[NSArray arrayWithObject:tag]];
        [p addObject:@"append"];
        
        [tagReq setParameters:p];
        [tagReq setDelegate:self];
        [tagReq setRepresentedObject:obj];
        [tagReq performSelector:@selector(sendRequest) withObject:nil afterDelay:0.0];
        
        [request retain];
        [rpcreqs removeObject:request];
        [request autorelease];
        
        [rpcreqs addObject:tagReq];
    } else {
        [request retain];
        [rpcreqs removeObject:request];
        [request autorelease];
        
        [[[self window] toolbar] validateVisibleItems];
    }
}

- (void)error:(NSError*)error receivedForRequest:(ASXMLRPC*)request
{
    ScrobLog(SCROB_LOG_ERR, @"RPC request '%@' for '%@' returned error: %@",
        [request method], [request representedObject], error);
    
    [request retain];
    [rpcreqs removeObject:request];
    [request autorelease];
    [[[self window] toolbar] validateVisibleItems];
}

// NSToolbar
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier
    willBeInsertedIntoToolbar:(BOOL)flag 
{
    return [toolbarItems objectForKey:itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return [toolbarItems allKeys];
}

// Called once during toolbar init
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    return [NSArray arrayWithObjects:
        NSToolbarFlexibleSpaceItemIdentifier,
        @"artistdetails",
        @"trackhistory",
        NSToolbarSeparatorItemIdentifier,
        @"showloveban",
        NSToolbarSeparatorItemIdentifier,
        @"recommend",
        @"tag",
        NSToolbarSeparatorItemIdentifier,
        @"ban",
        @"love",
        //NSToolbarSpaceItemIdentifier,
        nil];
}

- (BOOL)validateToolbarItem:(NSToolbarItem*)item
{
    id data;
    NSInteger flags = [item tag];
    if (0 == flags)
        return (YES);
    
    @try {
    data = [self currentDataController];
    } @catch (id e) {
        return (NO);
    }
    if ((flags & kTBItemDisabledForFeedback))
        return (NO);
    
    NSUInteger ct = [[data selectedObjects] count];
    BOOL valid = YES;
    if ((flags & kTBItemRequiresSelection))
        valid = (ct > 0);
    if (valid && (flags & kTBItemRequiresTrackSelection))
        valid = (data == topTracksController);
    if (valid && (flags & kTBItemNoMultipleSelection))
        valid = (1 == ct);
    
    //ScrobTrace(@"flags = %lx, ct = %lu, valid = %d", flags, ct, valid);
    return (valid);
}

// Artist Details delegate
- (NSString*)detailsFrameSaveName
{
    return (@"Top Lists Details");
}

+ (BOOL)willCreateNewProfile
{
    // XXX this belongs in the persistence plugin, but it's here so we don't have to load the plugin to test
    // whether a new profile will be created or not.
    NSURL *url = [NSURL fileURLWithPath:PERSISTENT_STORE_DB]; 
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:nil URL:url error:nil];
    if (!metadata) {
        url = [NSURL fileURLWithPath:PERSISTENT_STORE_DB_21X]; 
        metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:nil URL:url error:nil];
    }
    #if 0
    // while technically indicating a new profile, the last check is also true while an import is in progress
    // and [iScrobblerController applicationShouldTerminate:] would break in this case.
    return (!metadata || (nil != [metadata objectForKey:@"ISWillImportiTunesLibrary"]);
    #endif
    
    return (!metadata && NO == [[NSFileManager defaultManager] fileExistsAtPath:PERSISTENT_STORE_XML]);
}

+ (BOOL)isActive
{
    return (g_topLists != nil);
}

// singleton support
+ (TopListsController*)sharedInstance
{
    if (g_topLists)
        return (g_topLists);
    
    return ((g_topLists = [[TopListsController alloc] initWithWindowNibName:@"TopLists"]));
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if (g_topLists == nil) {
            return ([super allocWithZone:zone]);
        }
    }

    return (g_topLists);
}

- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (NSUInteger)retainCount
{
    return (NSUIntegerMax);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end

#define PROFILE_DATE_FORMAT @"%Y-%m-%d %I:%M:%S %p"

@implementation TopListsController (ISProfileReportAdditions)

- (void)generateProfileReport
{
    // Create html
    NSString *cssPath = [@"~/Documents/iScrobblerProfile.css" stringByExpandingTildeInPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cssPath])
        cssPath = [[NSBundle mainBundle] pathForResource:@"ProfileReport" ofType:@"css"];
    
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%@'s iScrobbler Profile (%@)", ""),
        NSFullUserName(), [[NSDate date] descriptionWithCalendarFormat:PROFILE_DATE_FORMAT timeZone:nil locale:nil]];
    
    NSData *data = nil;
    @try {
        data = [self generateHTMLReportWithCSSURL:[NSURL fileURLWithPath:cssPath]
            withTitle:title];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while generating profile report: %@.", e);
        NSBeep();
        return;
    }
    
    ISProfileDocumentController *report =
        [[ISProfileDocumentController alloc] initWithWindowNibName:@"ISProfileReport"];
    @try {
        [report showWindowWithHTMLData:data withWindowTitle:title];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while creating profile report: %@.", e);
        [report release];
        return;
    }
}

- (IBAction)createProfileReport:(id)sender
{    
    if (!topRatings) {
        NSManagedObjectID *oid = [[self selectedSession] objectID];
        if (oid) {
            [self setValue:[NSNumber numberWithBool:YES] forKey:@"loading"]; // this is cleared in [loadExtendedDidFinish];
            [ISThreadMessenger makeTarget:persistenceTh performSelector:@selector(loadExtendedSessionData:) withObject:oid];
        }
    } else
        [self generateProfileReport];
}

#define TOP_ARTISTS_TITLE NSLocalizedString(@"Top Artists", "")
#define NEW_ARTISTS_TITLE NSLocalizedString(@"New Artists", "")
#define TOP_TRACKS_TITLE NSLocalizedString(@"Top Tracks", "")
#define TOP_ALBUMS_TITLE NSLocalizedString(@"Top Albums", "")
#define TOP_RATINGS_TITLE NSLocalizedString(@"Top Ratings", "")
#define TOP_HOURS_TITLE NSLocalizedString(@"Top Hours", "")

- (NSString*)tableTitleWithString:(NSString*)tt usingID:(NSString*)tid
{
    static NSDictionary *bclinks = nil;
    static NSArray *bctitles = nil;
    if (!bclinks) {
        bctitles = [[NSArray alloc] initWithObjects:
            TOP_ARTISTS_TITLE,
            NEW_ARTISTS_TITLE,
            TOP_TRACKS_TITLE,
            TOP_ALBUMS_TITLE,
            TOP_RATINGS_TITLE,
            TOP_HOURS_TITLE,
            nil];
        bclinks = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"ta", TOP_ARTISTS_TITLE,
            @"na", NEW_ARTISTS_TITLE,
            @"tt", TOP_TRACKS_TITLE,
            @"tal", TOP_ALBUMS_TITLE,
            @"tr", TOP_RATINGS_TITLE,
            @"th", TOP_HOURS_TITLE,
            nil];
    }
    
    NSString *myname = [bclinks objectForKey:tid];
    if (myname) {
        NSMutableString *breadcrumb = [NSMutableString string];
        NSEnumerator *en = [bctitles objectEnumerator];
        NSString *s;
        while ((s = [en nextObject])) {
            if (NSOrderedSame == [s localizedCaseInsensitiveCompare:tid])
                continue;
            
            [breadcrumb appendFormat:@"<a href=\"#%@\">%@</a>&nbsp;", [bclinks objectForKey:s], s];
        }
        
        return ([NSString stringWithFormat:@"<a name=\"%@\"><h4>%@</h4></a> <div class=\"breadcrumbs\">%@</div>\n",
            myname, tt, breadcrumb]);
    }
    
    return ([NSString stringWithFormat:@"<h4>%@</h4>\n",tt]);
}

#define HEAD @"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n" \
@"\t\t\"http://www.w3.org/TR/2000/REC-xhtml1-20000126/DTD/xhtml1-strict.dtd\">" \
@"<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">" \
@"<head>\n<meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\" />\n"
#define STYLE @"<link rel=\"stylesheet\" type=\"text/css\" href=\"%@\" title=\"iScrobbler stylesheet\" />\n"
#define HEAD_CLOSE @"</head>\n"
#define BODY @"<body><div class=\"content\">\n"
#define DOCCLOSE @"</div></body></html>"
#define TBLCLOSE @"</table>\n"
#define TBLTITLE(t, tid) [self tableTitleWithString:t usingID:tid]
#define TR @"<tr>\n"
#define TRALT @"<tr class=\"alt\">"
#define TRCLOSE @"</tr>\n"
#define TD @"<td>"
#define TDTITLE @"<td class=\"title\">"
#define TDGRAPH @"<td class=\"smallgraph\">" 
#define TDPOS @"<td class=\"position\">"
#define TDCLOSE @"</td>\n"

NS_INLINE NSString* TH(int span, NSString *title)
{
    return ( [NSString stringWithFormat:@"<th colspan=\"%d\" align=\"left\">%@</th>\n", span, title] );
}

NS_INLINE void HAdd(NSMutableData *d, NSString *str)
{
    [d appendData:[str dataUsingEncoding:NSUTF8StringEncoding]];
}

NS_INLINE NSString* TDEntry(NSString *type, id obj)
{
    return ( [NSString stringWithFormat:@"%@%@%@", type, obj, TDCLOSE] );
}

NS_INLINE NSString* DIVEntry(NSString *type, float width, NSString *title, id obj)
{
    return ( [NSString stringWithFormat:@"<div class=\"%@\" %@style=\"width:%u%%;\">%@</div>",
       type,  (title ? [NSString stringWithFormat:@"title=\"%@\" ", title] : @""),
       (unsigned)width, obj] );
}

- (NSData*)generateHTMLReportWithCSSURL:(NSURL*)cssURL withTitle:(NSString*)profileTitle
{
    NSMutableData *d = [NSMutableData data];
    
    HAdd(d, HEAD);
    HAdd(d, [NSString stringWithFormat:@"<title>%@</title>\n", profileTitle]);
    HAdd(d, [NSString stringWithFormat:STYLE, [NSString stringWithFormat:@"file://%@", [cssURL path]]]);
    HAdd(d, HEAD_CLOSE BODY);
    
    NSArray *artists = [[topArtistsController valueForKey:@"arrangedObjects"]
        sortedArrayUsingSelector:@selector(sortByPlayCount:)];
    NSArray *tracks = [[topTracksController valueForKey:@"arrangedObjects"]
        sortedArrayUsingSelector:@selector(sortByPlayCount:)];
    
    NSNumber *totalTime = [artists valueForKeyPath:@"Total Duration.@sum.unsignedIntValue"];
    NSNumber *totalPlays = [artists valueForKeyPath:@"Play Count.@sum.unsignedIntValue"];
    
    unsigned int days, hours, minutes, seconds;
    ISDurationsFromTime([totalTime unsignedIntValue], &days, &hours, &minutes, &seconds);
    NSString *timeStr = [NSString stringWithFormat:@"%u %@, %u:%02u:%02u",
        days, (1 == days ? NSLocalizedString(@"day","") : NSLocalizedString(@"days", "")),
        hours, minutes, seconds];
    
    NSDate *startDate = [[self selectedSession] valueForKey:@"epoch"];
    NSDate *endDate;
    NSManagedObject *session = [self currentSession];
    if (!(endDate = [session valueForKey:@"term"]) || [endDate isGreaterThan:[NSDate date]])
        endDate = [NSDate date];
    
    NSTimeInterval elapsedSeconds =  [endDate timeIntervalSince1970] - [startDate timeIntervalSince1970];
    ISDurationsFromTime64(elapsedSeconds, &days, &hours, &minutes, &seconds);
    NSString *elapsedTime = [NSString stringWithFormat:@"%u %@, %u:%02u:%02u",
        days, (1 == days ? NSLocalizedString(@"day","") : NSLocalizedString(@"days", "")),
        hours, minutes, seconds];
    
    //// OVERALL ////
    HAdd(d, @"<table style=\"width:100%; border:0; margin:0; padding:0;\">\n<tr><td valign=\"top\">\n");
    
    HAdd(d, @"<div class=\"modbox\" style=\"vertical-align:top;\">\n" @"<table class=\"topn\">\n" TR);
    HAdd(d, TH(2, TBLTITLE(NSLocalizedString(@"Totals", ""), @"")));
    HAdd(d, TRCLOSE TR);
    HAdd(d, TDEntry(@"<td class=\"att\">", NSLocalizedString(@"Tracks Played:", "")));
    
    NSTimeInterval elapsedDays = (elapsedSeconds / 86400.0);
    NSString *tmp = [NSString stringWithFormat:NSLocalizedString(@"That's an average of %.0f tracks per day", ""),
        elapsedDays >= 1.0 ? round([totalPlays doubleValue] / elapsedDays) : [totalPlays doubleValue]];
    if (elapsedDays > 7.0) {
        tmp = [tmp stringByAppendingFormat:NSLocalizedString(@", %.0f tracks per week", ""),
            round([totalPlays doubleValue] / (elapsedDays / 7.0))];
        if (elapsedDays > 30.0) {
            tmp = [tmp stringByAppendingFormat:NSLocalizedString(@", %.0f tracks per month", ""),
                round([totalPlays doubleValue] / (elapsedDays / 30.0))];
            if (elapsedDays > 365.0) {
                tmp = [tmp stringByAppendingFormat:NSLocalizedString(@", %.0f tracks per year", ""),
                    round([totalPlays doubleValue] / (elapsedDays / 365.0))];
            }
        }
    }
    HAdd(d, TDEntry(TD, [NSString stringWithFormat:@"<span title=\"%@\">%@ (%@ %@)</span>",
        tmp,
        [NSString stringWithFormat:NSLocalizedString(@"%@ plays from %lu artists", ""), totalPlays, [artists count]],
        NSLocalizedString(@"since", ""),
        [startDate descriptionWithCalendarFormat:@"%B %e, %Y %I:%M %p" timeZone:nil locale:nil]]));
    HAdd(d, TRCLOSE TRALT);
    
    tmp = [NSString stringWithFormat:NSLocalizedString(@"That's an average of %0.2f hours per day", ""),
        ([totalTime doubleValue] / 3600.0) / elapsedDays];
    HAdd(d, TDEntry(@"<td class=\"att\">", NSLocalizedString(@"Time Played:", "")));
    HAdd(d, TDEntry(TD, [NSString stringWithFormat:@"<span title=\"%@\">%@ (%0.2f%% %@ %@ %@)</span>",
        tmp, timeStr, ([totalTime floatValue] / elapsedSeconds) * 100.0,
        NSLocalizedString(@"of", ""), elapsedTime, NSLocalizedString(@"elapsed", "")]));
    HAdd(d, TRCLOSE TBLCLOSE @"</div>");
    
    HAdd(d, TDCLOSE TRCLOSE TBLCLOSE);
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    //// ARTISTS ////
    HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"topartists\">\n" TR);
    tmp = [NSString stringWithFormat:@"<span title=\"%@: %lu\">%@</span>",
        NSLocalizedString(@"Total", ""), [artists count], TOP_ARTISTS_TITLE];
    
    NSEnumerator *en;
    unsigned position = 0; // ranking in chart
    unsigned absPosition = 1; // absolute position in chart
    unsigned prevPlayCount = 0;
    NSNumber *playCount;
    NSString *artist;
    /// compute previuos artist chart rankings
    NSArray *previousArtistCounts = [artistComparisonData keysSortedByValueUsingSelector:@selector(compare:)];
    NSMutableDictionary *previousArtistRanks;
    if ([[artistComparisonData objectForKey:[previousArtistCounts lastObject]] unsignedIntValue] > 0) {
        previousArtistRanks = [NSMutableDictionary dictionaryWithCapacity:[previousArtistCounts count]];
        en = [previousArtistCounts reverseObjectEnumerator]; // high->low
        while ((artist = [en nextObject])) {
            playCount = [artistComparisonData objectForKey:artist];
            if (prevPlayCount != [playCount unsignedIntValue]) {
                position = absPosition;
                prevPlayCount = [playCount unsignedIntValue];
            }
            
            [previousArtistRanks setObject:[NSNumber numberWithUnsignedInt:position] forKey:artist];
            ++absPosition;
        }
    } else {
        previousArtistCounts = nil;
        previousArtistRanks = nil;
    }
    
    HAdd(d, TH(previousArtistCounts ? 3 : 2, TBLTITLE(tmp, TOP_ARTISTS_TITLE)));
    HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Count", ""), @"")));
    if (elapsedDays > 14.0) {
        HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Count per Week", ""), @"")));
    } else
        HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Count per Day", ""), @"")));
    HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Time", ""), @"")));
    HAdd(d, TRCLOSE);
    
    en = [artists reverseObjectEnumerator]; // high->low
    NSDictionary *entry;
    NSString *track;
    float width = 100.0f /* bar width */, percentage,
    basePlayCount = [[artists valueForKeyPath:@"Play Count.@max.unsignedIntValue"] floatValue],
    basePlayTime = [[artists valueForKeyPath:@"Total Duration.@max.unsignedIntValue"] floatValue];
    float secondaryBasePlayCount = basePlayCount / (elapsedDays > 14.0 ? (elapsedDays / 7.0) : elapsedDays);
    float secondaryTotalPlayCount = [totalPlays floatValue] / (elapsedDays > 14.0 ? (elapsedDays / 7.0) : elapsedDays);
    NSNumber *previousRank;
    NSMutableArray *newArtists = [NSMutableArray array];
    position = 0;
    absPosition = 1;
    prevPlayCount = 0;
    while ((entry = [en nextObject])) {
        artist = [[entry objectForKey:@"Artist"] stringByConvertingCharactersToHTMLEntities];
        playCount = [entry objectForKey:@"Play Count"];
        timeStr = [entry objectForKey:@"Play Time"];
        if ([[entry objectForKey:@"New This Session"] boolValue])
            [newArtists addObject:artist];
        
        HAdd(d, (absPosition & 0x0000001) ? TR : TRALT);
        
        if (prevPlayCount != [playCount unsignedIntValue]) {
            position = absPosition;
            prevPlayCount = [playCount unsignedIntValue];
        }
        previousRank = [previousArtistRanks objectForKey:artist];
        if (previousRank) {
            int delta = (int)position - [previousRank intValue];
            unichar deltaChar;
            if (delta < 0) {
                tmp = [NSString stringWithFormat:@"<td class=\"delta\" title=\"%@\">",
                    [NSString stringWithFormat:NSLocalizedString(@"Up %d places", ""), ABS(delta)]];
                deltaChar = 0x25B2; // up triangle
            } else if (delta > 0) {
                tmp = [NSString stringWithFormat:@"<td class=\"delta\" title=\"%@\">",
                    [NSString stringWithFormat:NSLocalizedString(@"Down %d places", ""), delta]];
                deltaChar = 0x25BC; // down triangle
            } else {
                tmp = [NSString stringWithFormat:@"<td class=\"delta\" title=\"%@\">",
                    NSLocalizedString(@"Same position", "")];
                deltaChar = 0x2014; // em dash
            }
            
            HAdd(d, TDEntry(tmp, [NSString stringWithFormat:(delta != 0 ? @"%C&nbsp;%ld" : @"%C"),
                deltaChar, ABS(delta)]));
        } else if (previousArtistRanks) {
            tmp = [NSString stringWithFormat:@"<td class=\"delta\" title=\"%@\">",
                NSLocalizedString(@"New entry", "")];
            HAdd(d, TDEntry(tmp, @"&nbsp;"));
        }
        HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
        HAdd(d, TDEntry(@"<td class=\"mediumtitle\">", artist));
        // Total Plays bar
        width = rintf(([playCount floatValue] / basePlayCount) * 100.0f);
        percentage = ([playCount floatValue] / [totalPlays floatValue]) * 100.0f;
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, playCount)));
        // Per Day/Week count
        float secondaryCount = [playCount floatValue] / (elapsedDays > 14.0 ? (elapsedDays / 7.0) : elapsedDays);
        width = rintf((secondaryCount / secondaryBasePlayCount) * 100.0f);
        percentage = (secondaryCount / secondaryTotalPlayCount) * 100.0f;
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, [NSString stringWithFormat:@"%.1f", secondaryCount])));
        // Total time bar
        width = rintf(([[entry objectForKey:@"Total Duration"] floatValue] / basePlayTime) * 100.0f);
        percentage = ([[entry objectForKey:@"Total Duration"] floatValue] / [totalTime floatValue]) * 100.0f;
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, timeStr)));
        
        HAdd(d, TRCLOSE);
        ++absPosition;
    }
    
    HAdd(d, TBLCLOSE @"</div>");
    
    //// NEWARTISTS ////
    if ([persistence isVersion2]) {
        HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"newartists\">\n" TR);
        tmp = [NSString stringWithFormat:@"<span title=\"%@: %lu\">%@</span>",
            NSLocalizedString(@"Total", ""), [newArtists count], NEW_ARTISTS_TITLE];
        HAdd(d, TH(4, TBLTITLE(tmp, NEW_ARTISTS_TITLE)));
        HAdd(d, TRCLOSE);
        en = [[newArtists sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] objectEnumerator];
        #if 0
        absPosition = 1;
        if (elapsedDays > 14.0) {
            // 1 artist per row with date
            while ((entry = [en nextObject])) {
                HAdd(d, (absPosition & 0x0000001) ? TR : TRALT);
                HAdd(d, TDEntry(@"<td class=\"title\">", entry));
                HAdd(d, TRCLOSE);
                ++absPosition;
            }
        } else
        #endif
        {
            // 1 row with all artists
            NSMutableString *s = [NSMutableString stringWithString:@""];
            HAdd(d, TR);
            while ((entry = [en nextObject])) {
                [s appendFormat:@"%@, ", entry];
            }
            NSRange r;
            r.location = [s length];
            if (r.location > 0) {
                // remove the trailing ", "
                r.location -= 2;
                r.length = 2;
                [s deleteCharactersInRange:r];
            }
            HAdd(d, TDEntry(@"<td class=\"userinfo\">", s));
            HAdd(d, TRCLOSE);
        }
        HAdd(d, TBLCLOSE @"</div>");
    }
    
    [pool release];
    
    pool = [[NSAutoreleasePool alloc] init];
    //// TRACKS ////
    HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"toptracks\">\n" TR);
    tmp = [NSString stringWithFormat:@"<span title=\"%@: %lu\">%@</span>",
        NSLocalizedString(@"Total", ""), [tracks count], TOP_TRACKS_TITLE];
    HAdd(d, TH(2, TBLTITLE(tmp, TOP_TRACKS_TITLE)));
    HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Last Played", ""), @"")));
    HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Count", ""), @"")));
    HAdd(d, TRCLOSE);
    
    en = [tracks reverseObjectEnumerator]; // high->low
    absPosition = 1;
    position = 0;
    prevPlayCount = 0;
    basePlayCount = [[tracks valueForKeyPath:@"Play Count.@max.unsignedIntValue"] floatValue];
    while ((entry = [en nextObject])) {
        artist = [[entry objectForKey:@"Artist"] stringByConvertingCharactersToHTMLEntities];
        playCount = [entry objectForKey:@"Play Count"];
        timeStr = [[entry objectForKey:@"Last Played"]
            descriptionWithCalendarFormat:PROFILE_DATE_FORMAT timeZone:nil locale:nil];
        track = [[entry objectForKey:@"Track"] stringByConvertingCharactersToHTMLEntities];
        
        HAdd(d, (absPosition & 0x0000001) ? TR : TRALT);
        
        if (prevPlayCount != [playCount unsignedIntValue]) {
            ++position;
            prevPlayCount = [playCount unsignedIntValue];
        }
        HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
        tmp = [NSString stringWithFormat:@"%@ - %@", track, artist];
        HAdd(d, TDEntry(TDTITLE, tmp));
        HAdd(d, TDEntry(TDGRAPH, timeStr)); // Last play time
        // Total Plays bar
        width = rintf(([playCount floatValue] / basePlayCount) * 100.0f);
        percentage = ([playCount floatValue] / [totalPlays floatValue]) * 100.0f;
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, playCount)));
        
        HAdd(d, TRCLOSE);
        ++absPosition;
    }
    
    HAdd(d, TBLCLOSE @"</div>");
    [pool release];
    
    //// ALBUMS ////
    NSArray *topAlbums = [[topAlbumsController valueForKey:@"arrangedObjects"]
        sortedArrayUsingSelector:@selector(sortByPlayCount:)];
    if ([topAlbums count] > 0) {
        pool = [[NSAutoreleasePool alloc] init];
        
        HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"topalbums\">\n" TR);
        tmp = [NSString stringWithFormat:@"<span title=\"%@: %lu\">%@</span>",
            NSLocalizedString(@"Total", ""), [topAlbums count], TOP_ALBUMS_TITLE];
        HAdd(d, TH(2, TBLTITLE(tmp, TOP_ALBUMS_TITLE)));
        HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Count", ""), @"")));
        HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Time", ""), @"")));
        HAdd(d, TRCLOSE);
        
        basePlayCount = [[topAlbums valueForKeyPath:@"Play Count.@max.unsignedIntValue"] floatValue],
        basePlayTime = [[topAlbums valueForKeyPath:@"Total Duration.@max.unsignedIntValue"] floatValue];
        en = [topAlbums reverseObjectEnumerator]; // high->low
        absPosition = 1;
        position = 0;
        prevPlayCount = 0;
        while ((entry = [en nextObject])) { // tmp is our key into the topAlbums dict
            artist = [entry objectForKey:@"Artist"];
            NSString *album = [entry objectForKey:@"Album"];
            
            HAdd(d, (absPosition & 0x0000001) ? TR : TRALT);
            
            playCount = [entry objectForKey:@"Play Count"];
            if (prevPlayCount != [playCount unsignedIntValue]) {
                ++position;
                prevPlayCount = [playCount unsignedIntValue];
            }
            HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
            tmp = [NSString stringWithFormat:@"%@ - %@", album, artist];
            HAdd(d, TDEntry(TDTITLE, tmp));
            // Total Plays bar
            width = rintf(([playCount floatValue] / basePlayCount) * 100.0f);
            percentage = ([playCount floatValue] / [totalPlays floatValue]) * 100.0f;
            tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
            HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, playCount)));
            // Total time bar
            playCount = [entry objectForKey:@"Total Duration"];
            width = rintf(([playCount floatValue] / basePlayTime) * 100.0f);
            percentage = ([playCount floatValue] / [totalTime floatValue]) * 100.0f;
            tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
            ISDurationsFromTime([playCount unsignedIntValue], &days, &hours, &minutes, &seconds);
            timeStr = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
            HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, timeStr)));
            
            HAdd(d, TRCLOSE);
            ++absPosition;
        }
        
        HAdd(d, TBLCLOSE @"</div>");
        [pool release];
    }
    
    //// RATINGS ////
    if (topRatings) {
        pool = [[NSAutoreleasePool alloc] init];
        
        HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"topratings\">\n" TR);
        HAdd(d, TH(1, TBLTITLE(TOP_RATINGS_TITLE, TOP_RATINGS_TITLE)));
        HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Count", ""), @"")));
        HAdd(d, TRCLOSE);
        
        // Determine max count
        NSNumber *rating;
        unsigned maxCount = [[[topRatings allValues] valueForKeyPath:@"Play Count.@max.unsignedIntValue"] unsignedIntValue];
        basePlayCount = (float)maxCount;
        absPosition = 1;
        en = [[[topRatings allKeys] sortedArrayUsingSelector:@selector(compare:)] reverseObjectEnumerator];
        SongData *dummy = [[SongData alloc] init];
        while ((rating = [en nextObject])) {
            HAdd(d, (absPosition & 0x0000001) ? TR : TRALT);
            
            //HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
            // Get the rating string to display
            [dummy setRating:rating];
            tmp = [dummy fullStarRating];
            
            HAdd(d, TDEntry(TDTITLE, tmp));
            // Total Plays bar
            float ratingCount = (float)[[[topRatings objectForKey:rating] objectForKey:@"Play Count"] floatValue];
            width = rintf((ratingCount / basePlayCount) * 100.0f);
            percentage = (ratingCount / [totalPlays floatValue]) * 100.0f;
            tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
            playCount = [NSNumber numberWithFloat:ratingCount];
            HAdd(d, TDEntry(@"<td class=\"graph\">", DIVEntry(@"bar", width, tmp, playCount)));
            
            HAdd(d, TRCLOSE);
            ++absPosition;
        }
        [dummy release];
        
        HAdd(d, TBLCLOSE @"</div>");
        [pool release];
    }
    
    //// HOURS ////
    if (topHours) {
        pool = [[NSAutoreleasePool alloc] init];
        
        HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"tophours\">\n" TR);
        HAdd(d, TH(1, TBLTITLE(TOP_HOURS_TITLE, TOP_HOURS_TITLE)));
        HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Count", ""), @"")));
        HAdd(d, TH(1, TBLTITLE(NSLocalizedString(@"Time", ""), @"")));
        HAdd(d, TRCLOSE);
        
        // Determine max count
        unsigned maxCount = [[topHours valueForKeyPath:@"Play Count.@max.unsignedIntValue"] unsignedIntValue];
        basePlayCount = (float)maxCount;
        maxCount = [[topHours valueForKeyPath:@"Total Duration.@max.unsignedLongLongValue"] unsignedIntValue];
        basePlayTime = (float)maxCount;
        absPosition = 0;
        for (; absPosition < 24; ++absPosition) {
            HAdd(d, (absPosition & 0x0000001) ? TR : TRALT);
            
            tmp = [NSString stringWithFormat:@"%02d00", absPosition];
            
            HAdd(d, TDEntry(@"<td class=\"smalltitle\">", tmp));
            // Total Plays bar
            float ratingCount = [[[topHours objectAtIndex:absPosition] objectForKey:@"Play Count"] floatValue];
            width = rintf((ratingCount / basePlayCount) * 100.0f);
            percentage = (ratingCount / [totalPlays floatValue]) * 100.0f;
            tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
            playCount = [NSNumber numberWithFloat:ratingCount];
            HAdd(d, TDEntry(@"<td class=\"graph\">", DIVEntry(@"bar", width, tmp, playCount)));
            
            // Total time bar
            ratingCount = [[[topHours objectAtIndex:absPosition] objectForKey:@"Total Duration"] floatValue];
            width = rintf((ratingCount / basePlayTime) * 100.0f);
            percentage = (ratingCount / [totalTime floatValue]) * 100.0f;
            tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
            ISDurationsFromTime((unsigned)ratingCount, &days, &hours, &minutes, &seconds);
            timeStr = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
            HAdd(d, TDEntry(@"<td class=\"graph\">", DIVEntry(@"bar", width, tmp, timeStr)));
            
            HAdd(d, TRCLOSE);
        }
        
        HAdd(d, TBLCLOSE @"</div>");
        [pool release];
    }
    
    HAdd(d, DOCCLOSE);
    
    return (d);
}

@end

@interface PersistentProfile (SessionManagement)
- (BOOL)performSelectorOnSessionMgrThread:(SEL)selector withObject:(id)object;
@end

@interface ISChartsScriptCommand : NSScriptCommand {
}
@end

@implementation ISChartsScriptCommand

- (id)performDefaultImplementation
{
    switch ([[self commandDescription] appleEventCode]) {
        case (FourCharCode)'SylC': // synchronize local charts
            if ([TopListsController isActive]) {
                PersistentProfile *profile = [[TopListsController sharedInstance] valueForKey:@"persistence"];
                [profile performSelectorOnSessionMgrThread:@selector(synchronizeDatabaseWithiTunes) withObject:nil];
                //[profile performSelector:@selector(flushCaches:) withObject:self afterDelay:0.0];
            }
        break;
        case (FourCharCode)'RclC': // recreate local charts
            if ([TopListsController isActive]) {
                PersistentProfile *profile = [[TopListsController sharedInstance] valueForKey:@"persistence"];
                if ([profile isVersion2])
                    [profile performSelectorOnSessionMgrThread:@selector(exportDatabase:) withObject:nil];
                else {
                    NSBeep();
                    ScrobLog(SCROB_LOG_ERR, @"recreate charts is not supported with this OS version");
                }
            }
        break;
        default:
            ScrobLog(SCROB_LOG_TRACE, @"ISChartsScriptCommand: unknown aevt code: %c", [[self commandDescription] appleEventCode]);
        break;
    }
    return (nil);
}

@end

#import "TopListsPersistenceAdaptor.m"

@implementation NSString (ISHTMLConversion)

- (NSString *)stringByConvertingCharactersToHTMLEntities
{
    NSMutableString *s = [self mutableCopy];
    NSRange r;
    // This has to be the most inefficient way to do this, but it works
    
    // Replace all ampersands (must be first!)
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:r];
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:r];
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:r];
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:r];
#ifdef notyet
    r = NSMakeRange(0, [s length]);
    [s replaceOccurrencesOfString:@"\xa0" withString:@"&nbsp;" options:0 range:r];
#endif
    return ([s autorelease]);
}

@end

@implementation NSMutableDictionary (ISTopListsAdditions)

- (NSComparisonResult)sortByPlayCount:(NSDictionary*)entry
{
    return ( [(NSNumber*)[self objectForKey:@"Play Count"] compare:(NSNumber*)[entry objectForKey:@"Play Count"]] );
}

- (NSComparisonResult)sortByDuration:(NSDictionary*)entry
{
    return ( [(NSNumber*)[self objectForKey:@"Total Duration"] compare:(NSNumber*)[entry objectForKey:@"Total Duration"]] );
}

@end

@implementation NSString (ISTopListsAdditions)

- (NSComparisonResult)caseInsensitiveNumericCompare:(NSString *)string
{
    return ([self compare:string options:NSCaseInsensitiveSearch|NSNumericSearch|NSDiacriticInsensitiveSearch]);
}

@end
