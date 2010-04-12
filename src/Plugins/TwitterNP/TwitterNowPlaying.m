//
//  ISTwitterNowPlaying.m
//  iScrobbler Plugin
//
//  Copyright 2010 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//
#import <dispatch/dispatch.h>

#import "TwitterNowPlaying.h"
#import "SongData.h"
#import "keychain.h"

@interface SimpleTwitter : NSObject {
    NSString *name;
    NSString *pass;
    NSMutableData *response;
    NSURLConnection *conn; // weak
    id delegate;
}

+ (SimpleTwitter*)twitterWithUser:(NSString*)user password:(NSString*)password;

@property (nonatomic, assign) id delegate;

- (void)setStatus:(NSString*)msg;
- (void)deleteStatus:(NSString*)sid;

@end

@implementation ISTwitterNowPlaying

- (void)statusResult:(NSString*)sid
{
    if (nil == sid) {
        // failed
        return;
    }
    
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger nplimit = [ud integerForKey:@"builtin_Twitter_nplimit"];
    NSMutableArray *lastnp = [[[ud arrayForKey:@"builtin_Twitter_lastnp"] mutableCopy] autorelease];
    if (nil == lastnp) {
        lastnp = [NSMutableArray array];
    } else if ([lastnp containsObject:sid]) {
        return; // duplicate tweet
    }
    
    [lastnp insertObject:sid atIndex:0];
    
    if ([lastnp count] > nplimit) {
        sid = [lastnp lastObject];
        [twitter deleteStatus:sid];
        [lastnp removeObject:sid];
    }
    
    [ud setObject:lastnp forKey:@"builtin_Twitter_lastnp"];
}

- (void)sendNowPlaying
{
    if (npSong && [mProxy isNetworkAvailable]) {
        if (!twitter) {
            NSString *pass, *user;
            pass = [[NSClassFromString(@"KeyChain") defaultKeyChain] internetPassswordForService:@"twitter.com" account:&user];
            if (0 == [pass length] || 0 == [user length])
                return;
        
            if (!(twitter = [[SimpleTwitter twitterWithUser:user password:pass] retain]))
                return;
                
            twitter.delegate = self;
        }
    
        enum {
            kTweetLimit = 140,
            kTweetNPLimit = 140 - 12,
            kMusicMondayLen = 13, //" #MusicMonday"
        };
        
        NSString *msg = [NSString stringWithFormat:@"%@ - %@",
            [npSong title], [npSong artist]];
        if ([msg length] > kTweetNPLimit) {
            msg = [npSong title];
            if ([msg length] > kTweetNPLimit)
                msg = [msg substringWithRange:NSMakeRange(0, kTweetNPLimit)];
        }
        msg = [msg stringByAppendingString:@" #nowplaying"];
        
        NSCalendar *cal = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] autorelease];
        NSDateComponents *comps = [cal components:NSWeekdayCalendarUnit fromDate:[NSDate date]];
        if (2 == [comps weekday] && ([msg length] + kMusicMondayLen) <= kTweetLimit) {
            msg = [msg stringByAppendingString:@" #MusicMonday"];
        }
        
        [twitter setStatus:msg];
    }
}

- (void)nowPlaying:(NSNotification*)note
{
    if (NO == [[NSUserDefaults standardUserDefaults] boolForKey:@"builtin_Twitter_enabled"])
        return;
    
    SongData *s = [note object];
    BOOL repeat = NO;
    id obj;
    NSDictionary *userInfo = [note userInfo];
    if (userInfo && (obj = [userInfo objectForKey:@"repeat"]))
        repeat = [obj boolValue];
    if (!s || (!repeat && [npSong isEqualToSong:s]) || 0 == [[s artist] length] || 0 == [[s title] length]) {
        if (!s) {
            [npSong release];
            npSong = nil;
        }
        return;
    }
    
    [npSong release];
    npSong = [s retain];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendNowPlaying) object:nil];
    [self performSelector:@selector(sendNowPlaying) withObject:nil afterDelay:5.0];
}

// ISPlugin protocol

- (id)initWithAppProxy:(id<ISPluginProxy>)proxy
{
    self = [super init];
    mProxy = proxy;
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // get the Twitter password so we prompt the user during launch (if necessary)
        (void)[[NSClassFromString(@"KeyChain") defaultKeyChain] internetPassswordForService:@"twitter.com" account:nil];
    });
    
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (nil == [ud objectForKey:@"builtin_Twitter_nplimit"])
        [ud setInteger:5 forKey:@"builtin_Twitter_nplimit"];
    
    if (nil == [ud objectForKey:@"builtin_Twitter_enabled"])
        [ud setBool:YES forKey:@"builtin_Twitter_enabled"];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(nowPlaying:)
        name:[mProxy nowPlayingNotificationName]
        object:nil];
    
    return (self);
}

- (NSString*)description
{
    return (NSLocalizedString(@"Twitter Now Playing Plugin", ""));
}

- (void)applicationWillTerminate
{

}

@end

@implementation SimpleTwitter

@synthesize delegate;

+ (SimpleTwitter*)twitterWithUser:(NSString*)user password:(NSString*)password
{
    SimpleTwitter *t = [[SimpleTwitter alloc] init];
    t->name = [user retain];
    t->pass = [password retain];
    return ([t autorelease]);
}

- (void)setStatus:(NSString*)msg
{
    NSURL *url = [NSURL URLWithString:@"https://api.twitter.com/1/statuses/update.xml"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20.0];
    [request setHTTPMethod:@"POST"];
    msg = [(id)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)msg, NULL,
        CFSTR(";/?:@&=$+{}<>,"), kCFStringEncodingUTF8) autorelease];
    msg = [@"status=" stringByAppendingString:msg];
    [request setHTTPBody:[msg dataUsingEncoding:NSUTF8StringEncoding]];
    
    if (response)
        [response setLength:0];
    else
        response = [[NSMutableData alloc] init];
    [conn cancel];
    [conn release];
    conn = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
}

- (void)deleteStatus:(NSString*)sid
{
    NSURL *url = [NSURL URLWithString:
        [NSString stringWithFormat:@"https://api.twitter.com/1/statuses/destroy/%@.xml", sid]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20.0];
    [request setHTTPMethod:@"DELETE"];
    (void)[NSURLConnection connectionWithRequest:request delegate:self];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (conn != connection)
        return;
    
    [response appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if (conn != connection)
        return;
    
    NSString *sid = nil;
    NSUInteger len;
    if (response && (len = [response length]) > 0) {
        const char *bytes = [response bytes];
        NSString *head = [[[NSString alloc] initWithBytes:bytes length:MIN(len,500) encoding:NSUTF8StringEncoding] autorelease];
        // There's some crashers in NSXMLDocument, so avoid passing HTML and run the parser with lint enabled
        if (NSNotFound == [head rangeOfString:@"<html>" options:NSLiteralSearch].location) {
            NSError *err;
            NSXMLDocument *x = [[[NSXMLDocument alloc] initWithData:response
                options:NSXMLDocumentTidyXML // attempts to correct invalid XML
                error:&err] autorelease];
            
            @try {
                if (nil != x) {
                    NSXMLElement *e = [x rootElement]; // <status></status>
                    sid = [[[e elementsForName:@"id"] objectAtIndex:0] stringValue];
                }
            } @catch (NSException *e) {}
        }
    }
    
    [delegate statusResult:sid];
    [response setLength:0];
    [conn release];
    conn = nil;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    //ScrobLog(SCROB_LOG_TRACE, @"twitter connection error: %@", error);
    if (conn != connection)
        return;
    
    [delegate statusResult:nil];
    [response setLength:0];
    [conn release];
    conn = nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if ([challenge previousFailureCount] == 0) {
        NSURLCredential *cred = [NSURLCredential credentialWithUser:name password:pass
            persistence:NSURLCredentialPersistenceForSession];
        [[challenge sender] useCredential:cred forAuthenticationChallenge:challenge];
    } else {
        // Log failure?
    }
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return (nil);
}

- (void)dealloc
{
    [conn cancel];
    [conn release];
    [name release];
    [pass release];
    [response release];
    [super dealloc];
}

@end
