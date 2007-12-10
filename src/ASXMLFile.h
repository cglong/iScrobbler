//
//  ASXMLFile.h
//  iScrobbler
//
//  Created by Brian Bergstrand on 9/20/2007.
//  Copyright 2007 Brian Bergstrand.
//
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>

@class ASXMLFile;

@interface NSObject (ASXMLFileDelegateExtensions)
- (void)xmlFileDidFinishLoading:(ASXMLFile*)xmlFile;
- (void)xmlFile:(ASXMLFile *)xmlFile didFailWithError:(NSError *)reason;
@end

@protocol ASXMLFileCache
// async, see notifications above
+ (ASXMLFile*)xmlFileWithURL:(NSURL*)url delegate:(id)delegate cachedForSeconds:(NSInteger)seconds; // 0 == no cache
+ (ASXMLFile*)xmlFileWithURL:(NSURL*)url delegate:(id)delegate cached:(BOOL)cached;
+ (ASXMLFile*)xmlFileWithURL:(NSURL*)url delegate:(id)delegate;

+ (void)expireCacheEntryForURL:(NSURL*)url;
+ (void)expireAllCacheEntries;
@end

@protocol ASXMLFileInterpreted
- (NSArray*)tags; // array of dictionaries keyed on same tags as the XML file
- (NSArray*)users;
@end

@interface ASXMLFile : NSObject <ASXMLFileCache, ASXMLFileInterpreted> {
    NSURLConnection *conn;
    NSMutableData *responseData;
    NSXMLDocument *xml;
    NSURL *url;
    id delegate;
    BOOL cached;
}

- (BOOL)cached; // was the data from the file cache and not the network
- (NSXMLDocument*)xml;
- (void)cancel; // no delegate messages sent after this is called

@end
