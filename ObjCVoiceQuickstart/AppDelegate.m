//
//  AppDelegate.m
//  Twilio Voice Quickstart - Objective-C
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

#import "AppDelegate.h"

@import TwilioVoice;

@interface AppDelegate ()
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSLog(@"Twilio Voice Version: %@", [TwilioVoice version]);
    [self configureUserNotifications];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)configureUserNotifications {
    UIMutableUserNotificationAction *rejectAction = [[UIMutableUserNotificationAction alloc] init];
    [rejectAction setActivationMode:UIUserNotificationActivationModeBackground];
    [rejectAction setTitle:@"Reject"];
    [rejectAction setIdentifier:@"reject"];
    [rejectAction setDestructive:YES];
    [rejectAction setAuthenticationRequired:NO];

    UIMutableUserNotificationAction *acceptAction = [[UIMutableUserNotificationAction alloc] init];
    [acceptAction setActivationMode:UIUserNotificationActivationModeBackground];
    [acceptAction setTitle:@"Accept"];
    [acceptAction setIdentifier:@"accept"];
    [acceptAction setDestructive:NO];
    [acceptAction setAuthenticationRequired:NO];

    UIMutableUserNotificationCategory *actionCategory = [[UIMutableUserNotificationCategory alloc] init];
    [actionCategory setIdentifier:@"ACTIONABLE"];
    [actionCategory setActions:@[rejectAction, acceptAction]
                    forContext:UIUserNotificationActionContextDefault];

    [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|
                                                                                                                     UIUserNotificationTypeBadge|
                                                                                                                     UIUserNotificationTypeSound
                                                                                                          categories:[NSSet setWithObject:actionCategory]]];

}

@end
