//
//  ISArtistDetailsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 3/5/06.
//  Copyright 2006-2007 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "iScrobblerController.h"
#import "SongData.h"
#import "ProtocolManager.h"
#import "ISArtistDetailsController.h"
#import "ASXMLFile.h"
#import "ASWebServices.h"

static NSImage *artistImgPlaceholder = nil;
#if 0
#define dbgprint printf
#else
#define dbgprint(fmt, ...)
#endif

@implementation ISArtistDetailsController

- (ISArtistDetailsController*)initWithDelegate:(id)obj
{
    [super init];
    delegate = obj;
    
    BOOL loaded = NO;
    
    @try {
        loaded = [NSBundle loadNibNamed:@"ArtistDetails" owner:self];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_CRIT, @"Exception while loading ArtistDetails.nib! (%@)\n", e);
    }
    if (NO == loaded) {
        ScrobLog(SCROB_LOG_CRIT, @"Failed to to load ArtistDetails.nib!\n");
        [self autorelease];
        return (nil);
    }
    
    return (self);
}

+ (ISArtistDetailsController*)artistDetailsWithDelegate:(id)obj
{
    return ([[[ISArtistDetailsController alloc] initWithDelegate:obj] autorelease]);
}

- (void)setDetails:(NSMutableDictionary*)details
{
    if (!details) {
        NSString *unk = NSLocalizedString(@"Unknown", "");
        NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            nil];
        NSAttributedString *topFan = [[[NSAttributedString alloc] initWithString:unk
            attributes:attrs] autorelease];
        
        details = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            unk, @"FanRating",
            topFan, @"TopFan",
            [[[NSAttributedString alloc] initWithString:@""] autorelease], @"Artist",
            font, @"Font",
            @"", @"Description",
            [[[NSAttributedString alloc] initWithString:@"" attributes:attrs] autorelease], @"Tags",
            nil];
        if ([[similarArtistsController content] count])
            [similarArtistsController removeObjects:[similarArtistsController content]];
        [artistImage setImage:artistImgPlaceholder];
    }
    [artistController addObject:details];
}

- (void)awakeFromNib
{
    if (nil ==  artistImgPlaceholder) {
        artistImgPlaceholder = [[NSImage imageNamed:@"no_artist"] retain];
    }
    
    [detailsDrawer setParentWindow:[delegate window]];
    [detailsDrawer setDelegate:self];
    
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"detailsOpen"];
    
    [detailsProgress setUsesThreadedAnimation:YES];
    [similarArtistsTable setTarget:self];
    [similarArtistsTable setDoubleAction:@selector(handleSimilarDoubleClick:)];
    
    id obj = [[NSLevelIndicatorCell alloc] initWithLevelIndicatorStyle:NSRelevancyLevelIndicatorStyle];
    [obj setMaxValue:100.0];
    [obj setMinValue:0.0]; 
    [[similarArtistsTable tableColumnWithIdentifier:@"Rank"] setDataCell:obj];
    [obj setEnabled:NO];
    [obj release];
    [similarArtistsTable setAutosaveName:[[delegate windowFrameAutosaveName] stringByAppendingString:@"Artist Details"]];
    
    LEOPARD_BEGIN
    [artistImage setWantsLayer:YES];
    [artistImage setImageScaling:NSImageScaleProportionallyUpOrDown];
    LEOPARD_END
    
    [self setDetails:nil];
}

- (IBAction)openDetails:(id)sender
{
    [detailsDrawer open];
    [self setValue:[NSNumber numberWithBool:YES] forKey:@"detailsOpen"];

}

- (IBAction)closeDetails:(id)sender
{
    [detailsDrawer close];
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"detailsOpen"];
}

- (BOOL)textView:(NSTextView*)textView clickedOnLink:(id)url atIndex:(unsigned)charIndex
{
    BOOL handled = NO;
    @try {
        handled = [[NSWorkspace sharedWorkspace] openURL:url];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while trying to open: %@. (%@)\n", url, e);
    }
    return (handled);
}

- (void)cancelDetails
{
    ++delayedLoadSeed;
    
    [detailsProfile cancel];
    [detailsProfile release];
    detailsProfile = nil;
    [detailsTopArtists cancel];
    [detailsTopArtists release];
    detailsTopArtists = nil;
    [detailsTopFans cancel];
    [detailsTopFans release];
    detailsTopFans = nil;
    [detailsSimArtists cancel];
    [detailsSimArtists release];
    detailsSimArtists = nil;
    [detailsArtistTags cancel];
    [detailsArtistTags release];
    detailsArtistTags = nil;
    [detailsArtistData cancel];
    [detailsArtistData release];
    detailsArtistData = nil;
    
    [imageRequest cancel];
    [imageRequest release];
    imageRequest = nil;
    
    ScrobDebug(@"%@: cancel load", [[[artistController selection] valueForKey:@"Artist"] string]);
    [self setDetails:nil];
    
    if (detailsData) {
        [detailsData release];
        detailsData = nil;
        
        [detailsProgress stopAnimation:nil];
    }
}

- (BOOL)releaseConnection:(id)conn
{
    if (conn == detailsProfile) {
        detailsProfile = nil;
    } else if (conn == detailsTopArtists) {
        detailsTopArtists = nil;
    } else if (conn == detailsTopFans) {
        detailsTopFans = nil;
    } else if (conn == detailsSimArtists) {
        detailsSimArtists = nil;
    } else if (conn == detailsArtistData) {
        detailsArtistData = nil;
    } else if (conn == detailsArtistTags) {
        detailsArtistTags = nil;
    } else {
        ScrobLog(SCROB_LOG_TRACE, @"ArtistDetails: invalid connection: %p", conn);
        return (NO);
    }
    
    [conn release];
    return (YES);
}

- (void)loadTopFansData:(NSXMLDocument*)xml
{
    NSXMLElement *e = [xml rootElement];
    NSArray *all = [e elementsForName:@"user"];
    if (!all || [all count] <= 0)
        return;
    
    NSAttributedString *comma = [[[NSAttributedString alloc] initWithString:@", "] autorelease];
    NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
        [style setLineBreakMode:NSLineBreakByTruncatingMiddle];
    NSFont *font = [[artistController selection] valueForKey:@"Font"];
    NSMutableAttributedString *value = nil, *tmp = nil;
    NSEnumerator *en = [all objectEnumerator];
    int i = 0;
    while ((e = [en nextObject]) && i++ < 3) {
        NSString *user = [[[e attributeForName:@"username"] stringValue]
            stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (user) {
            if ((all = [e elementsForName:@"url"]) && [all count] > 0) {
                NSURL *url = nil;
                @try {
                    url = [NSURL URLWithString:[[all objectAtIndex:0] stringValue]];
                } @catch (NSException *ex) { }
                
                if (url) {
                    tmp = [[[NSMutableAttributedString alloc] initWithString:user attributes:
                        [NSDictionary dictionaryWithObjectsAndKeys:
                            url, NSLinkAttributeName,
                            [NSNumber numberWithInt:1], NSUnderlineStyleAttributeName,
                            [NSColor blueColor], NSForegroundColorAttributeName,
                            [NSCursor pointingHandCursor], NSCursorAttributeName,
                        nil]] autorelease];
                }
            } else
                tmp = [[[NSAttributedString alloc] initWithString:user] autorelease];
            
            if (!value)
                value = tmp;
            else {
                [value appendAttributedString:comma];
                [value appendAttributedString:tmp];
            }
        }
    }
    
    if (value) {
        [value addAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            style, NSParagraphStyleAttributeName,
            nil]
            range:NSMakeRange(0, [value length])];
        [[artistController selection] setValue:value forKeyPath:@"TopFan"];
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
            if ((imageRequest = [[NSURLDownload alloc] initWithRequest:request delegate:self]))
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
        [similarArtistsController addObject:entry];
    }
}

- (void)loadArtistData:(NSData*)data
{
    // Response Format:
    // "Artist"\t"Similar Artists"\t"Wiki Description"\t"Artist Image URL"
    
    NSMutableString *response = [[[NSMutableString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    // strip CFLF
    NSRange r = NSMakeRange(0, [response length]);
    (void)[response replaceOccurrencesOfString:@"\r\n" withString:@"" options:0 range:r];
    NSArray *elements = [response componentsSeparatedByString:@"\t"];
    if (elements && [elements count] > 3) {
        NSMutableString *description = [[[elements objectAtIndex:2] mutableCopy] autorelease];
        
        // strip any pre/post garbage (and the quotes)
        NSUInteger i = 0, len = [description length];
        for (; i < len && [description characterAtIndex:i] != (unichar)'\"'; ++i) /* no work */ ;
        
        r.location = 0;
        r.length = i+1;
        [description deleteCharactersInRange:r];
        
        len = [description length];
        i = len - 1;
        for (; i >= 0 && [description characterAtIndex:i] != (unichar)'\"'; --i) /* no work */ ;
        
        r.length = len - i;
        r.location = len - r.length;
        [description deleteCharactersInRange:r];
        
        // Strip last.fm BBCode tags
        r.location = 0;
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[artist]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[/artist]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[tag]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[/tag]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[place]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[/place]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[url]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[/url]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[b]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[/b]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[i]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"[/i]" withString:@"" options:NSCaseInsensitiveSearch range:r];
        
        // Replace double quotes
        r.length = [description length];
        (void)[description replaceOccurrencesOfString:@"\"\"" withString:@"\"" options:NSCaseInsensitiveSearch range:r];
        
        // Finally, set the tooltip.
        if ([description length] > 0) {
            [[artistController selection] setValue:description forKey:@"Description"];
            return;
        }
    }
    
    [[artistController selection] setValue:@"" forKey:@"Description"];
}

- (void)loadArtistTags:(NSXMLDocument*)xml
{
    @try {
        NSArray *names = [[xml rootElement] elementsForName:@"tag"];
        NSEnumerator *en = [names objectEnumerator];
        NSString *tagName;
        NSXMLElement *e;
        NSMutableAttributedString *value = nil;
        NSAttributedString *comma = [[[NSAttributedString alloc] initWithString:@", "] autorelease];
        
        while ((e = [en nextObject])) {
            if ((tagName = [[e attributeForName:@"name"] stringValue])
                || (tagName = [[[e elementsForName:@"name"] objectAtIndex:0] stringValue])) {
                NSString *urlStr = nil;
                NSURL *url = nil;
                @try {
                    urlStr = [[[e elementsForName:@"url"] objectAtIndex:0] stringValue];
                    url = [NSURL URLWithString:urlStr];
                } @catch (NSException *ex) { }
                
                if (url) {
                    NSMutableAttributedString *tmp = [[[NSMutableAttributedString alloc] initWithString:tagName attributes:
                        [NSDictionary dictionaryWithObjectsAndKeys:
                            url, NSLinkAttributeName,
                            [NSNumber numberWithInt:1], NSUnderlineStyleAttributeName,
                            [NSColor blueColor], NSForegroundColorAttributeName,
                            [NSCursor pointingHandCursor], NSCursorAttributeName,
                        nil]] autorelease];
                    if (!value)
                        value = tmp;
                    else {
                        [value appendAttributedString:comma];
                        [value appendAttributedString:tmp];
                    }    
                }
            } // tagName
        }
        
        NSFont *font = [[artistController selection] valueForKey:@"Font"];
        [value addAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName,
            // style, NSParagraphStyleAttributeName,
            nil]
            range:NSMakeRange(0, [value length])];
        [[artistController selection] setValue:value forKeyPath:@"Tags"];
    } @catch (NSException *e) {
        [[artistController selection] setValue:[[[NSAttributedString alloc]
            initWithString:NSLocalizedString(@"No tags found", "")] autorelease]  forKeyPath:@"Tags"];
        ScrobLog(SCROB_LOG_ERR, @"Exception processing tags: %@", e);
    }
}

- (void)openConnection:(NSArray*)args
{
    NSURL *url = [args objectAtIndex:0];
    NSConnection **p = [[args objectAtIndex:1] pointerValue];
    unsigned seed = [[args objectAtIndex:2] unsignedIntValue];
    if (seed != delayedLoadSeed)
        return;
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    [req setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"];
    *p = [[NSURLConnection connectionWithRequest:req delegate:self] retain];
}

- (void)openXML:(NSArray*)args
{
    NSURL *url = [args objectAtIndex:0];
    ASXMLFile **p = [[args objectAtIndex:1] pointerValue];
    unsigned seed = [[args objectAtIndex:2] unsignedIntValue];
    if (seed != delayedLoadSeed)
        return;
    
    *p = [[ASXMLFile xmlFileWithURL:url delegate:self cachedForSeconds:requestCacheSeconds] retain];
}

#define MakeXMLRequest(req, to, res) do { \
    urlStr = [[[urlBase stringByAppendingFormat:(to), (res)] mutableCopy] autorelease]; \
    /* Last.fm uses '+' instead of %20 */ \
    [urlStr replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [urlStr length])]; \
    url = [NSURL URLWithString:urlStr]; \
    NSArray *args = [NSArray arrayWithObjects:url, [NSValue valueWithPointer:(&(req))], \
        [NSNumber numberWithUnsignedInt:delayedLoadSeed], nil]; \
    [self performSelector:@selector(openXML:) withObject:args afterDelay:delay]; \
} while(0)

- (void)loadDetails:(NSString*)artist
{
    if (NSOrderedSame == [artist caseInsensitiveCompare:
        [[[artistController selection] valueForKey:@"Artist"] string]])
        return;
    
    [self cancelDetails]; // increments delayedLoadSeed
    ScrobDebug(@"%@: load", artist);
    
    NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [style setAlignment:NSCenterTextAlignment];
    [style setLineBreakMode:NSLineBreakByTruncatingMiddle];
    
    NSURL *url = [[NSApp delegate] audioScrobblerURLWithArtist:artist trackTitle:nil];
    NSFont *font = [[artistController selection] valueForKey:@"Font"];
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
        style, NSParagraphStyleAttributeName,
        // If url is nil, style will be the only pair in the dict
        url, NSLinkAttributeName,
        [NSNumber numberWithInt:1], NSUnderlineStyleAttributeName,
        [NSColor blueColor], NSForegroundColorAttributeName,
        font, NSFontAttributeName,
        [NSCursor pointingHandCursor], NSCursorAttributeName,
        nil];
    
    [[artistController selection] setValue:
        [[[NSAttributedString alloc] initWithString:artist attributes:attrs] autorelease]
        forKeyPath:@"Artist"];
    
    [detailsProgress startAnimation:nil];
    
    detailsLoaded = 0;
    detailsToLoad = 6;
    detailsData = [[NSMutableDictionary alloc] initWithCapacity:detailsToLoad+1];
    [detailsData setObject:artist forKey:@"artist"];
    
    NSString *urlBase = [[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"];
    
    NSMutableString *urlStr;
    // According to the webservices wiki, we are not supposed to make more than 1 req/sec
    NSTimeInterval delay = 0.0;
    
    artist = [[NSApp delegate] stringByEncodingURIChars:artist];
    
    detailsLoaded += 2; // account for missing profile loads
    
    requestCacheSeconds = 60*30;
    MakeXMLRequest(detailsSimArtists, @"artist/%@/similar.xml", artist);
    
    delay += 1.0;
    MakeXMLRequest(detailsArtistTags, @"artist/%@/toptags.xml", artist);
    
    delay += 0.5;
    MakeXMLRequest(detailsTopFans, @"artist/%@/fans.xml", artist);
    
    delay += 0.5;
    urlBase = [[NSUserDefaults standardUserDefaults] stringForKey:@"ASS URL"];
    urlStr = [[[urlBase stringByAppendingFormat:@"artistmetadata.php?artist=%@", artist] mutableCopy] autorelease];
    /* Last.fm uses '+' instead of %20 */
    [urlStr replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [urlStr length])];
    url = [NSURL URLWithString:urlStr];
    NSArray *args = [NSArray arrayWithObjects:url, [NSValue valueWithPointer:(&detailsArtistData)],
        [NSNumber numberWithUnsignedInt:delayedLoadSeed], nil];
    [self performSelector:@selector(openConnection:) withObject:args afterDelay:delay];
}

- (void)loadDetailsDidFinish:(id)obj
{
    NSValue *key = [NSValue valueWithPointer:obj];
    NSData  *data = [detailsData objectForKey:key];
    
    if (data && [data isKindOfClass:[NSXMLDocument class]]) {
        NSXMLDocument *xml = [detailsData objectForKey:key];
        @try {
            if (obj == detailsTopFans) {
                [self loadTopFansData:xml];
            } else if (obj == detailsSimArtists) {
                [self loadSimilarArtistsData:xml];
            } else if (obj == detailsArtistTags) {
                [self loadArtistTags:xml];
            }
        } @catch (NSException *e) {
            ScrobLog(SCROB_LOG_ERR, @"Exception while loading artist data from %@: %@\n", [xml URI], e);
        }
    } else {
        // currently, the only document we load is the artistmetadata link which is not XML
        // all other docuemnts (which are XML) are handled by ASXMLFile
        if (data && [data length] > 0 && obj == detailsArtistData) {
            @try {
                [self loadArtistData:data];
            } @catch (NSException *e) {
                ScrobLog(SCROB_LOG_ERR, @"Exception while loading artist meta data: %@\n", e);
            }
        }
    }
    
    [detailsData removeObjectForKey:key];
    if ([self releaseConnection:obj]) {
        ++detailsLoaded;
        if (detailsLoaded >= detailsToLoad) {
            [detailsData release];
            detailsData = nil;
            [imageRequest cancel];
            [imageRequest release];
            imageRequest = nil;
            [detailsProgress stopAnimation:nil];
        }
    }
}

- (void)setArtist:(NSString*)artist
{
    if (!artist || NO == [artist isKindOfClass:[NSString class]]
        // Assume it's some kind of place holder indicating no selection, multiple selection, etc
        || NO == [[ProtocolManager sharedInstance] isNetworkAvailable]
        || NO == [[NSUserDefaults standardUserDefaults] boolForKey:@"Artist Detail"]) {
        [self closeDetails:nil];
        //[self cancelDetails];
        return;
    }
    
    [self loadDetails:artist];
    [self openDetails:nil];
}

- (void)handleSimilarDoubleClick:(NSTableView*)sender
{
    NSArray *all = [similarArtistsController selectedObjects];
    NSEnumerator *en = [all objectEnumerator];
    NSDictionary *d;
    while ((d = [en nextObject])) {
        NSURL *url = [d objectForKey:@"url"];
        if (url)
            [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (BOOL)drawerShouldOpen:(NSDrawer*)sender
{
    return (YES);
}

- (BOOL)drawerShouldClose:(NSDrawer*)sender
{
    return (NO); // user is not allowed to close the drawer through dragging
}

- (NSSize)drawerWillResizeContents:(NSDrawer*)drawer toSize:(NSSize)contentSize
{
    NSSize minSize = [drawer minContentSize];
    if (contentSize.width < minSize.width)
        contentSize.width = minSize.width;
    if (contentSize.height < minSize.height)
        contentSize.height = minSize.height;
    return (contentSize);
}

- (void)dealloc
{
    [self cancelDetails];
    [super dealloc];
}

// ASXMLFile callbacks
- (void)xmlFileDidFinishLoading:(ASXMLFile*)connection
{
    //dbgprint("Finished loading for %p\n", connection);
    NSValue *key = [NSValue valueWithPointer:connection];
    ISASSERT(nil == [detailsData objectForKey:key], "data exists where it shouldn't!");
    
    id xml = [connection xml];
    if (xml)
        [detailsData setObject:xml forKey:key];
    [self loadDetailsDidFinish:connection];
}

- (void)xmlFile:(ASXMLFile*)connection didFailWithError:(NSError *)reason
{
    ISASSERT(nil == [connection xml], "xml data exists for an error!");
    [self xmlFileDidFinishLoading:connection];
}

// URLConnection callbacks
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (detailsData) {
        //dbgprint("Received data for %p\n", connection);
        NSMutableData *recvdData;
        NSValue *key = [NSValue valueWithPointer:connection];
        if (!(recvdData = [detailsData objectForKey:key])) {
            recvdData = [[NSMutableData alloc] init];
            [detailsData setObject:recvdData forKey:key];
            ISASSERT(2 == [recvdData retainCount], "recvdData is bad!");
            [recvdData release];
        }
        [recvdData appendData:data];
    } else {
        [connection cancel];
        (void)[self releaseConnection:connection];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    //dbgprint("Finished loading for %p\n", connection);
    [self loadDetailsDidFinish:connection];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)reason
{
    //dbgprint("Failed loading for %p\n", connection);
    ScrobLog(SCROB_LOG_TRACE, @"Connection failure: %@\n", reason);
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
            [artistImage setImage:pic];
        }
        [[NSFileManager defaultManager] removeFileAtPath:imagePath handler:nil];
    }
    [imagePath release];
    imagePath = nil;
    [self loadDetailsDidFinish:nil];
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    ScrobLog(SCROB_LOG_TRACE, @"%@ download failed with: %@\n", [[download request] URL], error);
    [imagePath release];
    imagePath = nil;
    [self downloadDidFinish:download];
}

@end
