//
//  PlayHistoryController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/28/07.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "PlayHistoryController.h"
#import "TopListsController.h"
#import "Persistence.h"
#import "DBEditController.h"
#import "PersistentSessionManager.h"

#import "iScrobblerController.h"
#import "SongData.h"

static PlayHistoryController *sharedController = nil;

// in PersistentSessionManager.m
@interface SongData (PersistentAdditions)
- (NSManagedObject*)persistentSongWithContext:(NSManagedObjectContext*)moc;
@end

@implementation PlayHistoryController

+ (PlayHistoryController*)sharedController
{
    return (sharedController);
}

- (id)init
{
    ISASSERT(sharedController == nil, "sharedController active!");
    sharedController = self = [super initWithWindowNibName:@"PlayHistory"];
    return (self);
}

- (void)awakeFromNib
{
    NSUInteger style = NSTitledWindowMask|NSUtilityWindowMask|NSClosableWindowMask|NSResizableWindowMask;
    style |= NSHUDWindowMask;
    NSWindow *w = [[NSPanel alloc] initWithContentRect:[contentView frame] styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [w setHidesOnDeactivate:NO];
    [w setLevel:NSNormalWindowLevel];
    if (0 == (style & NSHUDWindowMask))
        [w setAlphaValue:IS_UTIL_WINDOW_ALPHA];
    
    [w setReleasedWhenClosed:NO];
    [w setContentView:contentView];
    [w setMinSize:[contentView frame].size];
    
    [self setWindow:w];
    [w setDelegate:self]; // setWindow: does not do this for us (why?)
    [w autorelease];
    [self setWindowFrameAutosaveName:@"PlayHistory"];
    
    NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"lastPlayed" ascending:NO];
    [historyController setSortDescriptors:[NSArray arrayWithObjects:sort, nil]];
    [sort release];
    
    moc = [[NSManagedObjectContext alloc] init];
    [moc setUndoManager:nil];
    // we don't allow the user to make changes and the session mgr background thread handles all internal changes
    [moc setMergePolicy:NSRollbackMergePolicy];
    
    PersistentProfile *persistence = [[TopListsController sharedInstance] valueForKey:@"persistence"];
    id psc = [[persistence performSelector:@selector(mainMOC)] persistentStoreCoordinator];
    [moc setPersistentStoreCoordinator:psc];
}

- (IBAction)showWindow:(id)sender
{
    if (![[self window] isVisible]) {
        [NSApp activateIgnoringOtherApps:YES];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowPlaying:)
            name:@"Now Playing" object:nil];
            
         [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileDidEditObject:)
            name:PersistentProfileDidEditObject
            object:nil];
        
        id obj = [[NSApp delegate] nowPlaying];
        if (obj) {
            NSNotification *note = [NSNotification notificationWithName:@"Now Playing" object:obj];
            [self performSelector:@selector(nowPlaying:) withObject:note afterDelay:0.2];
        }
    }
    [super showWindow:nil];
}

- (IBAction)performClose:(id)sender
{
    [[self window] close];
}

- (BOOL)windowShouldClose:(NSNotification*)note
{
    return ([self scrobWindowShouldClose]);
}

- (void)windowWillClose:(NSNotification*)note
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    [moc release];
    moc = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:PersistentProfileDidEditObject object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"Now Playing" object:nil];
    [npTrackInfo release];
    npTrackInfo = nil;
    
    [currentTrackInfo release];
    currentTrackInfo = nil;
    
    ISASSERT(sharedController == self, "sharedController does not match!");
    sharedController = nil;
    [self autorelease];
}

- (void)nowPlaying:(NSNotification*)note
{
    SongData *song = [note object];
    
    NSDictionary *prevTrackInfo = [npTrackInfo autorelease];
    npTrackInfo = nil;
    
    if (!song) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
        
        if (!editMode && prevTrackInfo && [[[note userInfo] objectForKey:@"isStopped"] boolValue]) {
            // update the previous track to reflect any changes
            [self performSelector:@selector(loadHistoryForTrack:) withObject:prevTrackInfo afterDelay:1.5];
        }
        return;
    }
    
    NSManagedObjectID *mid = nil;
    @try {
        mid = [[song persistentSongWithContext:moc] objectID];
    } @catch (NSException *e) {
        NSBeep();
        ScrobLog(SCROB_LOG_ERR, @"History: exception getting persistent object for: %@", [song brief]);
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
        return;
    }
    
    npTrackInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
        [song artist], @"Artist",
        [song title], @"Track",
        mid, @"objectID", // this must be last as songs not yet in the db will have a nil id
        nil];
    
    if (!editMode)
        [self loadHistoryForTrack:npTrackInfo];
}

- (void)loadHistoryForTrack:(NSDictionary*)trackInfo
{
    [currentTrackInfo release];
    currentTrackInfo = nil;
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    NSString *title = [NSString stringWithFormat:@"\"%@ - %@\" %@",
        [trackInfo objectForKey:@"Track"], [trackInfo objectForKey:@"Artist"], NSLocalizedString(@"History", "")];
    if (editMode)
        title = [NSString stringWithFormat:@"%C %@", 0x270E, title];
    [[self window] setTitle:title];
    
    NSMutableArray *content = [NSMutableArray array];
    [historyController setContent:content];
    [totalPlayCount setStringValue:@"0"];
    [totalPlayCount setToolTip:nil];
    
    NSManagedObjectID *mid = [trackInfo objectForKey:@"objectID"];
    if (!mid) {
        [historyController rearrangeObjects];
        ScrobLog(SCROB_LOG_TRACE, @"History: persistent id for '%@ - %@' is missing.",
            [trackInfo objectForKey:@"Track"], [trackInfo objectForKey:@"Artist"]);
        return;
    }
    
    [progress startAnimation:nil];
    
    NSManagedObject *song = [moc objectWithID:mid];
    NSSet *history = [song valueForKey:@"playHistory"];
    
    // batch load the history
    NSError *error = nil;
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PSongLastPlayed" inManagedObjectContext:moc];
    [request setEntity:entity];
    [request setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", [history valueForKeyPath:@"objectID"]]];
    error = nil;
    (void)[moc executeFetchRequest:request error:&error];
    
    NSMutableDictionary *entry;
    NSManagedObject *obj;
    NSEnumerator *en = [history objectEnumerator];
    while ((obj = [en nextObject])) {
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [obj valueForKey:@"lastPlayed"], @"lastPlayed",
            [obj objectID], @"oid",
            nil];
        [content addObject:entry];
    }
    
    NSNumberFormatter *format = [[[NSNumberFormatter alloc] init] autorelease];
    [format setNumberStyle:NSNumberFormatterDecimalStyle];
    
    NSNumberFormatter *pctFormat = [[[NSNumberFormatter alloc] init] autorelease];
    [pctFormat setNumberStyle:NSNumberFormatterPercentStyle];
    [pctFormat setMaximumFractionDigits:2];
    
    PersistentSessionManager *psm = [[[TopListsController sharedInstance] persistence] sessionManager];
    id session = [psm sessionWithName:@"all" moc:moc];
    double totalSongs = session ? [[session valueForKey:@"playCount"] doubleValue] : 0.0;
    double artistCount = [[song valueForKeyPath:@"artist.playCount"] doubleValue];
    
    [totalPlayCount setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%@ of %@", "play counts"),
        [[historyController arrangedObjects] valueForKey:@"@count"],
        [song valueForKey:@"playCount"]]];
    [totalPlayCount setToolTip:[NSString stringWithFormat:@"%@: %@ (%@)",
        NSLocalizedString(@"Artist Plays", ""),
        [format stringFromNumber:[song valueForKeyPath:@"artist.playCount"]],
        [pctFormat stringFromNumber:[NSNumber numberWithDouble:artistCount/totalSongs]]
        ]];
    
    [moc reset];
    
    [historyController rearrangeObjects];
    
    [progress stopAnimation:nil];
    
    (void)[trackInfo retain];
    currentTrackInfo = trackInfo;
    
    // restore the NP info after a short period
    if (npTrackInfo && npTrackInfo != trackInfo && !editMode) {
        [self performSelector:@selector(loadHistoryForTrack:) withObject:npTrackInfo afterDelay:30.0];
    }
}

- (IBAction)addHistoryEvent:(id)sender
{
    if (currentTrackInfo) {
        DBEditController *ec = [[DBAddHistoryController alloc] init]; // released when closed by self
        [ec setObject:currentTrackInfo];
        [ec showWindow:nil];
    } else
        NSBeep();
}

- (IBAction)removeHistoryEvent:(id)sender
{
    NSArray *selection = [historyController selectedObjects];
    if (currentTrackInfo && [selection count] == 1) {
        PersistentProfile *persistence = [[TopListsController sharedInstance] valueForKey:@"persistence"];
        [persistence removeHistoryEvent:[[selection objectAtIndex:0] objectForKey:@"oid"]
            forObject:[currentTrackInfo objectForKey:@"objectID"]];
    } else
        NSBeep();
}

- (void)persistentProfileDidEditObject:(NSNotification*)note
{
    NSManagedObjectID *oid = [[note userInfo] objectForKey:@"oid"];
    if (currentTrackInfo && [oid isEqualTo:[currentTrackInfo objectForKey:@"objectID"]]) {
        NSManagedObject *obj = [moc objectRegisteredForID:oid];
        [obj refreshSelf];
        
        @try {
        
        NSString *what = [[note userInfo] objectForKey:@"what"];
        if (!what || NO == [what isEqualToString:@"remove"]) {
            [self loadHistoryForTrack:[[currentTrackInfo retain] autorelease]];
        } else {
            NSMutableDictionary *trackInfo = [[currentTrackInfo mutableCopy] autorelease];
            [trackInfo removeObjectForKey:@"objectID"];
            [self loadHistoryForTrack:trackInfo];
        }
        
        } @catch (NSException *e) {
            ScrobDebug(@"exception: %@", e);
        }
    }
}

- (void)keyDown:(NSEvent*)event
{
    NSString *chars = [event charactersIgnoringModifiers];
    unichar ch = [chars length] == 1 ? [chars characterAtIndex:0] : 0;
    switch (ch) {
        case NSF1FunctionKey:
            editMode = !editMode;
            NSString *title = [[self window] title];
            if (editMode) {
                title = [NSString stringWithFormat:@"%C %@", 0x270E, title ? title : @""];
                [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadHistoryForTrack:) object:npTrackInfo];
            } else {
                if (npTrackInfo) {
                    [self loadHistoryForTrack:npTrackInfo];
                    break;
                }
                
                if ([title hasPrefix:[NSString stringWithFormat:@"%C ", 0x270E]])
                    title = [title length] > 2 ? [title substringFromIndex:2] : @"";
            }
            [[self window] setTitle:title];
        break;
        default:
            return;
        break;
    }
}

- (NSColor*)textFieldColor
{
    #if 0
    return (([[self window] styleMask] & NSHUDWindowMask) ? [NSColor lightGrayColor] : [NSColor blackColor]);
    #endif
    // window may not be set when the binding calls us
    return ([NSColor lightGrayColor]);
}

@end
