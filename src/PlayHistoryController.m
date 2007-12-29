//
//  PlayHistoryController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/28/07.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "PlayHistoryController.h"
#import "TopListsController.h"
#import "Persistence.h"

#define TABLE_ID 9999
#define OKBUTTON_ID 10000

static PlayHistoryController *sharedController = nil;

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
    LEOPARD_BEGIN
    // this does not affect some of the window subviews (NSTableView) - how do we get HUD style controls?
    style |= NSHUDWindowMask;
    LEOPARD_END
    NSWindow *w = [[NSPanel alloc] initWithContentRect:[contentView frame] styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [w setHidesOnDeactivate:NO];
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
    [super showWindow:nil];
}

- (IBAction)performClose:(id)sender
{
    [[self window] close];
}

- (BOOL)windowShouldClose:(NSNotification*)note
{
    [[self window] fadeOutAndClose];
    return (NO);
}

- (void)windowWillClose:(NSNotification*)note
{
    [moc release];
    moc = nil;
    
    ISASSERT(sharedController == self, "sharedController does not match!");
    sharedController = nil;
    [self autorelease];
}

- (void)loadHistoryForTrack:(NSDictionary*)trackInfo
{
    [[self window] setTitle:[NSString stringWithFormat:@"%@ - %@ %@",
        [trackInfo objectForKey:@"Artist"], [trackInfo objectForKey:@"Track"], NSLocalizedString(@"History", "")]];
    
    NSMutableArray *content = [NSMutableArray array];
    [historyController setContent:content];
    
    NSManagedObjectID *mid = [trackInfo objectForKey:@"objectID"];
    if (!mid) {
        NSBeep();
        return;
    }
    
    [progress startAnimation:nil];
    
    NSSet *history = [[moc objectWithID:mid] valueForKey:@"playHistory"];
    
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
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:[obj valueForKey:@"lastPlayed"], @"lastPlayed", nil];
        [content addObject:entry];
    }
    
    [moc reset];
    
    [historyController addObjects:content];
    [historyController rearrangeObjects];
    
    [progress stopAnimation:nil];
}

@end
