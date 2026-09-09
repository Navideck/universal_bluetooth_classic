//
//  IOBluetoothPairingControllerObjC.h
//  BT Classic
//
//  Created by Fotios Dimanidis on 13.10.24.
//

#import <Foundation/Foundation.h>
@import IOBluetooth;
@import IOBluetoothUI;

NS_ASSUME_NONNULL_BEGIN

@interface IOBluetoothPairingControllerObjC : NSObject

+ (instancetype)pairingController;
- (int)runModal;
- (NSArray *)getResults;
- (void)setOptions:(IOBluetoothServiceBrowserControllerOptions)options;
- (IOBluetoothServiceBrowserControllerOptions)getOptions;
- (void)setSearchAttributes:(const IOBluetoothDeviceSearchAttributes *)searchAttributes;
- (const IOBluetoothDeviceSearchAttributes *)getSearchAttributes;
- (void)addAllowedUUID:(IOBluetoothSDPUUID *)allowedUUID;
- (void)addAllowedUUIDArray:(NSArray *)allowedUUIDArray;
- (void)clearAllowedUUIDs;
- (void)setTitle:(NSString *)windowTitle;
- (NSString *)getTitle;
- (void)setDescriptionText:(NSString *)descriptionText;
- (NSString *)getDescriptionText;
- (void)setPrompt:(NSString *)prompt;
- (NSString *)getPrompt;

@end

NS_ASSUME_NONNULL_END
