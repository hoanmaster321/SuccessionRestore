//
//  DecryptViewController.m
//  SuccessionRestore
//
//  Created by Sam Gardner on 8/30/19.
//  Copyright © 2019 Sam Gardner. All rights reserved.
//

#import "DecryptViewController.h"
#include <sys/sysctl.h>
#import "NSTask.h"
#import "iOS7Compat.h"

@interface DecryptViewController ()

@end

@implementation DecryptViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _successionPrefs = [NSDictionary dictionaryWithContentsOfFile:@"/private/var/mobile/Library/Preferences/com.samgisaninja.SuccessionRestore.plist"];
    // Create a size_t and set it to the size used to allocate modelChar
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    
    //Gets iOS device model (ex iPhone9,1 == iPhone 7 GSM).
    char *modelChar = malloc(size);
    sysctlbyname("hw.machine", modelChar, &size, NULL, 0);
    _deviceModel = [NSString stringWithUTF8String:modelChar];
    free(modelChar);
    
    //Gets iOS version and changes label.
    _deviceVersion = [[UIDevice currentDevice] systemVersion];
    
    // Set size to the size used to allocate buildChar
    sysctlbyname("kern.osversion", NULL, &size, NULL, 0);
    
    //Gets iOS device build number (ex 10.1.1 == 14B100 or 14B150) and changes label.
    //Thanks, Apple, for releasing two versions of 10.1.1, you really like making things hard on us.
    char *buildChar = malloc(size);
    sysctlbyname("kern.osversion", buildChar, &size, NULL, 0);
    _deviceBuild = [NSString stringWithUTF8String:buildChar];
    free(buildChar);

    NSString *bundledDmgPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"dmg"];
    NSString *dmgBinaryPath = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/dmg"]) {
        dmgBinaryPath = @"/usr/bin/dmg";
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:bundledDmgPath]) {
        dmgBinaryPath = bundledDmgPath;
    }
    if (!dmgBinaryPath) {
        UIAlertController *needsXPwn = [UIAlertController alertControllerWithTitle:@"Succession requires additional components to be installed" message:@"Please install xpwn from the saurik/Telesphoreo repo." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"Exit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }];
        [needsXPwn addAction:exitAction];
        [self presentViewController:needsXPwn animated:TRUE completion:nil];
        return;
    }

    [[self activityLabel] setText:@"Fetching RootFS decryption key..."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *rfsKey = [self getRFSKey];
        if (!rfsKey || [rfsKey isEqualToString:@"Failed."]) {
            return;
        }
        if ([rfsKey isEqualToString:@"Not Encrypted"]) {
            [[NSFileManager defaultManager] moveItemAtPath:@"/var/mobile/Media/Succession/encrypted.dmg" toPath:@"/var/mobile/Media/Succession/rfs.dmg" error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *downloadComplete = [UIAlertController alertControllerWithTitle:@"Decrypt Complete" message:@"The rootfilesystem is not encrypted and is ready to use." preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *backToHomePage = [UIAlertAction actionWithTitle:@"Back" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [[self navigationController] popToRootViewControllerAnimated:TRUE];
                }];
                [downloadComplete addAction:backToHomePage];
                [self presentViewController:downloadComplete animated:TRUE completion:nil];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[self activityLabel] setText:@"Decrypting RootFS DMG (this may take several minutes)..."];
            NSTask *decryptDMGTask = [[NSTask alloc] init];
            [decryptDMGTask setArguments:[NSArray arrayWithObjects:dmgBinaryPath, @"extract", @"/var/mobile/Media/Succession/encrypted.dmg", @"/var/mobile/Media/Succession/rfs.dmg", @"-k", rfsKey, nil]];
            NSPipe *outputPipe = [NSPipe pipe];
            [decryptDMGTask setStandardOutput:outputPipe];
            [decryptDMGTask setStandardError:outputPipe];
            NSFileHandle *stdoutHandle = [outputPipe fileHandleForReading];
            [stdoutHandle waitForDataInBackgroundAndNotify];
            __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSFileHandleDataAvailableNotification
                                                                                    object:stdoutHandle queue:nil
                                                                                usingBlock:^(NSNotification *note)
                        {
                            NSData *dataRead = [stdoutHandle availableData];
                            if (dataRead.length > 0) {
                                NSString *stringRead = [[NSString alloc] initWithData:dataRead encoding:NSUTF8StringEncoding];
                                if (stringRead.length > 0) {
                                    [self logToFile:stringRead atLineNumber:__LINE__];
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [[self activityLabel] setText:stringRead];
                                    });
                                }
                                [stdoutHandle waitForDataInBackgroundAndNotify];
                            } else if (observer) {
                                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                                observer = nil;
                            }
                        }];
            [decryptDMGTask setLaunchPath:[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"succdatroot"]];
            [self logToFile:@"launchpath set" atLineNumber:__LINE__];
            decryptDMGTask.terminationHandler = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (observer) {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        observer = nil;
                    }
                    unsigned long long rfsSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:@"/var/mobile/Media/Succession/rfs.dmg" error:nil] fileSize];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Media/Succession/rfs.dmg"] && rfsSize > 100000000ULL) {
                        [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Media/Succession/encrypted.dmg" error:nil];
                        UIAlertController *downloadComplete = [UIAlertController alertControllerWithTitle:@"Decrypt Complete" message:@"The rootfilesystem was successfully decrypted" preferredStyle:UIAlertControllerStyleAlert];
                        UIAlertAction *backToHomePage = [UIAlertAction actionWithTitle:@"Back" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            [[self navigationController] popToRootViewControllerAnimated:TRUE];
                        }];
                        [downloadComplete addAction:backToHomePage];
                        [self presentViewController:downloadComplete animated:TRUE completion:nil];
                    } else {
                        [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Media/Succession/rfs.dmg" error:nil];
                        [self errorAlert:@"Failed to decrypt DMG. Please make sure xpwn is installed and that you have enough free disk space."];
                    }
                });
            };
            [self logToFile:@"Launching dmg task..." atLineNumber:__LINE__];
            [decryptDMGTask launch];
        });
    });
}

-(NSString *)getRFSKey{
    NSError *keyError = nil;
    NSString *extractedKey = [SRNetworkHelper fetchRootFSKeyForDeviceModel:_deviceModel
                                                              buildVersion:_deviceBuild
                                                                     error:&keyError];
    if (extractedKey.length > 0) {
        [self logToFile:[NSString stringWithFormat:@"Obtained RootFS key for %@ (%@): %@", _deviceModel, _deviceBuild, extractedKey] atLineNumber:__LINE__];
        return extractedKey;
    }

    [self logToFile:[NSString stringWithFormat:@"Key for %@ %@ not available (%@).", _deviceModel, _deviceBuild, keyError.localizedDescription ?: @"Unknown error"] atLineNumber:__LINE__];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *deviceNotSupported = [UIAlertController alertControllerWithTitle:@"Device not supported." message:@"The filesystem for your iOS version is encrypted, and a decryption key could not be retrieved. If you have the RootFS key, you can decrypt the DMG yourself using xpwn and place it in /var/mobile/Media/Succession/rfs.dmg." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"Exit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }];
        [deviceNotSupported addAction:exitAction];
        [self presentViewController:deviceNotSupported animated:TRUE completion:nil];
    });
    return @"Failed.";
}


-(void)errorAlert:(NSString *)message{
    [self logToFile:[NSString stringWithFormat:@"ERROR! %@", message] atLineNumber:__LINE__];
    UIAlertController *errorAlertController = [UIAlertController alertControllerWithTitle:@"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"Exit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        exit(0);
    }];
    [errorAlertController addAction:exitAction];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:errorAlertController animated:TRUE completion:nil];
    });
}

- (void)logToFile:(NSString *)message atLineNumber:(int)lineNum {
    if ([[_successionPrefs objectForKey:@"log-file"] isEqual:@(1)]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/mobile/succession.log"]) {
            [[NSFileManager defaultManager] createFileAtPath:@"/private/var/mobile/succession.log" contents:nil attributes:nil];
        }
        NSString *stringToLog = [NSString stringWithFormat:@"[SUCCESSIONLOG %@: %@] Line %@: %@\n", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [NSDate date], [NSString stringWithFormat:@"%d", lineNum], message];
        NSLog(@"%@", stringToLog);
        NSFileHandle *logFileHandle = [NSFileHandle fileHandleForWritingAtPath:@"/private/var/mobile/succession.log"];
        [logFileHandle seekToEndOfFile];
        [logFileHandle writeData:[stringToLog dataUsingEncoding:NSUTF8StringEncoding]];
        [logFileHandle closeFile];
    }
}

@end
