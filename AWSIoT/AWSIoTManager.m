//
// Copyright 2010-2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License").
// You may not use this file except in compliance with the License.
// A copy of the License is located at
//
// http://aws.amazon.com/apache2.0
//
// or in the "license" file accompanying this file. This file is distributed
// on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
// express or implied. See the License for the specific language governing
// permissions and limitations under the License.
//

#import "AWSIoTManager.h"
#import "AWSIoTKeychain.h"
#import "AWSIoTCSR.h"
#import <AWSCore/AWSSynchronizedMutableDictionary.h>

static NSString *const AWSInfoIoTManager = @"IoTManager";

@interface AWSIoT()

- (instancetype)initWithConfiguration:(AWSServiceConfiguration *)configuration;

@end

@interface AWSIoTManager()

@property (nonatomic, strong) AWSIoT *IoT;

@end

@implementation AWSIoTCreateCertificateResponse

@end

@implementation AWSIoTManager

static AWSSynchronizedMutableDictionary *_serviceClients = nil;

+ (instancetype)defaultIoTManager {
    static AWSIoTManager *_defaultIoTManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        AWSServiceConfiguration *serviceConfiguration = nil;
        AWSServiceInfo *serviceInfo = [[AWSInfo defaultAWSInfo] defaultServiceInfo:AWSInfoIoTManager];
        if (serviceInfo) {
            serviceConfiguration = [[AWSServiceConfiguration alloc] initWithRegion:serviceInfo.region
                                                               credentialsProvider:serviceInfo.cognitoCredentialsProvider];
        }

        if (!serviceConfiguration) {
            serviceConfiguration = [AWSServiceManager defaultServiceManager].defaultServiceConfiguration;
        }

        if (!serviceConfiguration) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:@"The service configuration is `nil`. You need to configure `Info.plist` or set `defaultServiceConfiguration` before using this method."
                                         userInfo:nil];
        }

        _defaultIoTManager = [[AWSIoTManager alloc] initWithConfiguration:serviceConfiguration];
    });

    return _defaultIoTManager;
}

+ (void)registerIoTManagerWithConfiguration:(AWSServiceConfiguration *)configuration forKey:(NSString *)key {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serviceClients = [AWSSynchronizedMutableDictionary new];
    });
    [_serviceClients setObject:[[AWSIoTManager alloc] initWithConfiguration:configuration]
                        forKey:key];
}

+ (instancetype)IoTManagerForKey:(NSString *)key {
    @synchronized(self) {
        AWSIoTManager *serviceClient = [_serviceClients objectForKey:key];
        if (serviceClient) {
            return serviceClient;
        }

        AWSServiceInfo *serviceInfo = [[AWSInfo defaultAWSInfo] serviceInfo:AWSInfoIoTManager
                                                                     forKey:key];
        if (serviceInfo) {
            AWSServiceConfiguration *serviceConfiguration = [[AWSServiceConfiguration alloc] initWithRegion:serviceInfo.region
                                                                                        credentialsProvider:serviceInfo.cognitoCredentialsProvider];
            [AWSIoTManager registerIoTManagerWithConfiguration:serviceConfiguration
                                                        forKey:key];
        }

        return [_serviceClients objectForKey:key];
    }
}

+ (void)removeIoTManagerForKey:(NSString *)key {
    [_serviceClients removeObjectForKey:key];
}

- (instancetype)init {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"`- init` is not a valid initializer. Use `+ defaultIoTManager` or `+ IoTManagerForKey:` instead."
                                 userInfo:nil];
    return nil;
}
- (instancetype)initWithConfiguration:(AWSServiceConfiguration *)configuration {
    if (self = [super init]) {
        _configuration = [configuration copy];
        _IoT = [[AWSIoT alloc] initWithConfiguration:_configuration];
    }
    
    return self;
}

- (void)createKeysAndCertificateFromCsr:(NSDictionary *)csrDictionary callback:(void (^)(AWSIoTCreateCertificateResponse *mainResponse))callback {

    NSString *commonName = [csrDictionary objectForKey:@"commonName"];
    NSString *countryName = [csrDictionary objectForKey:@"countryName"];
    NSString *organizationName = [csrDictionary objectForKey:@"organizationName"];
    NSString *organizationalUnitName = [csrDictionary objectForKey:@"organizationalUnitName"];
    
    if ((commonName == nil) || (countryName == nil) || (organizationName == nil) || (organizationalUnitName == nil))
    {
        AWSLogError(@"all CSR dictionary fields must be specified");
        callback(nil);
    }
    
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *publicTag = [AWSIoTKeychain.publicKeyTag stringByAppendingString:uuid];
    NSString *privateTag = [AWSIoTKeychain.privateKeyTag stringByAppendingString:uuid];
    [AWSIoTKeychain generateKeyPairWithPublicTag:publicTag privateTag:privateTag];

    AWSIoTCSR *csr = [[AWSIoTCSR alloc] initWithCommonName: commonName countryName:countryName organizationName: organizationName organizationalUnitName: organizationalUnitName ];
    
    NSData* csrData = [csr generateCSRForCertificate:uuid];

    // Create certificate from CSR
    AWSIoTCreateCertificateFromCsrRequest *request = [[AWSIoTCreateCertificateFromCsrRequest alloc] init];
    request.setAsActive = @YES;

    NSString *certificateSigningRequest = [AWSIoTKeychain base64Encode:csrData];
    AWSLogInfo(@"certificateSigningRequest: %@", certificateSigningRequest);
    request.certificateSigningRequest = certificateSigningRequest;

    [[self.IoT createCertificateFromCsr:request] continueWithBlock:^id(AWSTask *task) {
        NSError *error = task.error;
        AWSLogInfo(@"error: %@", error);
        if (error != nil) {
            callback(nil);
            return nil;
        }
        NSException *exception = task.exception;
        AWSLogInfo(@"exception: %@", exception);
        if (exception != nil) {
            callback(nil);
            return nil;
        }

        AWSLogInfo(@"result: %@", task.result);

        if ([task.result isKindOfClass:[AWSIoTCreateCertificateFromCsrResponse class]]) {

            AWSIoTCreateCertificateFromCsrResponse *response = task.result;

            NSString* certificateArn = response.certificateArn;
            AWSLogInfo(@"certificateArn: %@", certificateArn);

            NSString* certificateId = response.certificateId;
            AWSLogInfo(@"certificateId: %@", certificateId);

            NSString* certificatePem = response.certificatePem;
            AWSLogInfo(@"certificatePem: %@", certificatePem);

            if (certificatePem != nil && certificateArn != nil && certificateId != nil) {
                NSString *newPublicTag = [AWSIoTKeychain.publicKeyTag stringByAppendingString:certificateId];
                NSString *newPrivateTag = [AWSIoTKeychain.privateKeyTag stringByAppendingString:certificateId];

                SecKeyRef publicKeyRef = [AWSIoTKeychain getPublicKeyRef:publicTag];
                SecKeyRef privateKeyRef = [AWSIoTKeychain getPrivateKeyRef:privateTag];

                if ([AWSIoTKeychain deleteAsymmetricKeysWithPublicTag:publicTag privateTag:privateTag]) {
                    if ([AWSIoTKeychain addPrivateKeyRef:privateKeyRef tag:newPrivateTag]) {
                        if ([AWSIoTKeychain addPublicKeyRef:publicKeyRef tag:newPublicTag]) {
                            if ([AWSIoTKeychain addCertificateToKeychain:certificatePem]) {
                                SecIdentityRef secIdentityRef = [AWSIoTKeychain getIdentityRef:newPrivateTag];
                                if (secIdentityRef != nil) {
                                    AWSIoTCreateCertificateResponse* resp = [[AWSIoTCreateCertificateResponse alloc] init];
                                    resp.certificateId = certificateId;
                                    resp.certificatePem = certificatePem;
                                    resp.certificateArn = certificateArn;

                                    callback(resp);
                                } else {
                                    callback(nil);
                                }
                            } else {
                                callback(nil);
                            }
                        } else {
                            callback(nil);
                        }
                    } else {
                        callback(nil);
                    }
                } else {
                    callback(nil);
                }
            } else {
                callback(nil);
            }
        } else {
            callback(nil);
        }

        return nil;
    }];
}

+ (BOOL)importIdentityFromPKCS12Data:(NSData *)pkcs12Data passPhrase:(NSString *)passPhrase certificateId:(NSString *)certificateId;
{
    SecKeyRef privateKey = NULL;
    SecKeyRef publicKey = NULL;
    SecCertificateRef certRef = NULL;
    
    [AWSIoTManager readPk12:pkcs12Data passPhrase:passPhrase certRef:&certRef privateKeyRef:&privateKey publicKeyRef:&publicKey];
    
    NSString *publicTag = [AWSIoTKeychain.publicKeyTag stringByAppendingString:certificateId];
    NSString *privateTag = [AWSIoTKeychain.privateKeyTag stringByAppendingString:certificateId];

    if (![AWSIoTKeychain addPrivateKeyRef:privateKey tag:privateTag])
    {
        AWSLogError(@"Unable to add private key");
        return NO;
    }
    
    if (![AWSIoTKeychain addPublicKeyRef:publicKey tag:publicTag])
    {
        [AWSIoTKeychain deleteAsymmetricKeysWithPublicTag:publicTag privateTag:privateTag];
        
        AWSLogError(@"Unable to add public key");
        return NO;
    }
    
    if(![AWSIoTKeychain addCertificateRef:certRef])
    {
        [AWSIoTKeychain deleteAsymmetricKeysWithPublicTag:publicTag privateTag:privateTag];
        
        AWSLogError(@"Unable to add certificate");
        return NO;
    }
    
    return YES;
}
//
// Helper method to get certificate, public key, and private key references to import into the keychain.
//
+ (BOOL)readPk12:(NSData *)pk12Data passPhrase:(NSString *)passPhrase certRef:(SecCertificateRef *)certRef privateKeyRef:(SecKeyRef *)privateKeyRef publicKeyRef:(SecKeyRef *)publicKeyRef
{
    SecPolicyRef policy = NULL;
    SecTrustRef trust = NULL;
    
    // cleanup stuff in a block so we don't need to do this over and over again.
    static BOOL (^cleanup)();
    static BOOL (^errorCleanup)();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cleanup = ^BOOL {
            if(policy) {
                CFRelease(policy);
            }
        
            if(trust) {
                CFRelease(trust);
            }
        
            return YES;
        };
        
        errorCleanup = ^BOOL {
            *privateKeyRef = NULL;
            *publicKeyRef = NULL;
            *certRef = NULL;
        
            cleanup();
        
            return NO;
        };
    });
    
    CFDictionaryRef secImportOptions = (__bridge CFDictionaryRef) @{(__bridge id) kSecImportExportPassphrase : passPhrase};
    CFArrayRef secImportItems = NULL;
    
    OSStatus status = SecPKCS12Import((__bridge CFDataRef) pk12Data, (CFDictionaryRef) secImportOptions, &secImportItems);
    
    if (status == errSecSuccess && CFArrayGetCount(secImportItems) > 0)
    {
        CFDictionaryRef identityDict = CFArrayGetValueAtIndex(secImportItems, 0);
        SecIdentityRef identityApp = (SecIdentityRef) CFDictionaryGetValue(identityDict, kSecImportItemIdentity);
        
        if (SecIdentityCopyPrivateKey(identityApp, privateKeyRef) != errSecSuccess)
        {
                AWSLogError(@"Unable to copy private key");
                return errorCleanup();
        }
        
        if (SecIdentityCopyCertificate(identityApp, certRef) != errSecSuccess)
        {
                AWSLogError(@"Unable to copy certificate");
                return errorCleanup();
        }
        
        //
        // Create trust management object
        //
        policy = SecPolicyCreateBasicX509();
        status = SecTrustCreateWithCertificates((__bridge CFArrayRef) @[(__bridge id) *certRef], policy, &trust);
        if (status != errSecSuccess)
        {
            AWSLogError(@"Unable to create trust");
            return errorCleanup();
        }
        //
        // Evaluate the trust management object
        //
        SecTrustResultType result;
        if (SecTrustEvaluate(trust, &result) != errSecSuccess)
        {
            AWSLogError(@"Unable to evaluate trust");
            return errorCleanup();
        }
        
        //
        // Try to retrieve a reference to the public key for the trust management object.
        //
        *publicKeyRef = SecTrustCopyPublicKey(trust);
        if(*publicKeyRef == NULL)
        {
            AWSLogError(@"Unable to copy public key");
            return errorCleanup();
        }
    
        return cleanup();
    }
    AWSLogError(@"Unable to import from PKCS12 data");
    return errorCleanup();
}


+ (BOOL)deleteCertificate {
    return [AWSIoTKeychain removeCertificate];
}

+ (BOOL)isValidCertificate:(NSString *)certificateId {
    return [AWSIoTKeychain isValidCertificate:[NSString stringWithFormat:@"%@%@",[AWSIoTKeychain privateKeyTag], certificateId ]];
}

@end
