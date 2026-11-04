//
//  iOS7Compat.m
//  SuccessionRestore
//
//  iOS 7 compatibility layer for UIAlertController, NSString, and TLS/Key fetching.
//

#import "iOS7Compat.h"
#import <objc/runtime.h>
#import <stdio.h>

#undef UIAlertController
#undef UIAlertAction

#pragma mark - NSString (SRiOS7Compatibility)

static BOOL SR_NSString_containsString(NSString *self, SEL _cmd, NSString *str) {
    if (!str) {
        return NO;
    }
    return [self rangeOfString:str].location != NSNotFound;
}

static void SR_UIViewController_showViewController(UIViewController *self, SEL _cmd, UIViewController *vc, id sender) {
    if (!vc) return;
    UINavigationController *nav = self.navigationController;
    if (!nav && [self isKindOfClass:[UINavigationController class]]) {
        nav = (UINavigationController *)self;
    }
    if (nav) {
        [nav pushViewController:vc animated:YES];
    } else {
        [self presentViewController:vc animated:YES completion:nil];
    }
}

static UIStoryboardSegue *SR_ShowSegueTemplate_segueWithDest(id self, SEL _cmd, UIViewController *destVC) {
    UIViewController *srcVC = [self valueForKey:@"viewController"];
    NSString *ident = [self valueForKey:@"identifier"];
    return [UIStoryboardSegue segueWithIdentifier:ident source:srcVC destination:destVC performHandler:^{
        UINavigationController *nav = srcVC.navigationController;
        if (!nav && [srcVC isKindOfClass:[UINavigationController class]]) {
            nav = (UINavigationController *)srcVC;
        }
        if (nav) {
            [nav pushViewController:destVC animated:YES];
        } else {
            [srcVC presentViewController:destVC animated:YES completion:nil];
        }
    }];
}

#pragma mark - SRAlertAction

@interface SRAlertAction ()
@property (nonatomic, copy, readwrite, nullable) NSString *title;
@property (nonatomic, assign, readwrite) UIAlertActionStyle style;
@property (nonatomic, copy, readwrite, nullable) void (^handler)(SRAlertAction *action);
@end

@implementation SRAlertAction

+ (instancetype)actionWithTitle:(NSString *)title
                          style:(UIAlertActionStyle)style
                        handler:(void (^)(SRAlertAction *action))handler {
    SRAlertAction *action = [[SRAlertAction alloc] init];
    action.title = title;
    action.style = style;
    action.handler = handler;

    Class nativeActionClass = NSClassFromString(@"UIAlertAction");
    if (nativeActionClass) {
        __weak typeof(action) weakAction = action;
        action.nativeAction = [nativeActionClass actionWithTitle:title
                                                           style:style
                                                         handler:^(id _Nonnull nativeAct) {
            __strong typeof(weakAction) strongAction = weakAction;
            if (handler && strongAction) {
                handler(strongAction);
            }
        }];
    }
    return action;
}

@end

#pragma mark - SRAlertController

@interface SRAlertController ()
@property (nonatomic, copy, nullable) NSString *alertTitle;
@property (nonatomic, copy, nullable) NSString *alertMessage;
@property (nonatomic, assign, readwrite) UIAlertControllerStyle preferredStyle;
@property (nonatomic, strong) NSMutableArray<SRAlertAction *> *mutableActions;
@property (nonatomic, strong) NSMutableArray<void (^)(UITextField *)> *textFieldConfigHandlers;
@property (nonatomic, strong, nullable) NSArray<UITextField *> *configuredTextFields;
@property (nonatomic, strong, nullable) UIAlertView *legacyAlertView;
@property (nonatomic, strong, nullable) UIActionSheet *legacyActionSheet;
@property (nonatomic, strong, nullable) SRAlertController *selfRetain;
@end

@implementation SRAlertController

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. Add -[NSString containsString:] on iOS 7 where it does not exist
        if (![NSString instancesRespondToSelector:@selector(containsString:)]) {
            char types[8];
            snprintf(types, sizeof(types), "%s@:@", @encode(BOOL));
            class_addMethod([NSString class], @selector(containsString:), (IMP)SR_NSString_containsString, types);
        }

        // 2. Add -[UIViewController showViewController:sender:] & UIStoryboardShowSegueTemplate on iOS 7
        if (![UIViewController instancesRespondToSelector:@selector(showViewController:sender:)]) {
            class_addMethod([UIViewController class], @selector(showViewController:sender:), (IMP)SR_UIViewController_showViewController, "v@:@@");
        }
        if (objc_getClass("UIStoryboardShowSegueTemplate") == nil) {
            Class baseSegueTemplate = objc_getClass("UIStoryboardSegueTemplate");
            if (baseSegueTemplate) {
                Class showTemplateCls = objc_allocateClassPair(baseSegueTemplate, "UIStoryboardShowSegueTemplate", 0);
                if (showTemplateCls) {
                    class_addMethod(showTemplateCls, NSSelectorFromString(@"segueWithDestinationViewController:"), (IMP)SR_ShowSegueTemplate_segueWithDest, "@@:@");
                    objc_registerClassPair(showTemplateCls);
                }
            }
        }

        // 3. Swizzle -[UIViewController presentViewController:animated:completion:] to intercept SRAlertController
        Class vcClass = [UIViewController class];
        SEL originalSel = @selector(presentViewController:animated:completion:);
        SEL swizzledSel = @selector(sr_presentViewController:animated:completion:);

        Method originalMethod = class_getInstanceMethod(vcClass, originalSel);
        Method swizzledMethod = class_getInstanceMethod(vcClass, swizzledSel);
        if (originalMethod && swizzledMethod) {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

+ (instancetype)alertControllerWithTitle:(NSString *)title
                                 message:(NSString *)message
                          preferredStyle:(UIAlertControllerStyle)preferredStyle {
    SRAlertController *controller = [[SRAlertController alloc] init];
    controller.alertTitle = title;
    controller.alertMessage = message;
    controller.preferredStyle = preferredStyle;
    controller.mutableActions = [NSMutableArray array];
    controller.textFieldConfigHandlers = [NSMutableArray array];

    Class nativeAlertClass = NSClassFromString(@"UIAlertController");
    if (nativeAlertClass) {
        controller.nativeAlertController = [nativeAlertClass alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:preferredStyle];
    }
    return controller;
}

- (NSArray<SRAlertAction *> *)actions {
    return [self.mutableActions copy];
}

- (NSArray<UITextField *> *)textFields {
    if (self.nativeAlertController) {
        return [(id)self.nativeAlertController textFields];
    }
    return self.configuredTextFields;
}

- (void)addAction:(SRAlertAction *)action {
    if (!action) return;
    [self.mutableActions addObject:action];
    if (self.nativeAlertController && action.nativeAction) {
        [(id)self.nativeAlertController addAction:action.nativeAction];
    }
}

- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *textField))configurationHandler {
    if (self.nativeAlertController) {
        [(id)self.nativeAlertController addTextFieldWithConfigurationHandler:configurationHandler];
        return;
    }
    if (configurationHandler) {
        [self.textFieldConfigHandlers addObject:[configurationHandler copy]];
    } else {
        [self.textFieldConfigHandlers addObject:^(UITextField *tf) {}];
    }
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion {
    if (self.nativeAlertController) {
        [self.nativeAlertController dismissViewControllerAnimated:flag completion:completion];
        return;
    }
    if (completion) {
        completion();
    }
}

- (void)presentFromViewController:(UIViewController *)viewController
                         animated:(BOOL)animated
                       completion:(void (^)(void))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentFromViewController:viewController animated:animated completion:completion];
        });
        return;
    }

    self.selfRetain = self;

    if (self.preferredStyle == UIAlertControllerStyleActionSheet) {
        NSString *sheetTitle = self.alertTitle;
        if (self.alertTitle.length > 0 && self.alertMessage.length > 0) {
            sheetTitle = [NSString stringWithFormat:@"%@\n%@", self.alertTitle, self.alertMessage];
        } else if (self.alertMessage.length > 0) {
            sheetTitle = self.alertMessage;
        }
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:sheetTitle
                                                           delegate:self
                                                  cancelButtonTitle:nil
                                             destructiveButtonTitle:nil
                                                  otherButtonTitles:nil];
        for (SRAlertAction *action in self.mutableActions) {
            NSInteger idx = [sheet addButtonWithTitle:action.title ?: @""];
            if (action.style == UIAlertActionStyleDestructive) {
                sheet.destructiveButtonIndex = idx;
            } else if (action.style == UIAlertActionStyleCancel) {
                sheet.cancelButtonIndex = idx;
            }
        }
        self.legacyActionSheet = sheet;
        UIView *targetView = viewController.view.window ? viewController.view : [[UIApplication sharedApplication] keyWindow];
        if (targetView) {
            [sheet showInView:targetView];
        }
    } else {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:self.alertTitle
                                                            message:self.alertMessage
                                                           delegate:self
                                                  cancelButtonTitle:nil
                                                  otherButtonTitles:nil];
        if (self.textFieldConfigHandlers.count > 0) {
            alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
            UITextField *textField = [alertView textFieldAtIndex:0];
            if (textField) {
                for (void (^handler)(UITextField *) in self.textFieldConfigHandlers) {
                    handler(textField);
                }
                self.configuredTextFields = @[textField];
            }
        }
        for (SRAlertAction *action in self.mutableActions) {
            NSInteger idx = [alertView addButtonWithTitle:action.title ?: @""];
            if (action.style == UIAlertActionStyleCancel) {
                alertView.cancelButtonIndex = idx;
            }
        }
        if (self.mutableActions.count == 0) {
            [alertView addButtonWithTitle:@"OK"];
        }
        self.legacyAlertView = alertView;
        [alertView show];
    }

    if (completion) {
        completion();
    }
}

#pragma mark - UIAlertViewDelegate & UIActionSheetDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    SRAlertAction *selectedAction = nil;
    if (buttonIndex >= 0 && buttonIndex < (NSInteger)self.mutableActions.count) {
        selectedAction = self.mutableActions[buttonIndex];
    }
    self.legacyAlertView = nil;
    SRAlertController *retainedSelf = self.selfRetain;
    self.selfRetain = nil;
    if (selectedAction && selectedAction.handler) {
        selectedAction.handler(selectedAction);
    }
    (void)retainedSelf;
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    SRAlertAction *selectedAction = nil;
    if (buttonIndex >= 0 && buttonIndex < (NSInteger)self.mutableActions.count) {
        selectedAction = self.mutableActions[buttonIndex];
    }
    self.legacyActionSheet = nil;
    SRAlertController *retainedSelf = self.selfRetain;
    self.selfRetain = nil;
    if (selectedAction && selectedAction.handler) {
        selectedAction.handler(selectedAction);
    }
    (void)retainedSelf;
}

@end

#pragma mark - UIViewController Swizzling for SRAlertController

@implementation UIViewController (SRAlertPresentation)

- (void)sr_presentViewController:(UIViewController *)viewControllerToPresent
                        animated:(BOOL)flag
                      completion:(void (^)(void))completion {
    if ([viewControllerToPresent isKindOfClass:[SRAlertController class]]) {
        SRAlertController *srAlert = (SRAlertController *)viewControllerToPresent;
        if (srAlert.nativeAlertController) {
            [self sr_presentViewController:srAlert.nativeAlertController animated:flag completion:completion];
        } else {
            [srAlert presentFromViewController:self animated:flag completion:completion];
        }
        return;
    }
    [self sr_presentViewController:viewControllerToPresent animated:flag completion:completion];
}

@end

#pragma mark - SRNetworkHelper (TLS & RootFS Key Fetching for iOS 7+)

@interface SRTrustingSessionDelegate : NSObject <NSURLSessionDelegate>
@end

@implementation SRTrustingSessionDelegate

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust] &&
        challenge.protectionSpace.serverTrust != NULL) {
        // On legacy iOS (e.g., iOS 7-9), modern root CAs (ISRG Root X1, etc.) may be missing from the system trust store.
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        return;
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

@end

@implementation SRNetworkHelper

+ (NSData *)fetchDataSynchronouslyFromURL:(NSURL *)url error:(NSError **)error {
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"SRNetworkHelperErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        }
        return nil;
    }

    __block NSData *resultData = nil;
    __block NSError *resultError = nil;
    __block NSInteger statusCode = 0;

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 30.0;
    config.timeoutIntervalForResource = 60.0;

    SRTrustingSessionDelegate *delegate = [[SRTrustingSessionDelegate alloc] init];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:30.0];
    [request setValue:@"SuccessionRestore/1.4 (iOS)" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable taskError) {
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = [(NSHTTPURLResponse *)response statusCode];
        }
        resultData = data;
        resultError = taskError;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];

    if (resultError) {
        if (error) *error = resultError;
        return nil;
    }
    if (statusCode >= 400) {
        if (error) {
            *error = [NSError errorWithDomain:@"SRNetworkHelperErrorDomain"
                                         code:statusCode
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP Error %ld from %@", (long)statusCode, url.host ?: url.absoluteString]}];
        }
        return nil;
    }
    return resultData;
}

+ (NSString *)cachedRootFSKeyPath {
    return @"/var/mobile/Media/Succession/rfs_key.plist";
}

+ (NSString *)extractKeyFromWikiHTML:(NSString *)html {
    if (!html || html.length == 0) return nil;
    if ([html containsString:@"RootFS"] && [html containsString:@"Not Encrypted"]) {
        return @"Not Encrypted";
    }
    NSRange keyTagRange = [html rangeOfString:@"id=\"keypage-rootfs-key\">"];
    if (keyTagRange.location == NSNotFound) {
        return nil;
    }
    NSString *afterTag = [html substringFromIndex:NSMaxRange(keyTagRange)];
    NSRange closeCodeRange = [afterTag rangeOfString:@"</code>"];
    if (closeCodeRange.location == NSNotFound) {
        return nil;
    }
    NSString *key = [[afterTag substringToIndex:closeCodeRange.location]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return key.length > 0 ? key : nil;
}

+ (NSString *)fetchRootFSKeyForDeviceModel:(NSString *)deviceModel
                              buildVersion:(NSString *)deviceBuild
                                     error:(NSError **)error {
    if (deviceModel.length == 0 || deviceBuild.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SRNetworkHelperErrorDomain"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing device model or build version"}];
        }
        return nil;
    }

    // 1. Check local cached RootFS key first (allows offline decryption in DecryptViewController)
    NSDictionary *cachedDict = [NSDictionary dictionaryWithContentsOfFile:[self cachedRootFSKeyPath]];
    if ([cachedDict isKindOfClass:[NSDictionary class]]) {
        NSString *cachedModel = cachedDict[@"deviceModel"];
        NSString *cachedBuild = cachedDict[@"deviceBuild"];
        NSString *cachedKey = cachedDict[@"key"];
        if ([cachedModel isEqualToString:deviceModel] &&
            [cachedBuild isEqualToString:deviceBuild] &&
            cachedKey.length > 0) {
            return cachedKey;
        }
    }

    NSError *lastError = nil;

    // 2. Query IPSW.me v4 keys API: https://api.ipsw.me/v4/keys/ipsw/{model}/{build}
    NSURL *ipswKeysURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.ipsw.me/v4/keys/ipsw/%@/%@", deviceModel, deviceBuild]];
    NSData *ipswKeysData = [self fetchDataSynchronouslyFromURL:ipswKeysURL error:&lastError];
    if (ipswKeysData.length > 0) {
        id jsonObj = [NSJSONSerialization JSONObjectWithData:ipswKeysData options:0 error:nil];
        NSArray *keysArray = nil;
        if ([jsonObj isKindOfClass:[NSDictionary class]] && [((NSDictionary *)jsonObj)[@"keys"] isKindOfClass:[NSArray class]]) {
            keysArray = ((NSDictionary *)jsonObj)[@"keys"];
        } else if ([jsonObj isKindOfClass:[NSArray class]]) {
            keysArray = (NSArray *)jsonObj;
        }
        if (keysArray) {
            for (id item in keysArray) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *entry = (NSDictionary *)item;
                NSString *imageName = [entry[@"image"] isKindOfClass:[NSString class]] ? entry[@"image"] : @"";
                NSString *keyString = [entry[@"key"] isKindOfClass:[NSString class]] ? entry[@"key"] : @"";
                if (([imageName caseInsensitiveCompare:@"RootFS"] == NSOrderedSame ||
                     [imageName caseInsensitiveCompare:@"RootFileSystem"] == NSOrderedSame) &&
                    keyString.length > 0) {
                    if ([keyString caseInsensitiveCompare:@"Not Encrypted"] == NSOrderedSame ||
                        [keyString caseInsensitiveCompare:@"Unencrypted"] == NSOrderedSame) {
                        return @"Not Encrypted";
                    }
                    NSDictionary *toCache = @{
                        @"deviceModel": deviceModel,
                        @"deviceBuild": deviceBuild,
                        @"key": keyString
                    };
                    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Media/Succession"
                                              withIntermediateDirectories:YES
                                                               attributes:nil
                                                                    error:nil];
                    [toCache writeToFile:[self cachedRootFSKeyPath] atomically:YES];
                    return keyString;
                }
            }
        }
    }

    // 3. Fallback: Obtain codename from IPSW.me v2 API and query TheAppleWiki / TheiPhoneWiki
    NSURL *codenameURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.ipsw.me/v2/%@/%@/info.json", deviceModel, deviceBuild]];
    NSData *codenameData = [self fetchDataSynchronouslyFromURL:codenameURL error:&lastError];
    if (codenameData.length > 0) {
        NSDictionary *ipswInfo = [NSJSONSerialization JSONObjectWithData:codenameData options:0 error:nil];
        NSString *codename = nil;
        if ([ipswInfo isKindOfClass:[NSDictionary class]] && [ipswInfo[@"codename"] isKindOfClass:[NSString class]]) {
            codename = ipswInfo[@"codename"];
        }
        if (codename.length > 0) {
            NSArray<NSString *> *wikiTemplates = @[
                @"https://theapplewiki.com/wiki/Keys:%@_%@_(%@)",
                @"https://theapplewiki.com/wiki/%@_%@_(%@)",
                @"https://www.theiphonewiki.com/wiki/Keys:%@_%@_(%@)",
                @"https://www.theiphonewiki.com/wiki/%@_%@_(%@)"
            ];
            for (NSString *templateStr in wikiTemplates) {
                NSString *urlString = [NSString stringWithFormat:templateStr, codename, deviceBuild, deviceModel];
                NSURL *wikiURL = [NSURL URLWithString:urlString];
                NSData *wikiData = [self fetchDataSynchronouslyFromURL:wikiURL error:&lastError];
                if (wikiData.length > 0) {
                    NSString *html = [[NSString alloc] initWithData:wikiData encoding:NSUTF8StringEncoding];
                    if (!html) {
                        html = [[NSString alloc] initWithData:wikiData encoding:NSISOLatin1StringEncoding];
                    }
                    NSString *extractedKey = [self extractKeyFromWikiHTML:html];
                    if (extractedKey.length > 0) {
                        if (![extractedKey isEqualToString:@"Not Encrypted"]) {
                            NSDictionary *toCache = @{
                                @"deviceModel": deviceModel,
                                @"deviceBuild": deviceBuild,
                                @"key": extractedKey
                            };
                            [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Media/Succession"
                                                      withIntermediateDirectories:YES
                                                                       attributes:nil
                                                                            error:nil];
                            [toCache writeToFile:[self cachedRootFSKeyPath] atomically:YES];
                        }
                        return extractedKey;
                    }
                }
            }
        }
    }

    if (error) {
        *error = lastError ?: [NSError errorWithDomain:@"SRNetworkHelperErrorDomain"
                                                  code:-3
                                              userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not find RootFS decryption key for %@ (%@)", deviceModel, deviceBuild]}];
    }
    return nil;
}

@end
