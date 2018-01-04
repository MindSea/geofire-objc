//
//  GeoFire+Private.h
//  GeoFire
//
//  Created by Jonny Dimond on 7/7/14.
//  Copyright (c) 2014 Firebase. All rights reserved.
//

#import <GeoFire/GeoFire.h>
#import <CoreLocation/CoreLocation.h>
#import <FirebaseDatabase/FirebaseDatabase.h>

extern NSString * const MSDCustomDataKey;

@interface GeoFire (Private)

- (FIRDatabaseReference *)firebaseRefForLocationKey:(NSString *)key;

+ (CLLocation *)locationFromValue:(id)dict;
+ (NSDictionary *)dictFromLocation:(CLLocation *)location;

+ (id)customDataFromSnapshot:(FIRDataSnapshot *)snapshot;

@end
