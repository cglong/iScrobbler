//
//  ISLoveBanListController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/11/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISLoveBanListController.h"
#import "ProtocolManager.h"
#import "ScrobLog.h"
#import "ASXMLRPC.h"

@implementation ISLoveBanListController

+ (ISLoveBanListController*)sharedController
{
    static ISLoveBanListController *shared = nil;
    return (shared ? shared : (shared = [[ISLoveBanListController alloc] init]));
}

- (IBAction)unLoveBanTrack:(id)sender
{
    NSString *method;
    NSArrayController *data;
    if (NSNotFound != [loved selectionIndex]) {
        method = @"unLoveTrack";
        data = loved;
    } else if (NSNotFound != [banned selectionIndex]) {
        method = @"unBanTrack";
        data = banned;
    } else
        return;
    
    @try {
        id obj = [[data selectedObjects] objectAtIndex:0];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            ASXMLRPC *req = [[ASXMLRPC alloc] init];
            [req setMethod:method];
            NSMutableArray *p = [req standardParams];
            [p addObject:[obj objectForKey:@"artist"]];
            [p addObject:[obj objectForKey:@"track"]];
            [req setParameters:p];
            [req setDelegate:self];
            [req setRepresentedObject:obj];
            
            [reverse setEnabled:YES];
            [req sendRequest];
            rpcreq = req;
        }
    } @catch (id e) {}
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
    if (connection == loveConn)
        loveConn = nil;
    else
        banConn = nil;
    [progress stopAnimation:nil];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSError *err = nil;
    NSXMLDocument *xml = nil;
    if (responseData) {
        xml = [[NSXMLDocument alloc] initWithData:responseData
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
    if (connection == loveConn) {
        data = loved;
        loveConn = nil;
        // Get the banned list now
        NSString *user = [[[ProtocolManager sharedInstance] userName]
            stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
            stringByAppendingFormat:@"user/%@/recentbannedtracks.xml", user];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
            cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
        [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
        banConn = [NSURLConnection connectionWithRequest:req delegate:self];
    } else {
        data = banned;
        banConn = nil;
    }
    
    @try {
        if ([[data content] count])
            [data removeObjects:[data content]];
            
        NSArray *tracks = [[xml rootElement] elementsForName:@"track"];
        NSEnumerator *en = [tracks objectEnumerator];
        NSString *artist, *track;
        NSXMLElement *e;
        while ((e = [en nextObject])) {
            if ((track = [[[e elementsForName:@"name"] objectAtIndex:0] stringValue])
                && (artist = [[[e elementsForName:@"artist"] objectAtIndex:0] stringValue])) {
                NSString *uts = [[[[e elementsForName:@"date"] objectAtIndex:0] attributeForName:@"uts"] stringValue];
                NSTimeInterval ti;
                if (uts)
                    ti = (NSTimeInterval)strtoull([uts UTF8String], NULL, 10);
                else
                    ti = 0.0;
                id date = [NSDate dateWithTimeIntervalSince1970:ti];
                if (!date)
                    date = @"";
                
                NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    [track stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding], @"track",
                    [artist stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding], @"artist",
                    [NSString stringWithFormat:@"%@ - %@", artist, track], @"displayName",
                    date, @"date",
                    nil];
                [data addObject:entry];
            }
        }
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception processing tracks: %@", e);
    }
    
    if (!banConn)
        [progress stopAnimation:nil];
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
    @try {
        if ([method isEqualToString:@"unLoveTrack"]) {
            [loved removeObject:[request representedObject]];
        } else if ([method isEqualToString:@"unBanTrack"]) {
            [banned removeObject:[request representedObject]];
        }
    } @catch(id e) {}
    
    ScrobLog(SCROB_LOG_TRACE, @"RPC request '%@' successful (%@)",
        method, [request representedObject]);
    
    [rpcreq release];
    rpcreq = nil;
    
    if (NSNotFound != [loved selectionIndex] || NSNotFound != [banned selectionIndex])
        [reverse setEnabled:YES];
}

- (void)error:(NSError*)error receivedForRequest:(ASXMLRPC*)request
{
    ScrobLog(SCROB_LOG_ERR, @"RPC request '%@' for '%@' returned error: %@",
        [request method], [request representedObject], error);
    
    [rpcreq release];
    rpcreq = nil;
    
    if (NSNotFound != [loved selectionIndex] || NSNotFound != [banned selectionIndex])
        [reverse setEnabled:YES];
}

- (void)tableViewSelectionDidChange:(NSNotification*)note
{
    NSTableView *alt, *table = [note object];
    NSArrayController *data;
    NSString *title;
    if (300 == [table tag]) {
        data = loved;
        alt = bannedTable;
        title = NSLocalizedString(@"Un-Love Track", "");
    } else if (301 == [table tag]) {
        data = banned;
        alt = lovedTable;
        title = NSLocalizedString(@"Un-Ban Track", "");
    } else
        return;
    
    if (NSNotFound != [data selectionIndex]) 
        [alt deselectAll:nil];
        
    if ((NSNotFound == [loved selectionIndex] && NSNotFound == [banned selectionIndex]) || rpcreq)
        [reverse setEnabled:NO];
    else
        [reverse setEnabled:YES];
    [reverse setTitle:title];
}

- (void)closeWindow
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:NSTableViewSelectionDidChangeNotification object:nil];
    [rpcreq release];
    rpcreq = nil;
    [responseData release];
    responseData = nil;
    [loveConn cancel];
    loveConn = nil;
    [banConn cancel];
    banConn = nil;
    [[self window] close];
    [[NSNotificationCenter defaultCenter] postNotificationName:ISLoveBanListDidEnd object:self];
}

- (IBAction)performClose:(id)sender
{
    [self closeWindow];
}

- (IBAction)showWindow:(id)sender
{
    BOOL init;
    if ((init = ![[self window] isVisible])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableViewSelectionDidChange:)
            name:NSTableViewSelectionDidChangeNotification object:nil];
        [super setWindowFrameAutosaveName:@"LoveBan"];
    }
    
    [super showWindow:sender];
    
    if (init) {
        [reverse setEnabled:NO];
        [progress startAnimation:nil];
        
        NSString *user = [[[ProtocolManager sharedInstance] userName]
            stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
            stringByAppendingFormat:@"user/%@/recentlovedtracks.xml", user];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
            cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
        [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
        loveConn = [NSURLConnection connectionWithRequest:req delegate:self];
    }
}

- (id)init
{
    return ((self = [super initWithWindowNibName:@"LoveBanList"]));
}

#ifdef notyet
- (void)dealloc
{
    [rpcreq release];
    [responseData release];
    [loveConn cancel];
    [banConn cancel];
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
