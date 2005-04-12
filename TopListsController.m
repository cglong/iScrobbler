//
//  TopListsController.m
//  iScrobbler
//
//  Created by Brian Bergstrand on 12/18/04.
//  Released under the GPL, license details available at
//  http://iscrobbler.sourceforge.net
//

#import "TopListsController.h"
#import "QueueManager.h"
#import "SongData.h"
#import "ISSearchArrayController.h"
#import "ISProfileDocumentController.h"
#import "ScrobLog.h"

// From iScrobblerController.m
void ISDurationsFromTime(unsigned int, unsigned int*, unsigned int*, unsigned int*, unsigned int*);

static TopListsController *g_topLists = nil;
static NSMutableDictionary *topAlbums = nil;
// This is the ASCII Record Separator char code
#define TOP_ALBUMS_KEY_TOKEN @"\x1e"

@interface NSString (ISHTMLConversion)
    - (NSString *)stringByConvertingCharactersToHTMLEntities;
@end

@implementation TopListsController

+ (TopListsController*)sharedInstance
{
    if (g_topLists)
        return (g_topLists);
    
    return ((g_topLists = [[TopListsController alloc] initWithWindowNibName:@"TopLists"]));
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if (g_topLists == nil) {
            return ([super allocWithZone:zone]);
        }
    }

    return (g_topLists);
}

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

#define PLAY_TIME_FORMAT @"%u:%02u:%02u:%02u"
- (void)songQueuedHandler:(NSNotification*)note
{
    SongData *song = [[note userInfo] objectForKey:QM_NOTIFICATION_USERINFO_KEY_SONG];
    NSString *artist = [song artist], *track = [song title], *playTime;
    NSMutableDictionary *entry;
    NSEnumerator *en;
    NSNumber *count;
    unsigned int time, days, hours, minutes, seconds;
    
    
    // Top Artists
    en = [[topArtistsController content] objectEnumerator];
    while ((entry = [en nextObject])) {
        if (NSOrderedSame == [artist caseInsensitiveCompare:[entry objectForKey:@"Artist"]]) {
            count = [entry objectForKey:@"Play Count"];
            count = [NSNumber numberWithUnsignedInt:
                [count unsignedIntValue] + 1];
            [entry setValue:count forKeyPath:@"Play Count"];
            
            time = [[entry objectForKey:@"Total Duration"] unsignedIntValue];
            time += [[song duration] unsignedIntValue];
            ISDurationsFromTime(time, &days, &hours, &minutes, &seconds);
            playTime = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
            [entry setValue:[NSNumber numberWithUnsignedInt:time] forKeyPath:@"Total Duration"];
            [entry setValue:playTime forKeyPath:@"Play Time"];
            break;
        }
    }

    if (!entry) {
        time = [[song duration] unsignedIntValue];
        ISDurationsFromTime(time, &days, &hours, &minutes, &seconds);
        playTime = [NSString stringWithFormat:PLAY_TIME_FORMAT, days, hours, minutes, seconds];
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    [song artist], @"Artist", [NSNumber numberWithUnsignedInt:1], @"Play Count",
                    [song duration], @"Total Duration", playTime, @"Play Time", nil];
    } else {
        entry = nil;
    }
    
    if (![topArtistsController isSearchInProgress]) {
        if (entry)
            [topArtistsController addObject:entry];
        [topArtistsController rearrangeObjects];
    } else if (entry) {
        // Can't alter the arrangedObjects array when a search is active
        // So manually enter the item in the content array
        NSMutableArray *contents = [topArtistsController content];
        [contents addObject:entry];
        [topArtistsController setContent:contents];
    }
    
    // Top Tracks
    id lastPlayedDate = [[song startTime] addTimeInterval:[[song duration] doubleValue]];
    en = [[topTracksController content] objectEnumerator];
    while ((entry = [en nextObject])) {
        if (NSOrderedSame == [artist caseInsensitiveCompare:[entry objectForKey:@"Artist"]] &&
             NSOrderedSame == [track caseInsensitiveCompare:[entry objectForKey:@"Track"]]) {
            count = [entry objectForKey:@"Play Count"];
            count = [NSNumber numberWithUnsignedInt:
                [count unsignedIntValue] + 1];
            [entry setValue:count forKeyPath:@"Play Count"];
            [entry setValue:lastPlayedDate forKeyPath:@"Last Played"];
            break;
        }
    }

    if (!entry) {
        entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    artist, @"Artist", [NSNumber numberWithUnsignedInt:1], @"Play Count",
                    track, @"Track", lastPlayedDate, @"Last Played", nil];
    } else {
        entry = nil;
    }
    
    if (![topTracksController isSearchInProgress]) {
        if (entry)
            [topTracksController addObject:entry];
        [topTracksController rearrangeObjects];
    } else if (entry) {
        // Can't alter the arrangedObjects array when a search is active
        // So manually enter the item in the content array
        NSMutableArray *contents = [topTracksController content];
        [contents addObject:entry];
        [topTracksController setContent:contents];
    }
    
    // Album info -- currently only used for Profile generation
    NSString *album;
    if ((album = [song album]) && [album length] > 0) {
        if (!topAlbums)
            topAlbums = [[NSMutableDictionary alloc] init];
        NSString *key = [NSString stringWithFormat:@"%@" TOP_ALBUMS_KEY_TOKEN @"%@",
            artist, album];
        if ((count = [topAlbums objectForKey:key])) {
            count = [NSNumber numberWithUnsignedInt:[count unsignedIntValue] + 1];
            [topAlbums setObject:count forKey:key];
        } else {
            count = [NSNumber numberWithUnsignedInt:1];
            [topAlbums setObject:count forKey:key];
        }
    }
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    if ((self = [super initWithWindowNibName:windowNibName])) {
        startDate = [[NSDate date] retain];
        
        // So stats are tracked while the window is closed, load the nib to create our Array Controllers
        // [super window] should be calling setDelegate itself, but it's not doing it for some reason.
        // It works correctly in [StatisticsController showWindow:].
        [[super window] setDelegate:self];
        
        // Register for QM notes
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(songQueuedHandler:)
                name:QM_NOTIFICATION_SONG_QUEUED
                object:nil];
        
        [super setWindowFrameAutosaveName:@"Top Lists"];
    }
    return (self);
}

- (IBAction)showWindow:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH];
    
    [super showWindow:sender];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:OPEN_TOPLISTS_WINDOW_AT_LAUNCH];
}

- (void)awakeFromNib
{
    // Seems NSArrayController adds an empty object for us, remove it
    if ([[topArtistsController content] count])
        [topArtistsController removeObjects:[topArtistsController content]];
    if ([[topTracksController content] count])
        [topTracksController removeObjects:[topTracksController content]];
        
    // Setup our sort descriptors
    NSSortDescriptor *playCountSort = [[NSSortDescriptor alloc] initWithKey:@"Play Count" ascending:NO];
    NSSortDescriptor *artistSort = [[NSSortDescriptor alloc] initWithKey:@"Artist" ascending:YES];
    NSSortDescriptor *playTimeSort = [[NSSortDescriptor alloc] initWithKey:@"Play Time" ascending:YES];
    NSArray *sorters = [NSArray arrayWithObjects:playCountSort, artistSort, playTimeSort, nil];
    
    [topArtistsController setSortDescriptors:sorters];
    
    NSSortDescriptor *trackSort = [[NSSortDescriptor alloc] initWithKey:@"Track" ascending:YES];
    sorters = [NSArray arrayWithObjects:playCountSort, artistSort, trackSort, nil];
    [topTracksController setSortDescriptors:sorters];
    
    [playCountSort release];
    [artistSort release];
    [playTimeSort release];
    [trackSort release];
}

@end

@implementation TopListsController (ISProfileReportAdditions)

- (IBAction)createProfileReport:(id)sender
{
    // Create html
    NSString *cssPath = [@"~/Documents/iScrobblerProfile.css" stringByExpandingTildeInPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cssPath])
        cssPath = [[NSBundle mainBundle] pathForResource:@"ProfileReport" ofType:@"css"];
    
    NSString *title = [NSString stringWithFormat:@"%@'s iScrobbler Profile (%@)",
        NSFullUserName(), [NSDate date]];
    
    NSData *data = nil;
    @try {
        data = [self generateHTMLReportWithCSSURL:[NSURL fileURLWithPath:cssPath]
            withTitle:title];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while generating profile report: %@.", exception);
        return;
    }
    
    ISProfileDocumentController *report =
        [[ISProfileDocumentController alloc] initWithWindowNibName:@"ISProfileReport"];
    @try {
        [report showWindowWithHTMLData:data withWindowTitle:title];
    } @catch (NSException *exception) {
        ScrobLog(SCROB_LOG_ERR, @"Exception while creating profile report: %@.", exception);
        [report release];
        return;
    }
}

#define HEAD @"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n" \
@"\t\t\"http://www.w3.org/TR/2000/REC-xhtml1-20000126/DTD/xhtml1-strict.dtd\">" \
@"<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">" \
@"<head>\n<meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\" />\n"
#define STYLE @"<link rel=\"stylesheet\" type=\"text/css\" href=\"%@\" title=\"iScrobbler stylesheet\" />\n"
#define HEAD_CLOSE @"</head>\n"
#define BODY @"<body><div class=\"content\">\n"
#define DOCCLOSE @"</div></body></html>"
#define TBLCLOSE @"</table>\n"
#define TBLTITLE(t) [NSString stringWithFormat:@"<h4>%@</h4>\n", (t)]
#define TR @"<tr>\n"
#define TRALT @"<tr class=\"alt\">"
#define TRCLOSE @"</tr>\n"
#define TD @"<td>"
#define TDTITLE @"<td class=\"title\">"
#define TDGRAPH @"<td class=\"smallgraph\">"
#define TDPOS @"<td class=\"position\">"
#define TDCLOSE @"</td>\n"

static inline NSString* TH(int span, NSString *title)
{
    return ( [NSString stringWithFormat:@"<th colspan=\"%d\" align=\"left\">%@</th>\n", span, title] );
}

static inline void HAdd(NSMutableData *d, NSString *str)
{
    [d appendData:[str dataUsingEncoding:NSUTF8StringEncoding]];
}

static inline NSString* TDEntry(NSString *type, id obj)
{
    return ( [NSString stringWithFormat:@"%@%@%@", type, obj, TDCLOSE] );
}

static inline NSString* DIVEntry(NSString *type, float width, NSString *title, id obj)
{
    return ( [NSString stringWithFormat:@"<div class=\"%@\" %@style=\"width:%u%%;\">%@</div>",
       type,  (title ? [NSString stringWithFormat:@" title=\"%@\"", title] : @""),
       (unsigned)width, obj] );
}

- (NSData*)generateHTMLReportWithCSSURL:(NSURL*)cssURL withTitle:(NSString*)profileTitle
{
    NSMutableData *d = [NSMutableData data];
    
    HAdd(d, HEAD);
    HAdd(d, [NSString stringWithFormat:@"<title>%@</title>\n", profileTitle]);
    HAdd(d, [NSString stringWithFormat:STYLE, [NSString stringWithFormat:@"file://%@", [cssURL path]]]);
    HAdd(d, HEAD_CLOSE BODY);
    
    id artists = [topArtistsController valueForKey:@"arrangedObjects"];
    id tracks = [topTracksController valueForKey:@"arrangedObjects"];
    
    NSNumber *totalTime = [artists valueForKeyPath:@"Total Duration.@sum.unsignedIntValue"];
    NSNumber *totalPlays = [artists valueForKeyPath:@"Play Count.@sum.unsignedIntValue"];
    
    unsigned int days, hours, minutes, seconds;
    ISDurationsFromTime([totalTime unsignedIntValue], &days, &hours, &minutes, &seconds);
    NSString *time = [NSString stringWithFormat:@"%u %s, %u:%02u:%02u",
        days, (1 == days ? "day" : "days"), hours, minutes, seconds];
    
    HAdd(d, @"<table style=\"width:100%; border:0; margin:0; padding:0;\">\n<tr><td valign=\"top\">\n");
    
    HAdd(d, @"<div class=\"modbox\" style=\"vertical-align:top;\">\n" @"<table class=\"topn\">\n" TR);
    HAdd(d, TH(2, TBLTITLE(NSLocalizedString(@"Totals", ""))));
    HAdd(d, TRCLOSE TR);
    HAdd(d, TDEntry(@"<td class=\"att\">", NSLocalizedString(@"Tracks Played:", "")));
    HAdd(d, TDEntry(TD, totalPlays));
    HAdd(d, TRCLOSE TRALT);
    HAdd(d, TDEntry(@"<td class=\"att\">", NSLocalizedString(@"Time Played:", "")));
    HAdd(d, TDEntry(TD, time));
    HAdd(d, TRCLOSE TBLCLOSE @"</div>");
    
    HAdd(d, TDCLOSE TRCLOSE TBLCLOSE);
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"topartists\">\n" TR);
    HAdd(d, TH(3, TBLTITLE(NSLocalizedString(@"Top Artists", ""))));
    HAdd(d, TRCLOSE);
    
    NSEnumerator *en = [artists objectEnumerator];
    NSDictionary *entry;
    NSString *artist, *track, *tmp;
    NSNumber *playCount;
    unsigned position = 1;
    float width = 100.0, percentage,
    basePlayCount = [[artists valueForKeyPath:@"Play Count.@max.unsignedIntValue"] floatValue],
    basePlayTime = [[artists valueForKeyPath:@"Total Duration.@max.unsignedIntValue"] floatValue];
    while ((entry = [en nextObject])) {
        artist = [[entry objectForKey:@"Artist"] stringByConvertingCharactersToHTMLEntities];
        playCount = [entry objectForKey:@"Play Count"];
        time = [entry objectForKey:@"Play Time"];
        
        HAdd(d, (position & 0x0000001) ? TR : TRALT);
        
        HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
        HAdd(d, TDEntry(TDTITLE, artist));
        width = rintf(([playCount floatValue] / basePlayCount) * 100.0);
        percentage = rintf(([playCount floatValue] / [totalPlays floatValue]) * 100.0);
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, playCount)));
        width = rintf(([[entry objectForKey:@"Total Duration"] floatValue] / basePlayTime) * 100.0);
        percentage = rintf(([[entry objectForKey:@"Total Duration"] floatValue] / [totalTime floatValue]) * 100.0);
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, time)));
        
        HAdd(d, TRCLOSE);
        ++position;
    }
    
    HAdd(d, TBLCLOSE @"</div>");
    [pool release];
    
    pool = [[NSAutoreleasePool alloc] init];
    HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"toptracks\">\n" TR);
    HAdd(d, TH(3, TBLTITLE(NSLocalizedString(@"Top Tracks", ""))));
    HAdd(d, TRCLOSE);
    
    en = [tracks objectEnumerator];
    position = 1;
    basePlayCount = [[tracks valueForKeyPath:@"Play Count.@max.unsignedIntValue"] floatValue];
    while ((entry = [en nextObject])) {
        artist = [[entry objectForKey:@"Artist"] stringByConvertingCharactersToHTMLEntities];
        playCount = [entry objectForKey:@"Play Count"];
        time = [entry objectForKey:@"Last Played"];
        track = [[entry objectForKey:@"Track"] stringByConvertingCharactersToHTMLEntities];
        
        HAdd(d, (position & 0x0000001) ? TR : TRALT);
        
        HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
        tmp = [NSString stringWithFormat:@"%@ - %@", track, artist];
        HAdd(d, TDEntry(TDTITLE, tmp));
        HAdd(d, TDEntry(TDGRAPH, time));
        width = rintf(([playCount floatValue] / basePlayCount) * 100.0);
        percentage = rintf(([playCount floatValue] / [totalPlays floatValue]) * 100.0);
        tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
        HAdd(d, TDEntry(TDGRAPH, DIVEntry(@"bar", width, tmp, playCount)));
        
        HAdd(d, TRCLOSE);
        ++position;
    }
    
    HAdd(d, TBLCLOSE @"</div>");
    [pool release];
    
    if (topAlbums) {
        pool = [[NSAutoreleasePool alloc] init];
        HAdd(d, @"<div class=\"modbox\">" @"<table class=\"topn\" id=\"topalbums\">\n" TR);
        HAdd(d, TH(2, TBLTITLE(NSLocalizedString(@"Top Albums", ""))));
        HAdd(d, TRCLOSE);
    
        NSArray *keys = [topAlbums keysSortedByValueUsingSelector:@selector(compare:)];
        en = [keys reverseObjectEnumerator];
        position = 1;
        // The keys are ordered from smallest to largest, therefore we want the last one
        basePlayCount = [[topAlbums objectForKey:[keys objectAtIndex:[keys count]-1]] floatValue];
        while ((tmp = [en nextObject])) {
            NSArray *items = [tmp componentsSeparatedByString:TOP_ALBUMS_KEY_TOKEN];
            if (items && 2 == [items count]) {
                artist = [[items objectAtIndex:0] stringByConvertingCharactersToHTMLEntities];
                NSString *album = [[items objectAtIndex:1] stringByConvertingCharactersToHTMLEntities];
                playCount = [topAlbums objectForKey:tmp];
                
                HAdd(d, (position & 0x0000001) ? TR : TRALT);
                
                HAdd(d, TDEntry(TDPOS, [NSNumber numberWithUnsignedInt:position]));
                tmp = [NSString stringWithFormat:@"%@ - %@", album, artist];
                HAdd(d, TDEntry(TDTITLE, tmp));
                width = rintf(([playCount floatValue] / basePlayCount) * 100.0);
                percentage = rintf(([playCount floatValue] / [totalPlays floatValue]) * 100.0);
                tmp = [NSString stringWithFormat:@"%.1f%%", percentage];
                HAdd(d, TDEntry(@"<td class=\"graph\">", DIVEntry(@"bar", width, tmp, playCount)));
                
                HAdd(d, TRCLOSE);
                ++position;
            }
        }
        
        HAdd(d, TBLCLOSE @"</div>");
        [pool release];
    }
    
    HAdd(d, DOCCLOSE);
    
    return (d);
}

@end

@implementation NSString (ISHTMLConversion)

- (NSString *)stringByConvertingCharactersToHTMLEntities
{
    NSMutableString *s = [self mutableCopy];
    NSRange r;
    // This has to be the most inefficient way to do this, but it works
    
    // Replace all ampersands (must be first!)
    r = NSMakeRange(0, [s length]-1);
    [s replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:r];
    r = NSMakeRange(0, [s length]-1);
    [s replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:r];
    r = NSMakeRange(0, [s length]-1);
    [s replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:r];
    r = NSMakeRange(0, [s length]-1);
    [s replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:r];
#ifdef notyet
    r = NSMakeRange(0, [s length]-1);
    [s replaceOccurrencesOfString:@"\xa0" withString:@"&nbsp;" options:0 range:r];
#endif
    return ([s autorelease]);
}

@end
