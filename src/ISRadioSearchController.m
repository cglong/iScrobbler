//
//  ISRadioSearchController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/20/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISRadioSearchController.h"
#import "ISRadioController.h"
#import "LNSSourceListView.h"
#import "ASXMLFile.h"
#import "ASWebServices.h"

@implementation ISRadioSearchController

- (void)tuneStation:(id)selection
{
    NSString *url = [selection valueForKeyPath:@"radioURL"];
    if (url)
        [[ISRadioController sharedInstance] tuneStationWithName:[selection valueForKeyPath:@"name"] url:url];
}

- (BOOL)textView:(NSTextView*)textView clickedOnLink:(id)link atIndex:(unsigned)charIndex
{
    BOOL handled = NO;
    ScrobDebug(@"%@", link);
    @try {
    if ([link isKindOfClass:[NSDictionary class]]) {
        if ([link objectForKey:@"radioURL"]) {
            [self tuneStation:link];
            handled = YES;
        } else
            handled = [[NSWorkspace sharedWorkspace] openURL:[link objectForKey:@"url"]];
    }
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception attempting to open: %@", link); 
    }
    return (handled);
}

+ (ISRadioSearchController*)sharedController
{
    static ISRadioSearchController *shared = nil;
    return (shared ? shared : (shared = [[ISRadioSearchController alloc] init]));
}

- (IBAction)search:(id)sender
{
    NSString *searchFor = [searchText stringValue];
    if (!searchFor || ![searchFor length])
        return;
    [searchButton setEnabled:NO];
    [searchProgress startAnimation:nil];
}

- (void)showSearchPanel:(id)selection
{
    NSView *cview = [[splitView subviews] objectAtIndex:1];
    if (searchView != cview) {
        [searchView setFrame:[cview frame]];
        [splitView replaceSubview:cview with:searchView];
    }
    
    [searchText setStringValue:@""];
    [searchButton setEnabled:YES];
    [searchProgress stopAnimation:nil];
}

- (void)showUserPanel:(id)selection
{
    ASWebServices *ws = [ASWebServices sharedInstance];
    NSView *cview = [[splitView subviews] objectAtIndex:1];
    NSTextView *v = [[NSTextView alloc] initWithFrame:[cview frame]];
    [v setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [v setEditable:NO];
    [v setSelectable:YES];
    [v setSelectable:YES];
    [v setDelegate:self];
    
    NSFont *font = [[NSFontManager sharedFontManager] convertFont:[NSFont userFontOfSize:[NSFont systemFontSize]] toHaveTrait:NSBoldFontMask];
    NSColor *textColor = [NSColor blueColor];
    NSCursor *urlCursor = [NSCursor pointingHandCursor];
    NSNumber *underline = [NSNumber numberWithInt:1];
    NSMutableAttributedString *value, *tmp, *newline;
    NSString *prompt, *name;
    NSDictionary *urlspec;
    
    name = [selection objectForKey:@"name"];
    value = [[[NSMutableAttributedString alloc] initWithString:@"" attributes:nil] autorelease];
    newline = [[[NSMutableAttributedString alloc] initWithString:@"\n\n" attributes:nil] autorelease];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Play %@'s Radio", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [ws station:@"personal" forUser:name], @"radioURL",
        [NSString stringWithFormat:NSLocalizedString(@"%@'s Radio", ""), name], @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"radioURL"], NSToolTipAttributeName,
                underline, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Play %@'s Loved Tracks", ""), name]; // sub only
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [ws station:@"loved" forUser:name], @"radioURL",
        [NSString stringWithFormat:NSLocalizedString(@"%@'s Loved Tracks", ""), name], @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"radioURL"], NSToolTipAttributeName,
                underline, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Play %@'s Neighborhood", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [ws station:@"neighbours" forUser:name], @"radioURL",
        [NSString stringWithFormat:NSLocalizedString(@"%@'s Neighborhood", ""), name], @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"radioURL"], NSToolTipAttributeName,
                underline, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Open %@'s Profile", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [selection objectForKey:@"url"], @"url",
        @"", @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"url"], NSToolTipAttributeName,
                underline, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    [splitView replaceSubview:cview with:v];
    if ([v acceptsFirstResponder]) {
        BOOL x = [[self window] makeFirstResponder:v];
        ScrobDebug(@"v is firstResponder: %d", x);
    }
    [[v textStorage] setAttributedString:value];
    //[[self window] resetCursorRects];
    [v release];
}

- (void)showTagPanel:(id)selection
{
    ASWebServices *ws = [ASWebServices sharedInstance];
    NSView *cview = [[splitView subviews] objectAtIndex:1];
    NSTextView *v = [[NSTextView alloc] initWithFrame:[cview frame]];
    [v setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [v setEditable:NO];
    [v setSelectable:YES];
    [v setSelectable:YES];
    [v setDelegate:self];
    
    NSFont *font = [[NSFontManager sharedFontManager] convertFont:[NSFont userFontOfSize:[NSFont systemFontSize]] toHaveTrait:NSBoldFontMask];
    NSColor *textColor = [NSColor blueColor];
    NSCursor *urlCursor = [NSCursor pointingHandCursor];
    NSNumber *underline = [NSNumber numberWithInt:1];
    NSMutableAttributedString *value, *tmp, *newline;
    NSString *prompt, *name;
    NSDictionary *urlspec;
    
    name = [selection objectForKey:@"tagName"]; // @"name" contains the display name of "tag (count)"
    value = [[[NSMutableAttributedString alloc] initWithString:@"" attributes:nil] autorelease];
    newline = [[[NSMutableAttributedString alloc] initWithString:@"\n\n" attributes:nil] autorelease];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Play My Music Tagged as '%@'", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [ws tagStationForCurrentUser:name], @"radioURL",
        [NSString stringWithFormat:NSLocalizedString(@"My %@ Tag Radio", ""), name], @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"radioURL"], NSToolTipAttributeName,
                underline, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Play All Music Tagged as '%@'", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [ws globalTagStation:name], @"radioURL",
        [NSString stringWithFormat:NSLocalizedString(@"%@ Tag Radio", ""), name], @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"radioURL"], NSToolTipAttributeName,
                underline, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Open '%@' Tag Page", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [selection objectForKey:@"url"], @"url",
        @"", @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"url"], NSToolTipAttributeName,
                underline, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    [splitView replaceSubview:cview with:v];
    if ([v acceptsFirstResponder]) {
        BOOL x = [[self window] makeFirstResponder:v];
        ScrobDebug(@"v is firstResponder: %d", x);
    }
    [[v textStorage] setAttributedString:value];
    //[[self window] resetCursorRects];
    [v release];
}

- (void)tuneHistory:(id)selection
{
    NSView *cview = [[splitView subviews] objectAtIndex:1];
    if (cview != placeholderView) {
        [placeholderView setFrame:[cview frame]];
        [splitView replaceSubview:cview with:placeholderView];
    }
    [self tuneStation:selection];
}

- (void)selectionDidChange:(NSNotification*)note
{
    @try {
    NSArray *all = [sourceListController selectedObjects];
    if (![all count])
        return;
    id selection = [all objectAtIndex:0];
    SEL method = NSSelectorFromString([selection objectForKey:@"action"]);
    if (method)
        [self performSelector:method withObject:selection];
    } @catch (id e) {
        ScrobDebug(@"%@", e);
    }
}

- (void)radioHistoryDidUpdate:(NSNotification*)note
{
    id obj = [(ISRadioController*)[note object] history];
    if (!obj)
        return;
    
    NSMutableArray *h = (NSMutableArray*)CFPropertyListCreateDeepCopy(kCFAllocatorDefault,
        obj, kCFPropertyListMutableContainers);
    NSMutableDictionary *d;
    NSEnumerator *en = [h objectEnumerator];
    NSString *action = NSStringFromSelector(@selector(tuneHistory:));
    while ((d = [en nextObject])) {
        [d setObject:action forKey:@"action"];
    }
    
    [history setValue:h forKey:@"children"];
    [h release];
}

- (void)updateUsers:(id)users withChildren:(NSArray*)children
{
    // the members contain NSURL instances, which are not plist values, so
    // CFPropertyListCreateDeepCopy() will fail
    NSMutableArray *u = [[NSMutableArray alloc] initWithCapacity:[children count]];
    
    NSMutableDictionary *d;
    NSEnumerator *en = [children objectEnumerator];
    NSString *action = NSStringFromSelector(@selector(showUserPanel:));
    while ((d = [[en nextObject] mutableCopy])) {
        [d setObject:action forKey:@"action"];
        [u addObject:d];
        [d release];
    }
    
    [users setValue:u forKey:@"children"];
    [u release];
}

- (void)friendsDidUpdate:(NSArray*)users
{
    [self updateUsers:friends withChildren:users];
}

- (void)neighborsDidUpdate:(NSArray*)users
{
    [self updateUsers:neighbors withChildren:users];
}

- (void)tagsDidUpdate:(NSArray*)mytags
{
    // the members contain NSURL instances, which are not plist values, so
    // CFPropertyListCreateDeepCopy() will fail
    NSMutableArray *t = [[NSMutableArray alloc] initWithCapacity:[mytags count]];
    
    NSMutableDictionary *d;
    NSEnumerator *en = [mytags objectEnumerator];
    NSString *action = NSStringFromSelector(@selector(showTagPanel:));
    NSString *name;
    while ((d = [[en nextObject] mutableCopy])) {
        [d setObject:[d objectForKey:@"name"] forKey:@"tagName"]; // save for use in generating URLs
        name = [NSString stringWithFormat:@"%@ (%@)", [d objectForKey:@"name"], [d objectForKey:@"count"]];
        [d setObject:name forKey:@"name"];
        [d setObject:action forKey:@"action"];
        [t addObject:d];
        [d release];
    }
    
    [tags setValue:t forKey:@"children"];
    [t release];
}

- (void)releaseConnection:(id)connection
{
    if (connection == friendsConn) {
        [friendsConn autorelease];
        friendsConn = nil;
    } else if (connection == neighborsConn) {
        [neighborsConn autorelease];
        neighborsConn = nil;
    } else if (connection == tagsConn) {
        [tagsConn autorelease];
        tagsConn = nil;
    }
    
    static int initState = 1;
    
    if (initState && !friendsConn && !neighborsConn && !tagsConn) {
        // restore source list expansion state after all initial data has loaded
        initState = 0;
        [self performSelector:@selector(restoreSourceListState) withObject:nil afterDelay:0.0];
    }
}

- (void)xmlFileDidFinishLoading:(ASXMLFile *)connection
{
    if (connection == friendsConn) {
        [self friendsDidUpdate:[connection users]];
    } else if (connection == neighborsConn) {
        [self neighborsDidUpdate:[connection users]];
    } else if (connection == tagsConn) {
        [self tagsDidUpdate:[connection tags]];
    }
    
    [self releaseConnection:connection];
}

-(void)xmlFile:(ASXMLFile *)connection didFailWithError:(NSError *)reason
{
    [self releaseConnection:connection];
}

- (void)initConnections
{
    [friendsConn cancel];
    [friendsConn release];
    friendsConn = [[ASXMLFile xmlFileWithURL:[ASWebServices currentUserFriendsURL] delegate:self cachedForSeconds:600] retain];
    
    [neighborsConn cancel];
    [neighborsConn release];
    neighborsConn = [[ASXMLFile xmlFileWithURL:[ASWebServices currentUserNeighborsURL] delegate:self cachedForSeconds:600] retain];
    
    [tagsConn cancel];
    [tagsConn release];
    tagsConn = [[ASXMLFile xmlFileWithURL:[ASWebServices currentUserTagsURL] delegate:self cachedForSeconds:600] retain];
}

- (void)initSourceList
{
    static int initList = 1;
    
    if (!initList)
        return;
    
    initList = 0;
    
    NSNumber *yes = [NSNumber numberWithBool:YES];
    NSNumber *no = [NSNumber numberWithBool:NO];
    NSString *title;
    
    title = NSLocalizedString(@"Search", "");
    NSString *action = NSStringFromSelector(@selector(showSearchPanel:));
    search = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        yes,  @"isSourceGroup",
        title, @"name",
        [NSMutableArray arrayWithObjects:
            [NSMutableDictionary dictionaryWithObjectsAndKeys:
                NSLocalizedString(@"Artists", ""), @"name",
                yes, @"artistSearch",
                action,  @"action",
                nil],
            [NSMutableDictionary dictionaryWithObjectsAndKeys:
                NSLocalizedString(@"Tags", ""), @"name",
                no, @"artistSearch",
                action,  @"action",
                nil],
            nil], @"children",
        nil];
    [sourceListController addObject:search];
    
    title = [NSString stringWithFormat:@"%C %@", 0x270E, NSLocalizedString(@"My Tags", "")];
    tags = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        yes,  @"isSourceGroup",
        title, @"name",
        [NSMutableArray array], @"children",
        nil];
    [sourceListController addObject:tags];
    
    title = [NSString stringWithFormat:@"%C %@", 0x2605, NSLocalizedString(@"My Friends", "")];
    friends = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        yes,  @"isSourceGroup",
        title, @"name",
        [NSMutableArray array], @"children",
        nil];
    [sourceListController addObject:friends];
    
    title = [NSString stringWithFormat:@"%C %@", 0x2606, NSLocalizedString(@"My Neighbors", "")];
    neighbors = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        yes,  @"isSourceGroup",
        title, @"name",
        [NSMutableArray array], @"children",
        nil];
    [sourceListController addObject:neighbors];
    
    // 0x221E == infinity, 0x25D4 = quarter filled circle (doesn't look right for some reason)
    title = [NSString stringWithFormat:@"%C %@", 0x221E, NSLocalizedString(@"History", "")];
    history = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        yes,  @"isSourceGroup",
        title, @"name",
        [NSMutableArray array], @"children",
        nil];
    [sourceListController addObject:history];
    
    [self radioHistoryDidUpdate:
        [NSNotification notificationWithName:ISRadioHistoryDidUpdateNotification object:[ISRadioController sharedInstance]]];
}

- (void)restoreSourceListState
{
    @try {
    
    NSArray *state = [[NSUserDefaults standardUserDefaults] objectForKey:@"RadioSourceListExpansionState"];
    int count;
    if (state && (count = [state count]) == [sourceList numberOfRows]) {
        id item;
        for (int i = 0; i < count; ++i) {
            item = [sourceList itemAtRow:i];
            if (0 == [sourceList levelForItem:item] && [[state objectAtIndex:i] boolValue])
                [sourceList expandItem:item];
        }
    } 
    
    } @catch (id e){}
}

- (void)saveSourceListState
{
    int count = [sourceList numberOfRows];
    NSMutableArray *state = [NSMutableArray arrayWithCapacity:count];
    id item;
    for (int i = 0; i < count; ++i) {
        item = [sourceList itemAtRow:i];
        if (0 == [sourceList levelForItem:item])
            [state addObject:[NSNumber numberWithBool:[sourceList isItemExpanded:item]]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:state forKey:@"RadioSourceListExpansionState"];
}

- (IBAction)showWindow:(id)sender
{
    if (![[self window] isVisible]) {
        [self initSourceList];
        
        [sourceList deselectAll:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(radioHistoryDidUpdate:)
            name:ISRadioHistoryDidUpdateNotification object:nil];
    }
    [super showWindow:sender];
    [self performSelector:@selector(initConnections) withObject:nil afterDelay:0.0];
}

- (void)windowDidLoad
{
    // retain our views so we don't lose them when they are replaced
    (void)[placeholderView retain];
    (void)[searchView retain];
    
    [[self window] setTitle:
        [@"iScrobbler: " stringByAppendingString:NSLocalizedString(@"Find a Radio Station", "")]];
    [splitView setDelegate:self];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectionDidChange:)
            name:NSOutlineViewSelectionDidChangeNotification object:sourceList];
}

- (void)windowWillClose:(NSNotification*)note
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISRadioHistoryDidUpdateNotification object:nil];
    
    [searchProgress stopAnimation:nil];
    
    [friendsConn cancel];
    [friendsConn release];
    friendsConn = nil;
    [neighborsConn cancel];
    [neighborsConn release];
    neighborsConn = nil;
    [tagsConn cancel];
    [tagsConn release];
    tagsConn = nil;
    
    NSView *cview = [[splitView subviews] objectAtIndex:1];
    if (cview != placeholderView) {
        [placeholderView setFrame:[cview frame]];
        [splitView replaceSubview:cview with:placeholderView];
    }
    
    [self saveSourceListState];
}

- (void)awakeFromNib
{
    [super setWindowFrameAutosaveName:@"RadioSearch"];
    if ([[sourceListController content] count])
        [sourceListController setContent:[NSMutableArray array]];
}

- (id)init
{
    return ((self = [super initWithWindowNibName:@"ISRadioSearch"]));
}

#define SearchPanelMaxRatio 0.80
- (float)splitView:(NSSplitView *)sender constrainMaxCoordinate:(float)proposedMax ofSubviewAt:(int)offset
{
    if (0 == offset) {
        NSRect bounds = [sender bounds];
        proposedMax = bounds.size.width * SearchPanelMaxRatio;
    }
    return (proposedMax);
}

#define SourceListViewMin 150.0
- (float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedMin ofSubviewAt:(int)offset
{
    if (0 == offset) {
        proposedMin = SourceListViewMin;
    }
    return (proposedMin);
}

- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
	NSArray *views = [sender subviews];
	[sender adjustSubviews];
	NSView *left = [views objectAtIndex:0];
	NSView *right = [views objectAtIndex:1];
	NSRect bounds = [left frame];
	if (bounds.size.width < SourceListViewMin) {
		float diff = SourceListViewMin - bounds.size.width;
		bounds.size.width = SourceListViewMin;
		[left setFrame:bounds];
		bounds = [right bounds];
		bounds.size.width -= diff;
		[right setFrame:bounds];
	}
}

#ifdef notyet
- (void)dealloc
{
    [super dealloc];
}
#endif

// Singleton support
- (id)copyWithZone:(NSZone *)zone
{
    return (self);
}

- (id)retain
{
    return (self);
}

- (unsigned)retainCount
{
    return (UINT_MAX);  //denotes an object that cannot be released
}

- (void)release
{
}

- (id)autorelease
{
    return (self);
}

@end
