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

- (id)init
{
    self = [super initWithWindowNibName:@"DBEdit"];
    return (self);
}

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
    LEOPARD_BEGIN
    // this does not affect some of the window subviews (NSTableView) - how do we get HUD style controls?
    style |= NSHUDWindowMask;
    LEOPARD_END
    NSWindow *w = [[NSPanel alloc] initWithContentRect:[renameView frame] styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [w setHidesOnDeactivate:NO];
    [w setLevel:NSNormalWindowLevel];
    if (0 == (style & NSHUDWindowMask))
        [w setAlphaValue:IS_UTIL_WINDOW_ALPHA];
    
    [w setReleasedWhenClosed:NO];
    [w setContentView:renameView];
    [w setMinSize:[renameView frame].size];
    
    [self setWindow:w];
    [w setDelegate:self]; // setWindow: does not do this for us (why?)
    [w autorelease];
    [self setWindowFrameAutosaveName:@"DBEdit"];
    
    moc = [[NSManagedObjectContext alloc] init];
    [moc setUndoManager:nil];
    // we don't allow the user to make changes and the session mgr background thread handles all internal changes
    [moc setMergePolicy:NSRollbackMergePolicy];
    
    PersistentProfile *persistence = [[TopListsController sharedInstance] valueForKey:@"persistence"];
    id psc = [[persistence performSelector:@selector(mainMOC)] persistentStoreCoordinator];
    [moc setPersistentStoreCoordinator:psc];
}

- (IBAction)showRenameWindow:(id)sender
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
    NSManagedObject *obj = [moc objectWithID:moid];
    [renameText setStringValue:[obj valueForKey:@"name"]];
    [super showWindow:nil];
}

- (IBAction)performClose:(id)sender
{
    [[self window] close];
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

- (BOOL)windowShouldClose:(NSNotification*)note
{
    if (NO == [self isBusy])
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

- (void)setRenameTitle:(NSString*)newTitle
{
    [[self window] setTitle:[NSLocalizedString(@"Rename", "") stringByAppendingFormat:@": %@", newTitle]];
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

    [self setRenameTitle:title];
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
    #if ISDEBUG
        ISASSERT(0, "invalid object type!");
    #endif
    }
    [self setRenameTitle:title];
    
    } @catch (NSException *e) {
        ScrobTrace(@"exception: %@", e);
    }
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
    [[NSApp delegate] displayErrorWithTitle:NSLocalizedString(@"Rename Failed", "")
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
