//
//  DBEditController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/05/08.
//  Copyright 2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import "iScrobblerController.h"
#import "DBEditController.h"
#import "TopListsController.h"
#import "Persistence.h"
#import "PersistentSessionManager.h"

@implementation DBEditController

- (BOOL)isBusy
{
    return (isBusy);
}

- (void)setIsBusy:(BOOL)busy
{
    isBusy = busy;
}

- (void)awakeFromNib
{
    NSUInteger style = NSTitledWindowMask|NSClosableWindowMask|NSUtilityWindowMask;
    if ([self isKindOfClass:[DBRemoveController class]])
        style |= NSResizableWindowMask;
    LEOPARD_BEGIN
    // this does not affect some of the window subviews (NSTableView) - how do we get HUD style controls?
    style |= NSHUDWindowMask;
    LEOPARD_END
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
    if ([self isKindOfClass:[DBRenameController class]])
        [self setWindowFrameAutosaveName:@"DBEdit"]; // legacy
    else
        [self setWindowFrameAutosaveName:NSStringFromClass([self class])];
    
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
        
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileDidEditObject:)
            name:PersistentProfileDidEditObject
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(persistentProfileFailedEditObject:)
            name:PersistentProfileFailedEditObject
            object:nil];
    }
    [super showWindow:sender];
}

- (IBAction)performClose:(id)sender
{
    [[self window] close];
}

- (BOOL)windowShouldClose:(NSNotification*)note
{
    if (NO == [self isBusy] || nil == moid)
        return ([self scrobWindowShouldClose]);
    else
        NSBeep();
    return (NO);
}

- (void)windowWillClose:(NSNotification*)note
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:PersistentProfileDidEditObject object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:PersistentProfileFailedEditObject object:nil];
    
    [moc release];
    moc = nil;
    
    [moid release];
    moid = nil;
    [self autorelease];
}

- (NSString*)operationDescription
{
    NSString *op;
    if ([self isKindOfClass:[DBRemoveController class]]) {
        op = NSLocalizedString(@"Delete", "");
    } else if ([self isKindOfClass:[DBRenameController class]]) {
        op = NSLocalizedString(@"Rename", "");
    } else {
        op = nil;
        ISASSERT(0, "invalid class!");
    }
    return (op);
}

- (void)setWindowTitle:(NSString*)newTitle
{    
    [[self window] setTitle:[[self operationDescription] stringByAppendingFormat:@": %@", newTitle]];
}

- (void)setObject:(NSDictionary*)objectInfo
{
    ISASSERT(moid == nil, "calling set twice!");
    moid = [[objectInfo objectForKey:@"objectID"] retain];
    if (!moid) {
        NSBeep();
        return;
    }
    
    NSString *title = [objectInfo objectForKey:@"Track"];
    if (title)
        title = [NSString stringWithFormat:@"%@ - %@", [objectInfo objectForKey:@"Artist"], title];
    else
        title = [objectInfo objectForKey:@"Artist"];

    [self setWindowTitle:title];
}

- (void)persistentProfileFailedEditObject:(NSNotification*)note
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread isMainThread], "!mainThread!");
    #endif
    
    NSManagedObjectID *oid = [[note userInfo] objectForKey:@"oid"];
    if (NO == [oid isEqualTo:moid])
        return;
    
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"isBusy"];
    NSBeep();
    [[NSApp delegate] displayErrorWithTitle:[self operationDescription]
        message:[[[note userInfo] objectForKey:NSUnderlyingErrorKey] localizedDescription]];
}

- (NSColor*)textEditorColor
{
    #if 0
    return (([[self window] styleMask] & NSHUDWindowMask) ? [NSColor darkGrayColor] : [NSColor blackColor]);
    #endif
    // window may not be set when the binding calls us
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    return ([NSColor darkGrayColor]);
    #else
    return ((floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_4) ? [NSColor darkGrayColor] : [NSColor blackColor]);
    #endif
}

@end

@implementation DBRenameController

- (id)init
{
    self = [super initWithWindowNibName:@"DBRename"];
    return (self);
}

- (IBAction)showWindow:(id)sender
{
    NSManagedObject *obj = [moc objectWithID:moid];
    [renameText setStringValue:[obj valueForKey:@"name"]];
    
    [super showWindow:sender];
}

- (IBAction)performRename:(id)sender
{
    [[self window] endEditingFor:nil];
    
    NSString *newTitle = [renameText stringValue];
    if (!moid || !newTitle || 0 == [newTitle length]) {
        NSBeep();
        return;
    }
    
    [self setValue:[NSNumber numberWithBool:YES] forKey:@"isBusy"];
    PersistentProfile *persistence = [[TopListsController sharedInstance] valueForKey:@"persistence"];
    [persistence rename:moid to:newTitle];
}

- (void)persistentProfileDidEditObject:(NSNotification*)note
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread isMainThread], "!mainThread!");
    #endif
    
    NSManagedObjectID *oid = [[note userInfo] objectForKey:@"oid"];
    if (NO == [oid isEqualTo:moid])
        return;
    
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"isBusy"];
    
    @try {
    
    PersistentProfile *persistence = [[TopListsController sharedInstance] valueForKey:@"persistence"];
    NSManagedObject *obj = [moc objectWithID:oid];
    [obj refreshSelf]; // make sure we don't have any cached values
    
    NSString *title;
    if ([persistence isSong:obj]) {
        title = [NSString stringWithFormat:@"%@ - %@", [obj valueForKeyPath:@"artist.name"], [obj valueForKey:@"name"]];
    } else if ([persistence isArtist:obj]) {
        title = [obj valueForKey:@"name"];
    } else {
        title = @"!!INVALID TYPE!!";
        ISASSERT(0, "invalid object type!");
    }
    [self setWindowTitle:title];
    
    } @catch (NSException *e) {
        ScrobTrace(@"exception: %@", e);
    }
}

@end

@implementation DBRemoveController

- (id)init
{
    self = [super initWithWindowNibName:@"DBRemove"];
    return (self);
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    if ([[playEvents content] count])
        [playEvents removeObjects:[playEvents content]];
        
    // Setup our sort descriptors
    NSSortDescriptor *byDate = [[NSSortDescriptor alloc] initWithKey:@"playDate" ascending:NO];
    [playEvents setSortDescriptors:[NSArray arrayWithObjects:byDate, nil]];
}

- (void)setObject:(NSDictionary*)objectInfo
{
    [super setObject:objectInfo];
    
    ISASSERT(playEventsContent == nil, "setObject called twice!");
    playEventsContent = [[NSMutableArray alloc] init];
    
    NSManagedObjectID *mid;
    NSEnumerator *en = [[objectInfo objectForKey:@"sessionInstanceIDs"] objectEnumerator];
    while ((mid = [en nextObject])) {
        NSManagedObject *mobj = [moc objectWithID:mid];
        if ([[mobj valueForKeyPath:@"session.name"] isEqualToString:@"all"])
            break;
        
        NSDate *played = [NSDate dateWithTimeIntervalSince1970:
            [[mobj valueForKey:@"submitted"] timeIntervalSince1970] + [[mobj valueForKeyPath:@"item.duration"] unsignedIntValue]];
        
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            played, @"playDate",
            mid, @"mobjectID",
            nil];
        [playEventsContent addObject:entry];
    }
}

- (void)windowWillClose:(NSNotification*)note
{
    [playEvents setContent:[NSMutableArray array]];
    [playEventsContent release];
    playEventsContent = nil;
    
    [super windowWillClose:note];
}

- (IBAction)showWindow:(id)sender
{
    if (![[self window] isVisible]) {
        [playEvents setContent:playEventsContent];
        [playEvents rearrangeObjects];
    }
    
    [super showWindow:sender];
}

#define REM_PLAY_TAG 1
#define REM_SONG_TAG 2
- (IBAction)performRemove:(id)sender
{
    NSManagedObjectID *mid;
    if (REM_PLAY_TAG == [sender tag]) {
        NSArray *so = [playEvents selectedObjects];
        playEventBeingRemoved = [so count] > 0 ? [so objectAtIndex:0] : nil;
        mid = [playEventBeingRemoved valueForKey:@"mobjectID"];
    } else
        mid = moid;
        
    if (!mid) {
        NSBeep();
        return;
    }
        
    [self setValue:[NSNumber numberWithBool:YES] forKey:@"isBusy"];
    PersistentProfile *persistence = [[TopListsController sharedInstance] valueForKey:@"persistence"];
    [persistence removeObject:mid];
}

- (void)persistentProfileDidEditObject:(NSNotification*)note
{
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
    ISASSERT([NSThread isMainThread], "!mainThread!");
    #endif
    
    NSManagedObjectID *oid = [[note userInfo] objectForKey:@"oid"];
    if (NO == [oid isEqualTo:moid]) {
        if (!playEventBeingRemoved || NO == [oid isEqualTo:[playEventBeingRemoved objectForKey:@"mobjectID"]])
            return;
    }
    
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"isBusy"];
    
    @try {
    
    NSManagedObject *obj = [moc objectWithID:oid];
    [obj refreshSelf];
    if ([oid isEqualTo:moid]) {
        // deleted the entire song
        [moid release];
        moid = nil;
        playEventBeingRemoved = nil;
        [playEvents setContent:[NSMutableArray array]];
        [self setValue:[NSNumber numberWithBool:YES] forKey:@"isBusy"];
        NSString *title = [[self window] title];
        [[self window] setTitle:[NSString stringWithFormat:@"[%@] %@", NSLocalizedString(@"Deleted", ""), title]];
        return;
    } else {
        [playEvents removeObject:playEventBeingRemoved];
        [playEvents rearrangeObjects];
        playEventBeingRemoved = nil;
    }

    } @catch (NSException *e) {
        ScrobTrace(@"exception: %@", e);
    }
}
    
@end
