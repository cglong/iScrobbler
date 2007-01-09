//
//  ISRecommendController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 1/8/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available res/gpl.txt
//

#import "ISRecommendController.h"
#import "ProtocolManager.h"
#import "ScrobLog.h"

@implementation ISRecommendController

- (IBAction)ok:(id)sender
{
    [[self window] endEditingFor:nil]; // force any editor to resign first-responder and commit
    send = YES;
    [self performSelector:@selector(performClose:) withObject:sender];
}

- (NSString*)who
{
    return (toUser ? toUser : @"");
}

- (NSString*)message
{
    return (msg ? msg : @"");
}

- (ISTypeToRecommend_t)type
{
    return (what);
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
    conn = nil;
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
    conn = nil;
    
    @try {
        if ([[friends content] count])
            [friends removeObjects:[friends content]];
            
        NSArray *users = [[xml rootElement] elementsForName:@"user"];
        NSEnumerator *en = [users objectEnumerator];
        NSString *user;
        NSXMLElement *e;
        while ((e = [en nextObject])) {
            if ((user = [[[e attributeForName:@"username"] stringValue]
                stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding])) {
                
                NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    user, @"name",
                    nil];
                [friends addObject:entry];
            }
        }
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception processing friends.xml: %@", e);
    }
    
    [progress stopAnimation:nil];
}

- (void)tableViewSelectionDidChange:(NSNotification*)note
{
    NSTableView *table = [note object];
    if (100 != [table tag])
        return;
    
    @try {
        NSArray *users = [friends selectedObjects];
        if ([users count] > 0) {
            id user = [users objectAtIndex:0];
            if ([user isKindOfClass:[NSDictionary class]]) {
                [self setValue:[user objectForKey:@"name"] forKey:@"toUser"];
            }
        }
    } @catch (id e) {}
}

- (void)closeWindow
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:NSTableViewSelectionDidChangeNotification object:nil];
    [NSApp endSheet:[self window]];
    [[self window] close];
    [[NSNotificationCenter defaultCenter] postNotificationName:ISRecommendDidEnd object:self];
}

- (IBAction)performClose:(id)sender
{
    [self closeWindow];
}

- (IBAction)showWindow:(id)sender
{
    [progress startAnimation:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableViewSelectionDidChange:)
        name:NSTableViewSelectionDidChangeNotification object:nil];
    
    [NSApp beginSheet:[self window] modalForWindow:sender modalDelegate:self didEndSelector:nil contextInfo:nil];
    
    // Get the friends list
    NSString *user = [[[ProtocolManager sharedInstance] userName]
        stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *url = [[[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"]
        stringByAppendingFormat:@"user/%@/friends.xml", user];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    conn = [NSURLConnection connectionWithRequest:req delegate:self];
}

- (id)init
{
    return ((self = [super initWithWindowNibName:@"Recommend"]));
}

- (void)dealloc
{
    [representedObj release];
    [responseData release];
    [conn cancel];
    [toUser release];
    [msg release];
    [super dealloc];
}

@end
