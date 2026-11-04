//
//  iOS7Compat.h
//  SuccessionRestore
//
//  iOS 7 compatibility layer for UIAlertController, NSString, and TLS/Key fetching.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface NSString (SRiOS7Compatibility)
- (BOOL)containsString:(NSString *)str;
@end

@class SRAlertAction;

@interface SRAlertAction : NSObject
@property (nonatomic, readonly, nullable) NSString *title;
@property (nonatomic, readonly) UIAlertActionStyle style;
@property (nonatomic, copy, readonly, nullable) void (^handler)(SRAlertAction *action);
@property (nonatomic, strong, nullable) id nativeAction;

+ (instancetype)actionWithTitle:(nullable NSString *)title
                          style:(UIAlertActionStyle)style
                        handler:(void (^ __nullable)(SRAlertAction *action))handler;
@end

@interface SRAlertController : UIViewController <UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, readonly) UIAlertControllerStyle preferredStyle;
@property (nonatomic, readonly) NSArray<SRAlertAction *> *actions;
@property (nonatomic, readonly, nullable) NSArray<UITextField *> *textFields;
@property (nonatomic, strong, nullable) UIViewController *nativeAlertController;

+ (instancetype)alertControllerWithTitle:(nullable NSString *)title
                                 message:(nullable NSString *)message
                          preferredStyle:(UIAlertControllerStyle)preferredStyle;

- (void)addAction:(SRAlertAction *)action;
- (void)addTextFieldWithConfigurationHandler:(void (^ __nullable)(UITextField *textField))configurationHandler;
- (void)presentFromViewController:(UIViewController *)viewController
                         animated:(BOOL)animated
                       completion:(void (^ __nullable)(void))completion;
@end

@interface SRNetworkHelper : NSObject
+ (nullable NSData *)fetchDataSynchronouslyFromURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
+ (nullable NSString *)fetchRootFSKeyForDeviceModel:(NSString *)deviceModel
                                       buildVersion:(NSString *)deviceBuild
                                              error:(NSError * _Nullable * _Nullable)error;
@end

// Map UIAlertController and UIAlertAction to our iOS 7-compatible wrapper across the project
#define UIAlertController SRAlertController
#define UIAlertAction SRAlertAction
