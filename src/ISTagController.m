//
//  ISTagController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/9/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISTagController.h"
#import "ProtocolManager.h"
#import "ScrobLog.h"
#import "SongData.h"

@implementation ISTagController

- (IBAction)ok:(id)sender
{
    [[self window] endEditingFor:nil]; // force any editor to resign first-responder and commit
    send = YES;
    [self performSelector:@selector(performClose:) withObject:sender];
}

- (NSArray*)tags
{
    // strip extra spaces
    id s = [[tagData mutableCopy] autorelease];
    [s replaceOccurrencesOfString:@", " withString:@"," options:0 range:NSMakeRange(0, [s length])];
    
    NSMutableArray *array = [[s componentsSeparatedByString:@","] mutableCopy];
    NSMutableArray *empty = [NSMutableArray array];
    NSEnumerator *en = [array objectEnumerator];
    while ((s = [en nextObject])) {
        if (0 == [s length])
            [empty addObject:s];
    }
    
    [array removeObjectsInArray:empty];
    if (!array || 0 == [array count]) {
        if (tt_overwrite == mode)
            array = [NSArray arrayWithObject:@""];
        else
            array = nil;
    }
    return (array);
}

- (ISTypeToTag_t)type
{
    return (what);
}

- (void)setType:(ISTypeToTag_t)newtype
{
    what = newtype;
}

- (ISTaggingMode_t)editMode
{
    return (mode);
}

- (BOOL)send
{
    return (send);
}

- (id)representedObject
{
    return (representedObj);
}

- (void)setRepresentedObject:(id)obj
{
    if (obj != representedObj) {
        [representedObj release];
        representedObj = [obj retain];
    }
}

- (void)getGlobalTags
{
    if (lastGlobalTags == what
        // XXX following 2 conditions are an optimization on the (current) assumption
        // that specific album tags are not yet published by last.fm
        || (lastGlobalTags == tt_album && what == tt_artist)
        || (lastGlobalTags == tt_artist && what == tt_album))
        return;
    
    if (globalConn)
        [globalConn cancel];
    
    NSString *type = @"tag/toptags.xml";
    if (representedObj && [representedObj isKindOfClass:[SongData class]]) {
        switch (what) {
            default:
            case tt_artist:
            case tt_album: // no specfic album tags yet
                type = [NSString stringWithFormat:@"artist/%@/toptags.xml",
                    [[representedObj artist] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
            break;
            
            case tt_track:
                type = [NSString stringWithFormat:@"track/%@/%@/toptags.xml",
                [[representedObj artist] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],
                [[representedObj title] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
    }
    lastGlobalTags = what;
    
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
            stringByAppendingString:type];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    
    [progress startAnimation:nil];
    globalConn = [NSURLConnection connectionWithRequest:req delegate:self];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (!responseData) {
        responseData = [[NSMutableData alloc] initWithData:data];
    } else {
        [responseData appendData:data];
    }
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)reason
{
    ScrobLog(SCROB_LOG_TRACE, @"Connection failure: %@\n", reason);
    [responseData release];
    responseData = nil;
    if (connection == userConn)
        userConn = nil;
    else
        globalConn = nil;
    [progress stopAnimation:nil];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSError *err = nil;
    NSXMLDocument *xml = nil;
    if (responseData) {
        Class xmlDoc = NSClassFromString(@"NSXMLDocument");
        xml = [[xmlDoc alloc] initWithData:responseData
            options:0 //(NSXMLNodePreserveWhitespace|NSXMLNodePreserveCDATA)
            error:&err];
    } else
        err = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
    if (err) {
        [self connection:connection didFailWithError:err];
        return;
    }
    
    [responseData release];
    responseData = nil;
    
    NSArrayController *data;
    if (connection == userConn) {
        data = userTags;
        userConn = nil;
        // Get the global tags now
       [self getGlobalTags];
    } else {
        data = globalTags;
        globalConn = nil;
    }
    
    @try {
        if ([[data content] count])
            [data removeObjects:[data content]];
            
        NSArray *names = [[xml rootElement] elementsForName:@"tag"];
        NSEnumerator *en = [names objectEnumerator];
        NSString *tagName;
        NSXMLElement *e;
        while ((e = [en nextObject])) {
            if ((tagName = [[e attributeForName:@"name"] stringValue])
                || (tagName = [[[e elementsForName:@"name"] objectAtIndex:0] stringValue])) {
                NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    [tagName stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding], @"name",
                    nil];
                [data addObject:entry];
            }
        }
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception processing tags: %@", e);
    }
    
    if (!globalConn)
        [progress stopAnimation:nil];
}

- (void)tableViewSelectionDidChange:(NSNotification*)note
{
    NSTableView *table = [note object];
    NSArrayController *data;
    if (200 == [table tag])
        data = userTags;
    else if (201 == [table tag])
        data = globalTags;
    else
        return;
    
    @try {
        NSArray *all = [data selectedObjects];
        NSEnumerator *en = [all objectEnumerator];
        id obj;
        NSString *tmp = tagData;
        while ((obj = [en nextObject])) {
            if ([obj isKindOfClass:[NSDictionary class]]) {
                NSString *name = [obj objectForKey:@"name"];
                if (!tmp) 
                    tmp = name;
                else if (NSNotFound == [tmp rangeOfString:name].location)
                    tmp = [tmp stringByAppendingFormat:@", %@", name];
            }
        }
        if (tmp != tagData)
            [self setValue:tmp forKey:@"tagData"];
    } @catch (id e) {}
}

- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([key isEqualToString:@"what"]) {
        [self performSelector:@selector(getGlobalTags) withObject:nil afterDelay:0.0]; // next time through the run loop
    }
}

- (void)closeWindow
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:NSTableViewSelectionDidChangeNotification object:nil];
    [NSApp endSheet:[self window]];
    [[self window] close];
    [[NSNotificationCenter defaultCenter] postNotificationName:ISTagDidEnd object:self];
}

- (IBAction)performClose:(id)sender
{
    [self closeWindow];
}

- (IBAction)showWindow:(id)sender
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableViewSelectionDidChange:)
        name:NSTableViewSelectionDidChangeNotification object:nil];
    
    [NSApp beginSheet:[self window] modalForWindow:sender modalDelegate:self didEndSelector:nil contextInfo:nil];
    [progress startAnimation:nil];
    
    [self addObserver:self forKeyPath:@"what" options:0 context:nil];
    
    lastGlobalTags = -1;
    NSString *user = [[[ProtocolManager sharedInstance] userName]
        stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
        stringByAppendingFormat:@"user/%@/tags.xml", user];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    userConn = [NSURLConnection connectionWithRequest:req delegate:self];
}

- (void)setArtistEnabled:(BOOL)enabled
{
    artistEnabled = enabled;
}

- (void)setTrackEnabled:(BOOL)enabled
{
    trackEnabled = enabled;
}

- (void)setAlbumEnabled:(BOOL)enabled
{
    albumEnabled = enabled;
}

- (id)init
{
    artistEnabled = trackEnabled = albumEnabled = YES;
    return ((self = [super initWithWindowNibName:@"Tag"]));
}

- (void)dealloc
{
    [representedObj release];
    [responseData release];
    [tagData release];
    [userConn cancel];
    [globalConn cancel];
    [super dealloc];
}

@end
