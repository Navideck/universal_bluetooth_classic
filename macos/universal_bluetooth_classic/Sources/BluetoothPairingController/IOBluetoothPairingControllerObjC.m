//
//  IOBluetoothPairingControllerObjC.m
//  BT Classic
//
//  Created by Fotios Dimanidis on 13.10.24.
//

#import "IOBluetoothPairingControllerObjC.h"

@implementation IOBluetoothPairingControllerObjC {
    IOBluetoothPairingController *_pairingController;
}

+ (instancetype)pairingController {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pairingController = [IOBluetoothPairingController pairingController];
    }
    return self;
}

- (int)runModal {
    return [_pairingController runModal];
}

- (NSArray *)getResults {
    return [_pairingController getResults];
}

- (void)setOptions:(IOBluetoothServiceBrowserControllerOptions)options {
    [_pairingController setOptions:options];
}

- (IOBluetoothServiceBrowserControllerOptions)getOptions {
    return [_pairingController getOptions];
}

- (void)setSearchAttributes:(const IOBluetoothDeviceSearchAttributes *)searchAttributes {
    [_pairingController setSearchAttributes:searchAttributes];
}

- (const IOBluetoothDeviceSearchAttributes *)getSearchAttributes {
    return [_pairingController getSearchAttributes];
}

- (void)addAllowedUUID:(IOBluetoothSDPUUID *)allowedUUID {
    [_pairingController addAllowedUUID:allowedUUID];
}

- (void)addAllowedUUIDArray:(NSArray *)allowedUUIDArray {
    [_pairingController addAllowedUUIDArray:allowedUUIDArray];
}

- (void)clearAllowedUUIDs {
    [_pairingController clearAllowedUUIDs];
}

- (void)setTitle:(NSString *)windowTitle {
    [_pairingController setTitle:windowTitle];
}

- (NSString *)getTitle {
    return [_pairingController getTitle];
}

- (void)setDescriptionText:(NSString *)descriptionText {
    [_pairingController setDescriptionText:descriptionText];
}

- (NSString *)getDescriptionText {
    return [_pairingController getDescriptionText];
}

- (void)setPrompt:(NSString *)prompt {
    [_pairingController setPrompt:prompt];
}

- (NSString *)getPrompt {
    return [_pairingController getPrompt];
}

@end
