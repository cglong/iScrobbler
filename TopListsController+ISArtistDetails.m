//
//  TopListsController+ISArtistDetails.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 3/3/06.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "iScrobblerController.h"
#import "TopListsController.h"
#import "ProtocolManager.h"
#import "ScrobLog.h"

@implementation TopListsController (ISArtistDetails)

- (void)cancelDetails
{
    [self setDetails:nil];
    if (detailsData) {
        [detailsProfile cancel];
        detailsProfile = nil;
        [detailsTopArtists cancel];
        detailsTopArtists = nil;
        [detailsTopFans cancel];
        detailsTopFans = nil;
        [detailsSimArtists cancel];
        detailsSimArtists = nil;
        [detailsData release];
        detailsData = nil;
        
        [imageRequest cancel];
        [imageRequest release];
        imageRequest = nil;
        
        [detailsProgress stopAnimation:nil];
    }
}

#if 0
#define dbgprint printf
#else
#define dbgprint(fmt, ...)
#endif

#define MakeRequest(req, to, res) do { \
    urlStr = [[[urlBase stringByAppendingFormat:(to), (res)] mutableCopy] autorelease]; \
    /* Last.fm uses '+' instead of %20 */ \
    [urlStr replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [urlStr length])]; \
    urlStr = [[urlStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] mutableCopy]; \
    url = [NSURL URLWithString:urlStr]; \
    [urlStr release]; \
    request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0]; \
    [request setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"]; \
    ScrobLog(SCROB_LOG_TRACE, @"Requesting %@", [url absoluteString]); \
    req = [NSURLConnection connectionWithRequest:request delegate:self]; \
} while(0)

- (void)loadDetails:(NSString*)artist
{
    [self cancelDetails];
    [[detailsController selection] setValue:artist forKeyPath:@"Artist"];
    
    [detailsProgress startAnimation:nil];
    
    detailsLoaded = 0;
    detailsToLoad = 4;
    detailsData = [[NSMutableDictionary alloc] initWithCapacity:detailsToLoad+1];
    [detailsData setObject:artist forKey:@"artist"];
    
    NSString *urlBase = [[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"];
    
    NSMutableString *urlStr;
    NSURL *url;
    NSMutableURLRequest *request;
    
    MakeRequest(detailsProfile, @"user/%@/profile.xml", [[ProtocolManager sharedInstance] userName]);
    
    MakeRequest(detailsTopArtists, @"user/%@/topartists.xml", [[ProtocolManager sharedInstance] userName]);
    
    MakeRequest(detailsTopFans, @"artist/%@/fans.xml", artist);
    
    MakeRequest(detailsSimArtists, @"artist/%@/similar.xml", artist);
}

- (void)setCurrentRating
{
    int total = [[[detailsController content] valueForKey:@"totalPlaycount"] intValue];
    int artistPlays = [[[detailsController content] valueForKey:@"artistPlaycount"] intValue];
    if (total && artistPlays) {
        float rating = 10000.0 * (float)artistPlays / ((float)total + 10000.0);
        NSNumberFormatter *floatFmt = [[NSNumberFormatter alloc] init];
        [floatFmt setFormat:@"0.00"];
        [[detailsController selection] setValue:[NSString stringWithFormat:@"%@ (%d / %d)",
            [floatFmt stringForObjectValue:[NSNumber numberWithFloat:rating]], artistPlays, total]
            forKeyPath:@"FanRating"];
        [floatFmt release];
    }
}

- (void)loadProfileData:(NSXMLDocument*)xml
{
    NSXMLElement *e = [xml rootElement];
    NSArray *all = [e elementsForName:@"playcount"];
    if (!all || [all count] <= 0)
        return;
    
    e = [all objectAtIndex:0];
    int ct = [[e stringValue] intValue];
    if (ct) {
        [[detailsController selection] setValue:[NSNumber numberWithInt:ct] forKeyPath:@"totalPlaycount"];
        [self setCurrentRating];
    }
}

- (void)loadTopArtistsData:(NSXMLDocument*)xml artist:(NSString*)artist
{
    NSXMLElement *e = [xml rootElement];
    NSArray *all = [e elementsForName:@"artist"];
    if (!all || [all count] <= 0)
        return;
    
    NSEnumerator *en = [all objectEnumerator];
    while ((e = [en nextObject])) {
        NSArray *values = [e elementsForName:@"name"];
        if (values && [values count] > 0
            && NSOrderedSame == [artist caseInsensitiveCompare:[[values objectAtIndex:0] stringValue]]) {
            values = [e elementsForName:@"playcount"];
            if (values && [values count] > 0) {
                int ct = [[[values objectAtIndex:0] stringValue] intValue];
                if (ct) {
                    [[detailsController selection] setValue:[NSNumber numberWithInt:ct] forKeyPath:@"artistPlaycount"];
                    [self setCurrentRating];
                }
            }
        }
    }
}

- (void)loadTopFansData:(NSXMLDocument*)xml
{
    NSXMLElement *e = [xml rootElement];
    NSArray *all = [e elementsForName:@"user"];
    if (!all || [all count] <= 0)
        return;
    
    // We are only interested in the top fan
    e = [all objectAtIndex:0];
    NSString *user = [[[e attributeForName:@"username"] stringValue]
        stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (user) {
        all = [e elementsForName:@"weight"];
        if (all && [all count] > 0) {
            NSString *rating = [[all objectAtIndex:0] stringValue];
            if (rating)
                [[detailsController selection] setValue:
                    [NSString stringWithFormat:@"%@ (%@)", user, rating] 
                        forKeyPath:@"TopFan"];
        }
    }
}

- (void)loadSimilarArtistsData:(NSXMLDocument*)xml
{
    NSXMLElement *e = [xml rootElement];
    
    NSString *picture = [[e attributeForName:@"picture"] stringValue];
    if (picture && [picture length] > 0) {
        NSURL *url = [NSURL URLWithString:picture];
        if (url) {
            ScrobLog(SCROB_LOG_TRACE, @"Requesting %@", url);
            NSMutableURLRequest *request = request = [NSMutableURLRequest requestWithURL:url
                    cachePolicy:NSURLRequestUseProtocolCachePolicy
                    timeoutInterval:60.0];
            if ((imageRequest = [[[NSURLDownload alloc] initWithRequest:request delegate:self] retain]))
                detailsToLoad++;
        }
    }
    
    NSArray *all = [e elementsForName:@"artist"];
    if (!all || [all count] <= 0)
        return;
    
    NSEnumerator *en = [all objectEnumerator];
    while ((e = [en nextObject])) {
        NSString *name;
        NSArray *values = [e elementsForName:@"name"];
        if (values && [values count] > 0)
            name = [[values objectAtIndex:0] stringValue];
        else
            continue;
        
        NSNumber *match;
        values = [e elementsForName:@"match"];
        if (values && [values count] > 0)
            match = [NSNumber numberWithInt:[[[values objectAtIndex:0] stringValue] intValue]];
        else
            match = [NSNumber numberWithInt:0];
        
        NSURL *url;
        values = [e elementsForName:@"url"];
        if (values && [values count] > 0)
            url = [NSURL URLWithString:[[values objectAtIndex:0] stringValue]];
        else
            url = nil;
        
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            name, @"Artist",
            match, @"match",
            url, @"url",
            nil];
        [detailsSimilarController addObject:entry];
    }
}

- (void)loadDetailsDidFinish:(id)obj
{
    NSValue *key = [NSValue valueWithPointer:obj];
    NSData  *data = [detailsData objectForKey:key];
    if (!data || [data isEqualTo:[NSNull null]] || 0 == [data length])
        goto loadDetailsExit;
    
    NSError *err;
    NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:data
            options:0 //(NSXMLNodePreserveWhitespace|NSXMLNodePreserveCDATA)
            error:&err];
    
    [detailsData removeObjectForKey:key];
    
    if (!xml)
        goto loadDetailsExit;
    
    @try {
    
    if (obj == detailsProfile) {
        [self loadProfileData:xml];
        detailsProfile = nil;
    } else if (obj == detailsTopArtists) {
        [self loadTopArtistsData:xml artist:[detailsData objectForKey:@"artist"]];
        detailsTopArtists = nil;
    } else if (obj == detailsTopFans) {
        [self loadTopFansData:xml];
        detailsTopFans = nil;
    } else if (obj == detailsSimArtists) {
        [self loadSimilarArtistsData:xml];
        detailsSimArtists = nil;
    }
    
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while loading artist data from %@\n", [xml URI]);
    }
    
    [xml release];

loadDetailsExit:
    if (detailsLoaded >= detailsToLoad) {
        [detailsData release];
        detailsData = nil;
        [imageRequest cancel];
        [imageRequest release];
        imageRequest = nil;
        [detailsProgress stopAnimation:nil];
    }
}

- (void)artistSelectionDidChange:(NSNotification*)note
{
    NSString *artist = [[[note object] dataSource] valueForKeyPath:@"selection.Artist"];
    if (!artist || NO == [artist isKindOfClass:[NSString class]]
        || NO == [[ProtocolManager sharedInstance] isNetworkAvailable]) {
        // Assume it's some kind of place holder indicating no selection, multiple selection, etc
        [detailsDrawer close];
        [self cancelDetails];
        return;
    }
    [self loadDetails:artist];
    
    [detailsDrawer open];
}

- (void)setDetails:(NSMutableDictionary*)details
{
    if (!details) {
        NSString *unk = NSLocalizedString(@"Unknown", "");
        details = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            unk, @"FanRating",
            unk, @"TopFan",
            @"", @"Artist",
            nil];
        if ([[detailsSimilarController content] count])
            [detailsSimilarController removeObjects:[detailsSimilarController content]];
        [detailsImage setImage:[NSImage imageNamed:@"NSApplicationIcon"]];
    }
    [detailsController addObject:details];
}

- (void)handleSimilarDoubleClick:(NSTableView*)sender
{
    NSArray *all = [detailsSimilarController selectedObjects];
    NSEnumerator *en = [all objectEnumerator];
    NSDictionary *d;
    while ((d = [en nextObject])) {
        NSURL *url = [d objectForKey:@"url"];
        if (url)
            [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

// URLConnection callbacks

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    //dbgprint("Received data for %p\n", connection);
    NSMutableData *recvdData;
    NSValue *key = [NSValue valueWithPointer:connection];
    if (!(recvdData = [detailsData objectForKey:key])) {
        recvdData = [[NSMutableData alloc] init];
        [detailsData setObject:recvdData forKey:key];
        [recvdData release];
    }
    [recvdData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    //dbgprint("Finished loading for %p\n", connection);
    ++detailsLoaded;
    [self loadDetailsDidFinish:connection];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)reason
{
    //dbgprint("Failed loading for %p\n", connection);
    NSValue *key = [NSValue valueWithPointer:connection];
    [detailsData removeObjectForKey:key];
    [self connectionDidFinishLoading:connection];
}

// URL download callbacks

- (void)downloadDidBegin:(NSURLDownload *)download 
{
    dbgprint("ISSetImage did begin\n");
    
    [download setDeletesFileUponFailure:YES];
    char buf[] = "/tmp/scrobXXXXXX";
    [download setDestination:
        [NSString stringWithUTF8String:mktemp(buf)]
        allowOverwrite:YES];
}

- (void)download:(NSURLDownload *)download didCreateDestination:(NSString *)path
{
    dbgprint("ISSetImage path: %s\n", [path fileSystemRepresentation]);
    imagePath = [path retain];
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    dbgprint("ISSetImage did finish\n");
    if (imagePath && [[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        NSImage *pic = [[[NSImage alloc] initWithContentsOfFile:imagePath] autorelease];
        if (pic) {
            dbgprint("ISSetImage set image\n");
            [detailsImage setImage:pic];
        }
    }
    ++detailsLoaded;
    [imagePath release];
    imagePath = nil;
    [self loadDetailsDidFinish:nil];
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    dbgprint("ISSetImage did fail with %s\n", [[error description] UTF8String]);
    [imagePath release];
    imagePath = nil;
    [self downloadDidFinish:download];
}

@end
