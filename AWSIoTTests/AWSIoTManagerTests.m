//
//  AWSIoTManagerTests.m
//  AWSiOSSDKv2
//
//  Created by Colin Harris on 28/7/16.
//  Copyright © 2016 Amazon Web Services. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "AWSLogging.h"
#import "AWSTestUtility.h"
#import "AWSIoTManager.h"

@interface AWSIoTManagerTests : XCTestCase

@end

@implementation AWSIoTManagerTests

+ (void)setUp {
    [super setUp];
    [AWSTestUtility setupCognitoCredentialsProvider];
    [AWSLogger defaultLogger].logLevel = AWSLogLevelDebug;
}
- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}


- (void)testCreateKeysAndCertificateFromCsr {
    NSMutableDictionary *csrDictionary = [[NSMutableDictionary alloc] init];
    [csrDictionary setValue:@"AWSIoTTest" forKey:@"commonName"];
    [csrDictionary setValue:@"Country" forKey:@"countryName"];
    [csrDictionary setValue:@"Org" forKey:@"organizationName"];
    [csrDictionary setValue:@"Org Unit" forKey:@"organizationalUnitName"];

    AWSIoTManager *manager = [AWSIoTManager defaultIoTManager];
    [manager createKeysAndCertificateFromCsr:csrDictionary callback:^(AWSIoTCreateCertificateResponse *mainResponse){
        NSLog(@"AWSIoTCreateCertificateResponse callback!");
    }];
}

@end
