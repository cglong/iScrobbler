//
//  main.m
//  iScrobbler
//
//  Created by Sam Ley on Feb 14, 2003.
//  Released under the GPL, license details available in res/gpl.txt
//

#import <Cocoa/Cocoa.h>
#import <sandbox.h>

@interface ISLogLevelToBool : NSValueTransformer {
}
@end

@interface ISDateToString : NSValueTransformer {
}
@end

@interface ISSessionDatesToString : NSValueTransformer {
}
@end

@interface ISSessionStatsToString : NSValueTransformer {
}
@end

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [NSValueTransformer setValueTransformer:[[[ISLogLevelToBool alloc] init] autorelease]
        forName:@"ISLogLevelIsTrace"];
    
    [NSValueTransformer setValueTransformer:[[[ISDateToString alloc] init] autorelease]
        forName:@"ISDateToString"];
    
    [NSValueTransformer setValueTransformer:[[[ISSessionDatesToString alloc] init] autorelease]
        forName:@"ISSessionDatesToString"];
    
    [NSValueTransformer setValueTransformer:[[[ISSessionStatsToString alloc] init] autorelease]
        forName:@"ISSessionStatsToString"];
    
    const char *sbf = [[[NSBundle mainBundle] pathForResource:@"iScrobbler" ofType:@"sb"] fileSystemRepresentation];
    if (sbf) {
        char *sberr = NULL;
        (void)sandbox_init(sbf, SANDBOX_NAMED_EXTERNAL, &sberr);
        if (sberr) {
            #ifdef ISDEBUG
            if (strlen(sberr) > 0)
                NSLog(@"sandbox error: '%s'\n", sberr);
            #endif
            sandbox_free_error(sberr);
        }
    }
    
    [pool release];
    
    return NSApplicationMain(argc, argv);
}

@implementation ISLogLevelToBool

+ (Class)transformedValueClass
{
    return [NSNumber class];
}

+ (BOOL)allowsReverseTransformation
{
    return (YES);   
}

- (id)transformedValue:(id)value
{
    return ([NSNumber numberWithBool:[value isEqualTo:@"TRACE"]]);
}

- (id)reverseTransformedValue:(id)value
{
    if ([value boolValue])
        return (@"TRACE");
    
    return (@"VERB");
}

@end

@implementation ISDateToString

+ (Class)transformedValueClass
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation
{
    return (NO);   
}

- (id)transformedValue:(id)value
{
    return ([value description]);
}

@end

@implementation ISSessionDatesToString

+ (Class)transformedValueClass
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation
{
    return (NO);   
}

- (id)transformedValue:(id)value
{
    static NSDateFormatter *dateFormat = nil;
    if (!dateFormat) {
        dateFormat = [[NSDateFormatter alloc] init];
        [dateFormat setDateStyle:NSDateFormatterLongStyle];
        [dateFormat setTimeStyle:kCFDateFormatterShortStyle];
    }
    
    NSDate *epoch = [value valueForKey:@"epoch"];
    if (NO == [epoch isKindOfClass:[NSDate class]])
        return (@"");
    
    NSDate *term;
    NSString *s;
    if ((term = [value valueForKey:@"term"]))
        s = [NSString stringWithFormat:NSLocalizedString(@"From %@ to %@", "session date range"),
            [dateFormat stringFromDate:epoch], [dateFormat stringFromDate:term]];
    else
        s = [NSString stringWithFormat:NSLocalizedString(@"Since %@", "session date range"),
            [dateFormat stringFromDate:epoch]];
    return (s);
}

@end

void ISDurationsFromTime64(unsigned long long tSeconds, unsigned int *days, unsigned int *hours,
    unsigned int *minutes, unsigned int *seconds);

@implementation ISSessionStatsToString

+ (Class)transformedValueClass
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation
{
    return (NO);   
}

- (id)transformedValue:(id)value
{
    NSDate *epoch = [value valueForKey:@"epoch"];
    if (NO == [epoch isKindOfClass:[NSDate class]])
        return (@"");
    
    NSNumber *playCount = [value valueForKey:@"playCount"];
    NSNumber *playTime = [value valueForKey:@"playTime"];
    unsigned int days, hours, minutes, seconds;
    ISDurationsFromTime64([playTime unsignedLongLongValue], &days, &hours, &minutes, &seconds);
    NSString *timeStr = [NSString stringWithFormat:@"%u %@, %u:%02u",
        days, (1 == days ? NSLocalizedString(@"day","") : NSLocalizedString(@"days", "")),
        hours, minutes];
    
    static NSNumberFormatter *format = nil;
    if (!format) {
        format = [[NSNumberFormatter alloc] init];
        [format setNumberStyle:NSNumberFormatterDecimalStyle];
    }
    NSString *s = [NSString stringWithFormat:NSLocalizedString(@"%@ plays with a duration of %@", "session play count and time"),
        [format stringFromNumber:playCount], timeStr];
    return (s);
}

@end
