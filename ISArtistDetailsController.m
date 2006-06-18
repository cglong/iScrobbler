//
//  ISArtistDetailsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 3/5/06.
//  Copyright 2006 Brian Bergstrand.
//
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "iScrobblerController.h"
#import "SongData.h"
#import "ProtocolManager.h"
#import "ScrobLog.h"
#import "ISArtistDetailsController.h"

#ifdef obsolete
static NSXMLDocument *profileCache = nil;
static NSDate *profileNextUpdate = nil;
static NSXMLDocument *topArtistsCache = nil;
static NSDate *topArtistsNextUpdate = nil;
static NSTimeInterval topArtistsCachePeriod = 7200.0; // 2 hrs
#endif
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

+ (BOOL)canLoad
{
    // 10.4+ only
    return (nil !=  NSClassFromString(@"NSXMLDocument"));
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
    
    [self setValue:[NSNumber numberWithBool:NO] forKey:@"detailsOpen"];
    
    [detailsProgress setUsesThreadedAnimation:YES];
    [similarArtistsTable setTarget:self];
    [similarArtistsTable setDoubleAction:@selector(handleSimilarDoubleClick:)];
    
    Class nsLevel = NSClassFromString(@"NSLevelIndicatorCell");
    id obj = [nsLevel new];
    [obj setMaxValue:100.0];
    [obj setMinValue:0.0]; 
    [obj setLevelIndicatorStyle:NSRelevancyLevelIndicatorStyle];
    [[similarArtistsTable tableColumnWithIdentifier:@"Rank"] setDataCell:obj];
    [similarArtistsTable setAutosaveName:[[delegate windowFrameAutosaveName] stringByAppendingString:@"Artist Details"]];
    
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

- (BOOL)textView:(NSTextView*)textView clickedOnLink:(id)link atIndex:(unsigned)charIndex
{
    BOOL handled = NO;
    @try {
        handled = [[NSWorkspace sharedWorkspace] openURL:link];
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while trying to open: %@. (%@)\n", link, e);
    }
    return (handled);
}

- (void)cancelDetails
{
    [self setDetails:nil];
    
    [detailsProfile cancel];
    detailsProfile = nil;
    [detailsTopArtists cancel];
    detailsTopArtists = nil;
    [detailsTopFans cancel];
    detailsTopFans = nil;
    [detailsSimArtists cancel];
    detailsSimArtists = nil;
    [detailsArtistData cancel];
    detailsArtistData = nil; 
    
    [imageRequest cancel];
    [imageRequest release];
    imageRequest = nil;
    
    if (detailsData) {
        [detailsData release];
        detailsData = nil;
        
        [detailsProgress stopAnimation:nil];
    }
}

- (void)releaseConnection:(id)conn
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
    }
}

- (void)setCurrentRating
{
    int total = [[[artistController content] valueForKey:@"totalPlaycount"] intValue];
    int artistPlays = [[[artistController content] valueForKey:@"artistPlaycount"] intValue];
    if (total && artistPlays) {
        float rating = 10000.0 * (float)artistPlays / ((float)total + 10000.0);
        NSNumberFormatter *floatFmt = [[NSNumberFormatter alloc] init];
        [floatFmt setFormat:@"0.00"];
        [[artistController selection] setValue:[NSString stringWithFormat:@"%@ (%d / %d)",
            [floatFmt stringForObjectValue:[NSNumber numberWithFloat:rating]], artistPlays, total]
            forKeyPath:@"FanRating"];
        [floatFmt release];
    }
}

#ifdef obsolete
// Right after the release of 1.2, last.fm change top fans to a simple count of plays for the last week
- (void)loadProfileData:(NSXMLDocument*)xml
{
    NSXMLElement *e = [xml rootElement];
    NSArray *all = [e elementsForName:@"playcount"];
    if (!all || [all count] <= 0)
        return;
    
    e = [all objectAtIndex:0];
    int ct = [[e stringValue] intValue];
    if (ct) {
        [[artistController selection] setValue:[NSNumber numberWithInt:ct] forKeyPath:@"totalPlaycount"];
        [self setCurrentRating];
        
        if (xml && xml != profileCache) {
            [profileCache release];
            profileCache = [xml retain];
            [profileNextUpdate release];
            profileNextUpdate = [[NSDate dateWithTimeIntervalSinceNow:900.0 /* 15 minutes */] retain];
            ScrobLog(SCROB_LOG_TRACE, @"Caching profile for %d seconds.\n", 900);
            
            // The smaller the play count, the more often the top artists can generate...
            if (ct > 10000)
                topArtistsCachePeriod = 21600.0; // 6 hrs
            else if (ct > 1000)
                topArtistsCachePeriod = 14400.0;
            else if (ct > 100)
                topArtistsCachePeriod = 7200.0;
            else
                topArtistsCachePeriod = 3600.0; // 1 hr
        }
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
                    [[artistController selection] setValue:[NSNumber numberWithInt:ct] forKeyPath:@"artistPlaycount"];
                    [self setCurrentRating];
                }
            }
            break;
        }
    }
    
    if (artist && xml && xml != topArtistsCache) {
        [topArtistsCache release];
        topArtistsCache = [xml retain];
        [topArtistsNextUpdate release];
        topArtistsNextUpdate = [[NSDate dateWithTimeIntervalSinceNow:topArtistsCachePeriod] retain];
        ScrobLog(SCROB_LOG_TRACE, @"Caching top artists for %.0f seconds.\n", topArtistsCachePeriod);
    }
}
#endif


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
        if ((all = [e elementsForName:@"weight"]) && [all count] > 0) {
            NSString *rating = [[all objectAtIndex:0] stringValue];
            if (rating) {
                id value = nil;
                NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
                [style setLineBreakMode:NSLineBreakByTruncatingMiddle];
                NSFont *font = [[artistController selection] valueForKey:@"Font"];
                if ((all = [e elementsForName:@"url"]) && [all count] > 0) {
                    NSString *urlStr = [[all objectAtIndex:0] stringValue];
                    NSURL *url = nil;
                    @try {
                        url = [NSURL URLWithString:urlStr];
                    } @catch (NSException *e) { }
                    
                    if (url) {
                        value = [[[NSMutableAttributedString alloc] initWithString:user attributes:
                            [NSDictionary dictionaryWithObjectsAndKeys:
                                url, NSLinkAttributeName,
                                [NSNumber numberWithInt:1], NSUnderlineStyleAttributeName,
                                [NSColor blueColor], NSForegroundColorAttributeName,
                                [NSCursor pointingHandCursor], NSCursorAttributeName,
                            nil]] autorelease];
                         
                        [value appendAttributedString:[[[NSAttributedString alloc]
                            initWithString:[NSString stringWithFormat:@" - %@", rating]]
                            autorelease]];
                        [value addAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                            font, NSFontAttributeName,
                            style, NSParagraphStyleAttributeName,
                            nil]
                            range:NSMakeRange(0, [value length])];
                    }
                } else
                    value = [[[NSAttributedString alloc] initWithString:
                        [NSString stringWithFormat:@"%@ - %@", user, rating]
                        attributes:[NSDictionary dictionaryWithObjectsAndKeys:
                            style, NSParagraphStyleAttributeName,
                            font, NSFontAttributeName,
                            nil]] autorelease];
                
                if (value)
                    [[artistController selection] setValue:value forKeyPath:@"TopFan"];
            }
        }
    }
    
    // If we weren't able to calculate a fan rating, see if the current user is listed in the AS fan data
    NSString *unk = NSLocalizedString(@"Unknown", "");
    if ([unk isEqualToString:[[artistController selection] valueForKey:@"FanRating"]]) {
        NSString *curUser = [[ProtocolManager sharedInstance] userName];
        all = [[xml rootElement] elementsForName:@"user"];
        NSEnumerator *en = [all objectEnumerator];
        while ((e = [en nextObject])) {
            if ((user = [[[e attributeForName:@"username"] stringValue]
                stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding])
                && NSOrderedSame == [user caseInsensitiveCompare:curUser]) {
                if ((all = [e elementsForName:@"weight"]) && [all count] > 0) {
                    NSString *rating = [[all objectAtIndex:0] stringValue];
                    if (rating)
                        [[artistController selection] setValue:rating forKeyPath:@"FanRating"];
                }
                break;
            }
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
        int i = 0, len = [description length];
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

- (void)openConnection:(NSArray*)args
{
    NSMutableURLRequest *request = [args objectAtIndex:0];
    NSURLConnection **p = [[args objectAtIndex:1] pointerValue];
    
    *p = [NSURLConnection connectionWithRequest:request delegate:self];
    ScrobLog(SCROB_LOG_TRACE, @"Requesting %@ (%p)", [[request URL] absoluteString], *p);
}

#define MakeRequest(req, to, res) do { \
    urlStr = [[[urlBase stringByAppendingFormat:(to), (res)] mutableCopy] autorelease]; \
    /* Last.fm uses '+' instead of %20 */ \
    [urlStr replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [urlStr length])]; \
    url = [NSURL URLWithString:urlStr]; \
    request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0]; \
    [request setValue:[[ProtocolManager sharedInstance] userAgent] forHTTPHeaderField:@"User-Agent"]; \
    NSArray *args = [NSArray arrayWithObjects:request, [NSValue valueWithPointer:(&(req))], nil]; \
    [self performSelector:@selector(openConnection:) withObject:args afterDelay:delay]; \
} while(0)

- (void)loadDetails:(NSString*)artist
{
    if (NSOrderedSame == [artist caseInsensitiveCompare:
        [[[artistController selection] valueForKey:@"Artist"] string]])
        return;
    
    [self cancelDetails];
    
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
    detailsToLoad = 5;
    detailsData = [[NSMutableDictionary alloc] initWithCapacity:detailsToLoad+1];
    [detailsData setObject:artist forKey:@"artist"];
    
    NSString *urlBase = [[NSUserDefaults standardUserDefaults] stringForKey:@"WS URL"];
    
    NSMutableString *urlStr;
    NSMutableURLRequest *request;
    // According to the webservices wiki, we are not supposed to make more than 1 req/sec
    NSTimeInterval delay = 0.0;
    
    artist = [[NSApp delegate] stringByEncodingURIChars:artist];
    
    #ifdef obsolete
    NSDate *now = [NSDate date];
    NSString *user = [@"Damaged" //[[[ProtocolManager sharedInstance] userName]
        stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    if (!profileCache || !profileNextUpdate || [profileNextUpdate isLessThan:now]) {
        MakeRequest(detailsProfile, @"user/%@/profile.xml", user);
        delay = 0.5;
    } else {
        ++detailsLoaded;
        ScrobLog(SCROB_LOG_TRACE, @"Loading profile from cache. Next load from net: %@.\n", profileNextUpdate);
        [self loadProfileData:profileCache];
    }
    
    if (!topArtistsCache || !topArtistsNextUpdate || [topArtistsNextUpdate isLessThan:now]) {
        MakeRequest(detailsTopArtists, @"user/%@/topartists.xml", user);
        delay += 0.5;
    } else {
        ++detailsLoaded;
        ScrobLog(SCROB_LOG_TRACE, @"Loading top artists from cache. Next load from net: %@.\n", topArtistsNextUpdate);
        // Use unescaped artist name
        [self loadTopArtistsData:topArtistsCache artist:[detailsData objectForKey:@"artist"]];
    }
    #else
    // account for missing profile loads
    detailsLoaded += 2;
    #endif
    
    MakeRequest(detailsTopFans, @"artist/%@/fans.xml", artist);
    
    delay += 1.0;
    MakeRequest(detailsSimArtists, @"artist/%@/similar.xml", artist);
    
    delay += 0.5;
    urlBase = [[NSUserDefaults standardUserDefaults] stringForKey:@"ASS URL"];
    MakeRequest(detailsArtistData, @"artistmetadata.php?artist=%@", artist);
}

- (void)loadDetailsDidFinish:(id)obj
{
    NSValue *key = [NSValue valueWithPointer:obj];
    NSData  *data = [detailsData objectForKey:key];
    if (!data || 0 == [data length])
        goto loadDetailsExit;
    
    NSError *err;
    Class xmlClass = NSClassFromString(@"NSXMLDocument");
    NSXMLDocument *xml = [[xmlClass alloc] initWithData:data
            options:0 //(NSXMLNodePreserveWhitespace|NSXMLNodePreserveCDATA)
            error:&err];
    
    if (!xml) {
        if (obj == detailsArtistData) {
            @try {
                [self loadArtistData:data];
            } @catch (NSException *e) {
                ScrobLog(SCROB_LOG_ERR, @"Exception while loading artist meta data: %@\n", e);
            }
        }
        goto loadDetailsExit;
    }
    
    @try {
    
    #ifdef obsolete
    if (obj == detailsProfile) {
        [self loadProfileData:xml];
    } else if (obj == detailsTopArtists) {
        [self loadTopArtistsData:xml artist:[detailsData objectForKey:@"artist"]];
    } else
    #endif
    if (obj == detailsTopFans) {
        [self loadTopFansData:xml];
    } else if (obj == detailsSimArtists) {
        [self loadSimilarArtistsData:xml];
    }
    
    } @catch (NSException *e) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while loading artist data from %@: %@\n", [xml URI], e);
    }
    
    [xml release];

loadDetailsExit:
    [detailsData removeObjectForKey:key];
    [self releaseConnection:obj];
    if (detailsLoaded >= detailsToLoad) {
        [detailsData release];
        detailsData = nil;
        [imageRequest cancel];
        [imageRequest release];
        imageRequest = nil;
        [detailsProgress stopAnimation:nil];
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

- (void)dealloc
{
    [self cancelDetails];
    [super dealloc];
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
        [self releaseConnection:connection];
        [connection cancel];
    }
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
    ++detailsLoaded;
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
