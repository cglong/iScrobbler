//
//  ISRadioSearchController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/20/2007.
//  Copyright 2007,2008 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import <QuartzCore/QuartzCore.h>

#import "ISRadioSearchController.h"
#import "ISRadioController.h"
#import "ASXMLFile.h"
#import "ASWebServices.h"
#import "ISBusyView.h"

// XXX: We don't atually search for anything currently, for now we just attempt to play what every the user enters
#define PLAY_NOT_SEARCH

@implementation ISRadioSearchController

- (void)tuneStation:(id)selection
{
    NSString *url = [selection valueForKeyPath:@"radioURL"];
    if (url)
        [[ISRadioController sharedInstance] tuneStationWithName:[selection valueForKeyPath:@"name"] url:url];
}

- (BOOL)textView:(NSTextView*)textView clickedOnLink:(id)url atIndex:(NSUInteger)charIndex
{
    BOOL handled = NO;
    ScrobDebug(@"%@", url);
    @try {
    if ([url isKindOfClass:[NSDictionary class]]) {
        if ([url objectForKey:@"radioURL"]) {
            [self tuneStation:url];
            handled = YES;
        } else
            handled = [[NSWorkspace sharedWorkspace] openURL:[url objectForKey:@"url"]];
    }
    } @catch (id e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception attempting to open: %@", url); 
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
    if (!searchFor || ![searchFor length] || !currentSearchType) {
        NSBeep();
        return;
    }
    #ifndef PLAY_NOT_SEARCH
    [searchButton setEnabled:NO];
    [searchProgress startAnimation:nil];
    #endif
    
    ASWebServices *ws = [ASWebServices sharedInstance];
    NSString *url, *name;
    if ([currentSearchType objectForKey:@"artist"]) {
        url = [ws stationForArtist:searchFor];
        name = [NSString stringWithFormat:NSLocalizedString(@"%@ Artist Radio", ""), searchFor];
        if (![searchOption isHidden] && NSOnState == [searchOption state])
            url = [url stringByAppendingString:@"/fans"];
    } else if ([currentSearchType objectForKey:@"tag"]) {
        url = [ws stationForGlobalTag:searchFor];
        name = [NSString stringWithFormat:NSLocalizedString(@"%@ Tag Radio", ""), searchFor];
    } else if ([currentSearchType objectForKey:@"group"]) {
        url = [ws stationForGroup:searchFor];
        name = [NSString stringWithFormat:NSLocalizedString(@"%@ Group Radio", ""), searchFor];
    } else if ([currentSearchType objectForKey:@"user"]) {
        // display the user panel
        NSDictionary *user = [NSDictionary dictionaryWithObjectsAndKeys:
            searchFor, @"name",
            [NSURL URLWithString:[@"http://www.last.fm/user/" stringByAppendingString:searchFor]], @"url",
            nil];
        [self performSelector:@selector(showUserPanel:) withObject:user afterDelay:0.0];
        return;
    } else {
        NSBeep();
        return;
    }
    
    [self tuneStation:[NSDictionary dictionaryWithObjectsAndKeys:
        url, @"radioURL", name, @"name", nil]];
}

- (void)showSearchPanel:(id)selection
{
    NSView *cview = [[splitView subviews] objectAtIndex:1];
    if (searchView != cview) {
        [searchView setFrame:[cview frame]];
        [[splitView animator] replaceSubview:cview with:searchView];
    }
    
    currentSearchType = selection;
    
    NSString *name;
    if ([currentSearchType objectForKey:@"artist"]) {
        name = NSLocalizedString(@"Enter a Artist", "");
        [searchOption setTitle:NSLocalizedString(@"Play Artist Top Fans Radio", "")];
        [searchOption setHidden:NO];
    } else if ([currentSearchType objectForKey:@"tag"]) {
        name = NSLocalizedString(@"Enter a Tag", "");
    } else if ([currentSearchType objectForKey:@"group"]) {
        name = NSLocalizedString(@"Enter a Group", "");
    } else if ([currentSearchType objectForKey:@"user"]) {
        name = NSLocalizedString(@"Enter a Name", "");
    } else {
        NSBeep();
        return;
    }
    [[searchText cell] setPlaceholderString:name];
    
    [searchText setStringValue:@""];
    ISASSERT([currentSearchType objectForKey:@"buttonTitle"] != nil, "missing title!");
    [searchButton setTitle:[currentSearchType objectForKey:@"buttonTitle"]];
    [searchButton sizeToFit];
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
    LEOPARD_BEGIN
    [v setWantsLayer:YES];
    [v setAnimations:viewAnimations];
    LEOPARD_END
    
    NSFont *font = [NSFont userFontOfSize:[NSFont systemFontSize]];
    NSColor *textColor = [NSColor blueColor];
    NSCursor *urlCursor = [NSCursor pointingHandCursor];
    NSNumber *underlineStyle = [NSNumber numberWithInt:1];
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
                underlineStyle, NSUnderlineStyleAttributeName,
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
                underlineStyle, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Play %@'s Playlist", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [ws station:@"playlist" forUser:name], @"radioURL",
        [NSString stringWithFormat:NSLocalizedString(@"%@'s Playlist", ""), name], @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"radioURL"], NSToolTipAttributeName,
                underlineStyle, NSUnderlineStyleAttributeName,
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
                underlineStyle, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Play %@'s Recommendations", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [ws station:@"recommended" forUser:name], @"radioURL",
        [NSString stringWithFormat:NSLocalizedString(@"%@'s Recommendations", ""), name], @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"radioURL"], NSToolTipAttributeName,
                underlineStyle, NSUnderlineStyleAttributeName,
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
                underlineStyle, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    [[splitView animator] replaceSubview:cview with:v];
    if ([v acceptsFirstResponder]) {
        (void)[[self window] makeFirstResponder:v];
    }
    [[v textStorage] setAttributedString:value];
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
    LEOPARD_BEGIN
    [v setWantsLayer:YES];
    [v setAnimations:viewAnimations];
    LEOPARD_END
    
    NSFont *font = [NSFont userFontOfSize:[NSFont systemFontSize]];
    NSColor *textColor = [NSColor blueColor];
    NSCursor *urlCursor = [NSCursor pointingHandCursor];
    NSNumber *underlineStyle = [NSNumber numberWithInt:1];
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
                underlineStyle, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    prompt = [NSString stringWithFormat:NSLocalizedString(@"Play All Music Tagged as '%@'", ""), name];
    urlspec = [NSDictionary dictionaryWithObjectsAndKeys:
        [ws stationForGlobalTag:name], @"radioURL",
        [NSString stringWithFormat:NSLocalizedString(@"%@ Tag Radio", ""), name], @"name",
        nil];
    tmp = [[[NSMutableAttributedString alloc] initWithString:prompt attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                urlspec, NSLinkAttributeName,
                [urlspec objectForKey:@"radioURL"], NSToolTipAttributeName,
                underlineStyle, NSUnderlineStyleAttributeName,
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
                underlineStyle, NSUnderlineStyleAttributeName,
                textColor, NSForegroundColorAttributeName,
                urlCursor, NSCursorAttributeName,
            nil]] autorelease];
    [value appendAttributedString:newline];
    [value appendAttributedString:tmp];
    
    [[splitView animator] replaceSubview:cview with:v];
    if ([v acceptsFirstResponder]) {
        (void)[[self window] makeFirstResponder:v];
    }
    [[v textStorage] setAttributedString:value];
    [v release];
}

- (void)tuneHistory:(id)selection
{
    NSView *cview = [[splitView subviews] objectAtIndex:1];
    if (cview != placeholderView) {
        [placeholderView setFrame:[cview frame]];
        [[splitView animator] replaceSubview:cview with:placeholderView];
    }
    [self tuneStation:selection];
}

- (void)selectionDidChange:(NSNotification*)note
{
    currentSearchType = nil;
    [searchOption setHidden:YES];
    
    @try {
    NSArray *all = [sourceListController selectedObjects];
    if (![all count])
        return;
    id selection = [all objectAtIndex:0];
    SEL method = NSSelectorFromString([selection objectForKey:@"action"]);
    if (method)
        [self performSelector:method withObject:selection];
    NSNumber *deselect = [selection objectForKey:@"deselect"];
    if (deselect && [deselect boolValue])
        [sourceList performSelector:@selector(deselectAll:) withObject:nil afterDelay:0.38];
    } @catch (NSException *e) {
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
    NSNumber *yes = [NSNumber numberWithBool:YES];
    while ((d = [en nextObject])) {
        [d setObject:action forKey:@"action"];
        [d setObject:yes forKey:@"deselect"];
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
    NSString *title;
    
    #ifdef PLAY_NOT_SEARCH
    title = NSLocalizedString(@"Play a Station", "");
    #else
    title = NSLocalizedString(@"Search", "");
    #endif
    NSString *action = NSStringFromSelector(@selector(showSearchPanel:));
    search = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        yes,  @"isSourceGroup",
        title, @"name",
        [NSMutableArray arrayWithObjects:
            [NSMutableDictionary dictionaryWithObjectsAndKeys:
                NSLocalizedString(@"Artist", ""), @"name",
                yes, @"artist",
                action,  @"action",
                NSLocalizedString(@"Play", @""), @"buttonTitle",
                nil],
            [NSMutableDictionary dictionaryWithObjectsAndKeys:
                NSLocalizedString(@"Tag", ""), @"name",
                yes, @"tag",
                action,  @"action",
                NSLocalizedString(@"Play", @""), @"buttonTitle",
                nil],
            [NSMutableDictionary dictionaryWithObjectsAndKeys:
                NSLocalizedString(@"Group", ""), @"name",
                yes, @"group",
                action,  @"action",
                NSLocalizedString(@"Play", @""), @"buttonTitle",
                nil],
            [NSMutableDictionary dictionaryWithObjectsAndKeys:
                NSLocalizedString(@"User", ""), @"name",
                yes, @"user",
                action,  @"action",
                NSLocalizedString(@"Show Stations", @""), @"buttonTitle",
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
    NSUInteger count;
    if (state && (count = [state count]) == [sourceList numberOfRows]) {
        id item;
        for (NSUInteger i = 0, j = 0; i < count; ++i) {
            item = [sourceList itemAtRow:i];
            if (0 == [sourceList levelForItem:item]) {
                if ([[state objectAtIndex:j] boolValue])
                    // we delay this until the next event loop so the list count does not change on us in mid-loop
                    [sourceList performSelector:@selector(expandItem:) withObject:item afterDelay:0.0];
                ++j;
            }   
        }
    } 
    
    } @catch (id e){}
}

- (void)saveSourceListState
{
    NSUInteger count = [sourceList numberOfRows];
    NSMutableArray *state = [NSMutableArray arrayWithCapacity:count];
    id item;
    for (NSUInteger i = 0; i < count; ++i) {
        item = [sourceList itemAtRow:i];
        if (0 == [sourceList levelForItem:item])
            [state addObject:[NSNumber numberWithBool:[sourceList isItemExpanded:item]]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:state forKey:@"RadioSourceListExpansionState"];
}

- (void)radioBusyStateDidChange:(BOOL)windowClosing
{
    NSView *cview = [[self window] contentView];
    BOOL busy = [[ISRadioController sharedInstance] isBusy];
    BOOL busyShowing = nil != [busyView window];
    if (!busyShowing  && busy && !windowClosing) {
        [busyView setFrame:[cview frame]];
        [[cview animator] addSubview:busyView];
        LEOPARD_BEGIN
        [sourceList setEnabled:NO];
        LEOPARD_END
    } else if (busyShowing && (!busy || windowClosing)) {
        [[busyView animator] removeFromSuperview];
        LEOPARD_BEGIN
        [sourceList setEnabled:YES];
        LEOPARD_END
    }
}

- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([key isEqualToString:@"isBusy"]) {
        [self radioBusyStateDidChange:NO];
    }
}

- (IBAction)showWindow:(id)sender
{
    if (![[self window] isVisible]) {
        currentSearchType = nil;
        [self initSourceList];
        
        [sourceList deselectAll:nil];
        
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OPEN_FINDSTATIONS_WINDOW_AT_LAUNCH];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(radioHistoryDidUpdate:)
            name:ISRadioHistoryDidUpdateNotification object:nil];
        
        [self radioBusyStateDidChange:NO];
        [[ISRadioController sharedInstance] addObserver:self forKeyPath:@"isBusy" options:0 context:nil];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [super showWindow:sender];
    [self performSelector:@selector(initConnections) withObject:nil afterDelay:0.0];
}

- (void)windowDidLoad
{
    #ifdef PLAY_NOT_SEARCH
    [searchButton setTitle:NSLocalizedString(@"Play", "")];
    #endif

    // retain our views so we don't lose them when they are replaced
    (void)[placeholderView retain];
    (void)[searchView retain];
    (void)[busyView retain];
    [searchOption setHidden:YES];
    
    [[self window] setTitle:
        [@"iScrobbler: " stringByAppendingString:NSLocalizedString(@"Find a Radio Station", "")]];
    [splitView setDelegate:self];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectionDidChange:)
        name:NSOutlineViewSelectionDidChangeNotification object:sourceList];
    
    LEOPARD_BEGIN
    [[[self window] contentView] setWantsLayer:YES];
    CIFilter *filter = [CIFilter filterWithName:@"CIDissolveTransition"];
    CATransition *inEffect = [CATransition animation];
    [inEffect setType:kCATransitionFade];
    [inEffect setFillMode:kCAFillModeForwards];
    [inEffect setFilter:filter];
    [inEffect setDuration:0.75];
    CATransition *outEffect = [CATransition animation];
    [outEffect setType:kCATransitionFade];
    [outEffect setFillMode:kCAFillModeRemoved];
    [outEffect setFilter:filter];
    [outEffect setDuration:0.75];
    viewAnimations = [[NSDictionary alloc] initWithObjectsAndKeys:
        inEffect, NSAnimationTriggerOrderIn,
        outEffect, NSAnimationTriggerOrderOut,
        nil];
    [placeholderView setWantsLayer:YES];
    [placeholderView setAnimations:viewAnimations];
    [searchView setWantsLayer:YES];
    [searchView setAnimations:viewAnimations];
    LEOPARD_END
}

- (void)windowWillClose:(NSNotification*)note
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:OPEN_FINDSTATIONS_WINDOW_AT_LAUNCH];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ISRadioHistoryDidUpdateNotification object:nil];
    
    [[ISRadioController sharedInstance] removeObserver:self forKeyPath:@"isBusy"];
    [self radioBusyStateDidChange:YES];
    
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
        [[splitView animator] replaceSubview:cview with:placeholderView];
    }
    
    [self saveSourceListState];
}

- (void)awakeFromNib
{
    LEOPARD_BEGIN
    [sourceList setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
    LEOPARD_END
    [sourceList setDelegate:self];
    [super setWindowFrameAutosaveName:@"RadioSearch"];
    if ([[sourceListController content] count])
        [sourceListController setContent:[NSMutableArray array]];
}

- (id)init
{
    return ((self = [super initWithWindowNibName:@"ISRadioSearch"]));
}

#ifdef notyet
- (void)dealloc
{
    [super dealloc];
}
#endif

// delegate methods
- (BOOL)outlineView:(NSOutlineView *)sender isGroupItem:(id)item {
    return ([[[item representedObject] objectForKey:@"isSourceGroup"] boolValue] ? YES : NO);
}

- (void)outlineView:(NSOutlineView *)sender willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    LEOPARD_BEGIN
    if ([[[item representedObject] objectForKey:@"isSourceGroup"] boolValue]) {
        NSMutableAttributedString *uc = [[cell attributedStringValue] mutableCopy];
        [uc replaceCharactersInRange:NSMakeRange(0,[uc length]) withString:[[uc string] uppercaseString]];
        [cell setAttributedStringValue:uc];
        [uc release];
    }
    LEOPARD_END
}

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
- (BOOL)selectionShouldChangeInOutlineView:(NSOutlineView *)outlineView
{
    // Tiger table views don't disable/enable, so we have to block clicks
    return (NO == [[ISRadioController sharedInstance] isBusy]);
}
#endif

- (BOOL)outlineView:(NSOutlineView*)sender shouldSelectItem:(id)item
{
    return ([[[item representedObject] objectForKey:@"isSourceGroup"] boolValue] ? NO : YES);
}

#define SearchPanelMaxRatio 0.80
- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset
{
    if (0 == offset) {
        NSRect bounds = [sender bounds];
        proposedMax = bounds.size.width * SearchPanelMaxRatio;
    }
    return (proposedMax);
}

#define SourceListViewMin 150.0
- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
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
		CGFloat diff = SourceListViewMin - bounds.size.width;
		bounds.size.width = SourceListViewMin;
		[left setFrame:bounds];
		bounds = [right bounds];
		bounds.size.width -= diff;
		[right setFrame:bounds];
	}
}

// Singleton support
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
