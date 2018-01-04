//
//  GeoFire.m
//  GeoFire
//
//  Created by Jonny Dimond on 7/3/14.
//  Copyright (c) 2014 Firebase. All rights reserved.
//

#import <FirebaseDatabase/FirebaseDatabase.h>

#import "GeoFire.h"
#import "GeoFire+Private.h"
#import "GFGeoHash.h"
#import "GFQuery+Private.h"

NSString * const kGeoFireErrorDomain = @"com.firebase.geofire";
NSString * const MSDCustomDataKey = @"msd";

enum {
    GFParseError = 1000
};

@interface GeoFire ()

@property (nonatomic, strong, readwrite) FIRDatabaseReference *firebaseRef;

@end

@implementation GeoFire

- (id)init
{
    [NSException raise:NSGenericException
                format:@"init is not supported. Please use %@ instead",
     NSStringFromSelector(@selector(initWithFirebaseRef:))];
    return nil;
}

- (id)initWithFirebaseRef:(FIRDatabaseReference *)firebaseRef
{
    self = [super init];
    if (self != nil) {
        if (firebaseRef == nil) {
            [NSException raise:NSInvalidArgumentException format:@"Firebase was nil!"];
        }
        self->_firebaseRef = firebaseRef;
        self->_callbackQueue = dispatch_get_main_queue();
    }
    return self;
}

- (void)setLocation:(CLLocation *)location forKey:(NSString *)key
{
    [self setLocation:location forKey:key withCompletionBlock:nil];
}

- (void)setLocation:(CLLocation *)location
             forKey:(NSString *)key
withCompletionBlock:(GFCompletionBlock)block
{
    [self setLocation:location customData:nil forKey:key withCompletionBlock:block];
}

- (void)setLocation:(CLLocation *)location
         customData:(id)customData
             forKey:(NSString *)key
withCompletionBlock:(GFCompletionBlock)block
{
    if (!CLLocationCoordinate2DIsValid(location.coordinate)) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Not a valid coordinate: [%f, %f]",
         location.coordinate.latitude, location.coordinate.longitude];
    }
    [self setLocationValue:location
                customData:customData
                    forKey:key
                 withBlock:block];
}

- (FIRDatabaseReference *)firebaseRefForLocationKey:(NSString *)key
{
    static NSCharacterSet *illegalCharacters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        illegalCharacters = [NSCharacterSet characterSetWithCharactersInString:@".#$][/"];
    });
    if ([key rangeOfCharacterFromSet:illegalCharacters].location != NSNotFound) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Not a valid GeoFire key: \"%@\". Characters .#$][/ not allowed in key!", key];
    }
    return [self.firebaseRef child:key];
}

- (void)setLocationValue:(CLLocation *)location
              customData:(id)customData
                  forKey:(NSString *)key
               withBlock:(GFCompletionBlock)block
{
    NSMutableDictionary *value;
    NSString *priority;
    if (location != nil) {
        NSNumber *lat = [NSNumber numberWithDouble:location.coordinate.latitude];
        NSNumber *lng = [NSNumber numberWithDouble:location.coordinate.longitude];
        NSString *geoHash = [GFGeoHash newWithLocation:location.coordinate].geoHashValue;
        value = [NSMutableDictionary new];
        value[@"l"] = @[ lat, lng ];
        value[@"g"] = geoHash;
        if (customData && ![[NSNull null] isEqual:customData]) {
            value[MSDCustomDataKey] = customData;
        }
        priority = geoHash;
    } else {
        value = nil;
        priority = nil;
    }
    [[self firebaseRefForLocationKey:key] setValue:value
                                       andPriority:priority
                               withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        if (block != nil) {
            dispatch_async(self.callbackQueue, ^{
                block(error);
            });
        }
    }];
}

- (void)removeKey:(NSString *)key
{
    [self removeKey:key withCompletionBlock:nil];
}

- (void)removeKey:(NSString *)key withCompletionBlock:(GFCompletionBlock)block
{
    [self setLocationValue:nil customData:nil forKey:key withBlock:block];
}

+ (CLLocation *)locationFromValue:(id)value
{
    if ([value isKindOfClass:[NSDictionary class]] && [value objectForKey:@"l"] != nil) {
        id locObj = [value objectForKey:@"l"];
        if ([locObj isKindOfClass:[NSArray class]] && [locObj count] == 2) {
            id latNum = [locObj objectAtIndex:0];
            id lngNum = [locObj objectAtIndex:1];
            if ([latNum isKindOfClass:[NSNumber class]] &&
                [lngNum isKindOfClass:[NSNumber class]]) {
                CLLocationDegrees lat = [latNum doubleValue];
                CLLocationDegrees lng = [lngNum doubleValue];
                if (CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lng))) {
                    return [[CLLocation alloc] initWithLatitude:lat longitude:lng];
                }
            }
        }
    }
    return nil;
}

+ (id)customDataFromSnapshot:(FIRDataSnapshot *)snapshot
{
    id customData = [snapshot childSnapshotForPath:MSDCustomDataKey].value;
    if ([[NSNull null] isEqual:customData]) {
        return nil;
    }
    return customData;
}

- (void)getLocationForKey:(NSString *)key withCallback:(GFCallbackBlock)callback
{
    [[self firebaseRefForLocationKey:key]
     observeSingleEventOfType:FIRDataEventTypeValue
     withBlock:^(FIRDataSnapshot *snapshot) {
         dispatch_async(self.callbackQueue, ^{
             if (snapshot.value == nil || [snapshot.value isMemberOfClass:[NSNull class]]) {
                 callback(nil, nil, nil);
             } else {
                 CLLocation *location = [GeoFire locationFromValue:snapshot.value];
                 if (location != nil) {
                     id customData = [snapshot hasChild:MSDCustomDataKey] ? [[snapshot childSnapshotForPath:MSDCustomDataKey] value] : nil;
                     callback(location, customData, nil);
                 } else {
                     NSMutableDictionary* details = [NSMutableDictionary dictionary];
                     [details setValue:[NSString stringWithFormat:@"Unable to parse location value: %@", snapshot.value]
                                forKey:NSLocalizedDescriptionKey];
                     NSError *error = [NSError errorWithDomain:kGeoFireErrorDomain code:GFParseError userInfo:details];
                     callback(nil, nil, error);
                 }
             }
         });
     } withCancelBlock:^(NSError *error) {
         dispatch_async(self.callbackQueue, ^{
             callback(nil, nil, error);
         });
     }];
}

- (GFCircleQuery *)queryAtLocation:(CLLocation *)location withRadius:(double)radius
{
    return [[GFCircleQuery alloc] initWithGeoFire:self location:location radius:radius];
}

- (GFRegionQuery *)queryWithRegion:(MKCoordinateRegion)region
{
    return [[GFRegionQuery alloc] initWithGeoFire:self region:region];
}

@end
