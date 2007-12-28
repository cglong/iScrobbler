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

@implementation PlayHistoryController

- (id)init
{
    self = [super initWithWindowNibName:@"PlayHistory"];
    return (self);
}

- (void)awakeFromNib
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:[contentView frame]
        styleMask:NSTitledWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask|NSResizableWindowMask
        backing:NSBackingStoreBuffered defer:NO];
    [w setReleasedWhenClosed:YES];
    [w setContentView:contentView];
    [w setMinSize:[contentView frame].size];
    
    [self setWindow:w];
    [w autorelease];
    
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
    if (sender)
        [NSApp beginSheet:[self window] modalForWindow:sender modalDelegate:self didEndSelector:nil contextInfo:nil];
    else
        [super showWindow:nil];
    
}

- (void)closeWindow
{
    if ([[self window] isSheet])
        [NSApp endSheet:[self window]];
    [[self window] close];
    
    [moc release];
    moc = nil;
    [self autorelease];
}

- (IBAction)performClose:(id)sender
{
    [self closeWindow];
}

- (void)loadHistoryForTrack:(NSDictionary*)trackInfo
{
    [[self window] setTitle:[NSString stringWithFormat:@"%@ - %@",
        [trackInfo objectForKey:@"Artist"], [trackInfo objectForKey:@"Track"]]];
    
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
