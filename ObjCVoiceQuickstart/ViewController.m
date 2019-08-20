//
//  ViewController.m
//  Twilio Voice Quickstart - Objective-C
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

#import "ViewController.h"

@import AVFoundation;
@import PushKit;
@import TwilioVoice;
@import UserNotifications;

static NSString *const kYourServerBaseURLString = <#URL TO YOUR ACCESS TOKEN SERVER#>;
static NSString *const kAccessTokenEndpoint = @"/accessToken";
static NSString *const kIdentity = @"alice";
static NSString *const kTwimlParamTo = @"to";

@interface ViewController () <PKPushRegistryDelegate, TVONotificationDelegate, TVOCallDelegate, AVAudioPlayerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) NSString *deviceTokenString;

@property (nonatomic, strong) PKPushRegistry *voipRegistry;
@property (nonatomic, strong) void(^incomingPushCompletionCallback)(void);
@property (nonatomic, strong) TVOCallInvite *callInvite;
@property (nonatomic, strong) TVOCall *call;

@property (nonatomic, weak) IBOutlet UIImageView *iconView;
@property (nonatomic, assign, getter=isSpinning) BOOL spinning;

@property (nonatomic, weak) IBOutlet UIButton *placeCallButton;
@property (nonatomic, weak) IBOutlet UITextField *outgoingValue;
@property (nonatomic, strong) UIAlertController* incomingAlertController;
@property (weak, nonatomic) IBOutlet UIView *callControlView;
@property (weak, nonatomic) IBOutlet UISwitch *muteSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *speakerSwitch;

@property (nonatomic, strong) AVAudioPlayer *ringtonePlayer;
typedef void (^RingtonePlaybackCallback)(void);
@property (nonatomic, strong) RingtonePlaybackCallback ringtonePlaybackCallback;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    self.voipRegistry.delegate = self;
    self.voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];

    [self toggleUIState:YES showCallControl:NO];
    self.outgoingValue.delegate = self;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (NSString *)fetchAccessToken {
    NSString *accessTokenEndpointWithIdentity = [NSString stringWithFormat:@"%@?identity=%@", kAccessTokenEndpoint, kIdentity];
    NSString *accessTokenURLString = [kYourServerBaseURLString stringByAppendingString:accessTokenEndpointWithIdentity];

    NSString *accessToken = [NSString stringWithContentsOfURL:[NSURL URLWithString:accessTokenURLString]
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
    return accessToken;
}

- (IBAction)placeCall:(id)sender {
    if (self.call) {
        [self.call disconnect];
        [self toggleUIState:NO showCallControl:NO];
    } else {
        __weak typeof(self) weakSelf = self;
        [self playOutgoingRingtone:^{
            __strong typeof(self) strongSelf = weakSelf;
            [strongSelf makeCall:strongSelf.outgoingValue.text];
        }];
        
        [self toggleUIState:NO showCallControl:NO];
        [self startSpin];
    }
}

- (void)makeCall:(NSString *)to {
    TVOConnectOptions *connectOptions = [TVOConnectOptions optionsWithAccessToken:[self fetchAccessToken]
                                                                            block:^(TVOConnectOptionsBuilder *builder) {
        builder.params = @{kTwimlParamTo: to};
    }];

    typeof(self) __weak weakSelf = self;
    [self checkRecordPermission:^(BOOL permissionGranted) {
        typeof(self) __strong strongSelf = weakSelf;
        if (!permissionGranted) {
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Voice Quick Start"
                                                                                     message:@"Microphone permission not granted."
                                                                              preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *continueWithoutMic = [UIAlertAction actionWithTitle:@"Continue without microphone"
                                                                         style:UIAlertActionStyleDefault
                                                                       handler:^(UIAlertAction *action) {
                strongSelf.call = [TwilioVoice connectWithOptions:connectOptions delegate:strongSelf];
            }];
            [alertController addAction:continueWithoutMic];
            
            NSDictionary *openURLOptions = @{UIApplicationOpenURLOptionUniversalLinksOnly: @NO};
            UIAlertAction *goToSettings = [UIAlertAction actionWithTitle:@"Settings"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action) {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
                                                   options:openURLOptions
                                         completionHandler:nil];
            }];
            [alertController addAction:goToSettings];
            
            UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel"
                                                             style:UIAlertActionStyleCancel
                                                           handler:^(UIAlertAction *action) {
                [strongSelf toggleUIState:YES showCallControl:NO];
                [strongSelf stopSpin];
            }];
            [alertController addAction:cancel];
            
            [self presentViewController:alertController animated:YES completion:nil];
        } else {
            strongSelf.call = [TwilioVoice connectWithOptions:connectOptions delegate:strongSelf];
        }
    }];
}

- (void)checkRecordPermission:(void(^)(BOOL permissionGranted))completion {
    AVAudioSessionRecordPermission permissionStatus = [[AVAudioSession sharedInstance] recordPermission];
    switch (permissionStatus) {
        case AVAudioSessionRecordPermissionGranted:
            // Record permission already granted.
            completion(YES);
            break;
        case AVAudioSessionRecordPermissionDenied:
            // Record permission denied.
            completion(NO);
            break;
        case AVAudioSessionRecordPermissionUndetermined:
        {
            // Requesting record permission.
            // Optional: pop up app dialog to let the users know if they want to request.
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                completion(granted);
            }];
            break;
        }
        default:
            completion(NO);
            break;
    }
}

- (void)toggleUIState:(BOOL)isEnabled showCallControl:(BOOL)showCallControl {
    self.placeCallButton.enabled = isEnabled;
    if (showCallControl) {
        self.callControlView.hidden = NO;
        self.muteSwitch.on = NO;
        self.speakerSwitch.on = YES;
    } else {
        self.callControlView.hidden = YES;
    }
}

- (IBAction)muteSwitchToggled:(UISwitch *)sender {
    self.call.muted = sender.on;
}

- (IBAction)speakerSwitchToggled:(UISwitch *)sender {
    [self toggleAudioRoute:sender.on];
}

#pragma mark - UITextFieldDelegate
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.outgoingValue resignFirstResponder];
    return YES;
}

#pragma mark - PKPushRegistryDelegate
- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type {
    NSLog(@"pushRegistry:didUpdatePushCredentials:forType:");

    if ([type isEqualToString:PKPushTypeVoIP]) {
        const unsigned *tokenBytes = [credentials.token bytes];
        self.deviceTokenString = [NSString stringWithFormat:@"<%08x %08x %08x %08x %08x %08x %08x %08x>",
                                  ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                                  ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                                  ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];
        NSString *accessToken = [self fetchAccessToken];

        [TwilioVoice registerWithAccessToken:accessToken
                                 deviceToken:self.deviceTokenString
                                  completion:^(NSError *error) {
             if (error) {
                 NSLog(@"An error occurred while registering: %@", [error localizedDescription]);
             }
             else {
                 NSLog(@"Successfully registered for VoIP push notifications.");
             }
         }];
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(PKPushType)type {
    NSLog(@"pushRegistry:didInvalidatePushTokenForType:");

    if ([type isEqualToString:PKPushTypeVoIP]) {
        NSString *accessToken = [self fetchAccessToken];

        [TwilioVoice unregisterWithAccessToken:accessToken
                                   deviceToken:self.deviceTokenString
                                    completion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"An error occurred while unregistering: %@", [error localizedDescription]);
            }
            else {
                NSLog(@"Successfully unregistered for VoIP push notifications.");
            }
        }];

        self.deviceTokenString = nil;
    }
}

/**
 * Try using the `pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:` method if
 * your application is targeting iOS 11. According to the docs, this delegate method is deprecated by Apple.
 */
- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type {
    NSLog(@"pushRegistry:didReceiveIncomingPushWithPayload:forType:");
    if ([type isEqualToString:PKPushTypeVoIP]) {
        if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self]) {
            NSLog(@"This is not a valid Twilio Voice notification.");
        }
    }
}

/**
 * This delegate method is available on iOS 11 and above. Call the completion handler once the
 * notification payload is passed to the `TwilioVoice.handleNotification()` method.
 */
- (void)pushRegistry:(PKPushRegistry *)registry
didReceiveIncomingPushWithPayload:(PKPushPayload *)payload
             forType:(PKPushType)type
withCompletionHandler:(void (^)(void))completion {
    NSLog(@"pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:");

    // Save for later when the notification is properly handled.
    self.incomingPushCompletionCallback = completion;

    if ([type isEqualToString:PKPushTypeVoIP]) {
        if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self]) {
            NSLog(@"This is not a valid Twilio Voice notification.");
        }
    }
}

- (void)incomingPushHandled {
    if (self.incomingPushCompletionCallback) {
        self.incomingPushCompletionCallback();
        self.incomingPushCompletionCallback = nil;
    }
}

#pragma mark - TVONotificationDelegate
- (void)callInviteReceived:(TVOCallInvite *)callInvite {
    NSLog(@"callInviteReceived:");
    
    if (self.callInvite) {
        NSLog(@"A CallInvite is already in progress. Ignoring the incoming CallInvite from %@", callInvite.from);
        [self incomingPushHandled];
        return;
    }
    if (self.call && self.call.state == TVOCallStateConnected) {
        NSLog(@"Already an active call. Ignoring incoming CallInvite from %@", callInvite.from);
        [self incomingPushHandled];
        return;
    }
    
    self.callInvite = callInvite;

    NSString *from = callInvite.from;
    NSString *alertMessage = [NSString stringWithFormat:@"From %@", from];
    
    [self playIncomingRingtone];

    self.incomingAlertController = [UIAlertController alertControllerWithTitle:@"Incoming" message:alertMessage preferredStyle:UIAlertControllerStyleAlert];

    typeof(self) __weak weakSelf = self;

    UIAlertAction *reject = [UIAlertAction actionWithTitle:@"Reject" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) __strong strongSelf = weakSelf;
        [strongSelf stopIncomingRingtone];
        [callInvite reject];
        strongSelf.callInvite = nil;

        strongSelf.incomingAlertController = nil;
        [strongSelf toggleUIState:YES showCallControl:NO];
    }];
    [self.incomingAlertController addAction:reject];

    UIAlertAction *ignore = [UIAlertAction actionWithTitle:@"Ignore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        /* To ignore the call invite, you don't have to do anything but just literally ignore it */
        typeof(self) __strong strongSelf = weakSelf;
        [strongSelf stopIncomingRingtone];

        strongSelf.callInvite = nil;
        strongSelf.incomingAlertController = nil;
        [strongSelf toggleUIState:YES showCallControl:NO];
    }];
    [self.incomingAlertController addAction:ignore];

    UIAlertAction *accept = [UIAlertAction actionWithTitle:@"Accept" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) __strong strongSelf = weakSelf;
        [strongSelf stopIncomingRingtone];
        TVOAcceptOptions *acceptOptions = [TVOAcceptOptions optionsWithCallInvite:strongSelf.callInvite];
        strongSelf.call = [callInvite acceptWithOptions:acceptOptions delegate:strongSelf];
        strongSelf.callInvite = nil;

        strongSelf.incomingAlertController = nil;
        [strongSelf startSpin];
    }];
    [self.incomingAlertController addAction:accept];

    [self toggleUIState:NO showCallControl:NO];
    [self presentViewController:self.incomingAlertController animated:YES completion:nil];

    // If the application is not in the foreground, post a local notification
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = @"Incoming Call";
        content.body = [NSString stringWithFormat:@"Call Invite from %@", callInvite.from];
        content.sound = [UNNotificationSound defaultSound];

        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"VoiceLocaNotification"
                                                                              content:content
                                                                              trigger:nil];
        
        [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
            NSLog(@"Failed to add notification request: %@", error);
        }];
    }

    [self incomingPushHandled];
}

- (void)cancelledCallInviteReceived:(TVOCancelledCallInvite *)cancelledCallInvite {
    NSLog(@"cancelledCallInviteReceived:");
    
    if (!self.callInvite ||
        ![self.callInvite.callSid isEqualToString:cancelledCallInvite.callSid]) {
        NSLog(@"No matching pending CallInvite. Ignoring the Cancelled CallInvite");
        return;
    }
    
    [self stopIncomingRingtone];
    [self playDisconnectSound];

    if (self.incomingAlertController) {
        typeof(self) __weak weakSelf = self;

        [self dismissViewControllerAnimated:YES completion:^{
            typeof(self) __strong strongSelf = weakSelf;
            strongSelf.incomingAlertController = nil;
            [strongSelf toggleUIState:YES showCallControl:NO];
        }];
    }
    
    self.callInvite = nil;

    [[UNUserNotificationCenter currentNotificationCenter] removeAllPendingNotificationRequests];
    
    [self incomingPushHandled];
}

#pragma mark - TVOCallDelegate
- (void)callDidStartRinging:(TVOCall *)call {
    NSLog(@"callDidStartRinging:");
    
    [self.placeCallButton setTitle:@"Ringing" forState:UIControlStateNormal];
}

- (void)callDidConnect:(TVOCall *)call {
    NSLog(@"callDidConnect:");

    self.call = call;
    
    [self.placeCallButton setTitle:@"Hang Up" forState:UIControlStateNormal];
    
    [self toggleUIState:YES showCallControl:YES];
    [self stopSpin];
    [self toggleAudioRoute:YES];
}

- (void)call:(TVOCall *)call isReconnectingWithError:(NSError *)error {
    NSLog(@"Call is reconnecting");
    
    [self.placeCallButton setTitle:@"Reconnecting" forState:UIControlStateNormal];
    [self toggleUIState:NO showCallControl:NO];
}

- (void)callDidReconnect:(TVOCall *)call {
    NSLog(@"Call reconnected");
    
    [self.placeCallButton setTitle:@"Hang Up" forState:UIControlStateNormal];
    [self toggleUIState:YES showCallControl:YES];
}

- (void)call:(TVOCall *)call didFailToConnectWithError:(NSError *)error {
    NSLog(@"Call failed to connect: %@", error);
    
    [self callDisconnected];
}

- (void)call:(TVOCall *)call didDisconnectWithError:(NSError *)error {
    if (error) {
        NSLog(@"Call failed: %@", error);
    } else {
        NSLog(@"Call disconnected");
    }
    
    [self callDisconnected];
}

- (void)callDisconnected {
    self.call = nil;
    
    [self playDisconnectSound];
    [self.placeCallButton setTitle:@"Call" forState:UIControlStateNormal];
    [self toggleUIState:YES showCallControl:NO];
    [self stopSpin];
}

#pragma mark - AVAudioSession
- (void)toggleAudioRoute:(BOOL)toSpeaker {
    // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
    TVODefaultAudioDevice *audioDevice = (TVODefaultAudioDevice *)TwilioVoice.audioDevice;
    audioDevice.block =  ^ {
        // We will execute `kDefaultAVAudioSessionConfigurationBlock` first.
        kTVODefaultAVAudioSessionConfigurationBlock();
        
        // Overwrite the audio route
        AVAudioSession *session = [AVAudioSession sharedInstance];
        NSError *error = nil;
        if (toSpeaker) {
            if (![session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error]) {
                NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
            }
        } else {
            if (![session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error]) {
                NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
            }
        }
    };
    audioDevice.block();
}

#pragma mark - Ringtone player & AVAudioPlayerDelegate
- (void)playOutgoingRingtone:(RingtonePlaybackCallback)completion {
    self.ringtonePlaybackCallback = completion;
    
    NSString *ringtonePath = [[NSBundle mainBundle] pathForResource:@"outgoing" ofType:@"wav"];
    if ([ringtonePath length] <= 0) {
        NSLog(@"Can't find outgoing sound file");
        if (self.ringtonePlaybackCallback) {
            self.ringtonePlaybackCallback();
        }
        return;
    }
    
    self.ringtonePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:ringtonePath] error:nil];
    self.ringtonePlayer.delegate = self;
    
    [self playRingtone];
}

- (void)playIncomingRingtone {
    NSString *ringtonePath = [[NSBundle mainBundle] pathForResource:@"incoming" ofType:@"wav"];
    if ([ringtonePath length] <= 0) {
        NSLog(@"Can't find incoming sound file");
        return;
    }
    
    self.ringtonePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:ringtonePath] error:nil];
    self.ringtonePlayer.delegate = self;
    self.ringtonePlayer.numberOfLoops = -1;
    
    [self playRingtone];
}

- (void)stopIncomingRingtone {
    if (!self.ringtonePlayer.isPlaying) {
        return;
    }
    
    [self.ringtonePlayer stop];
    NSError *error = nil;
    if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                                error:&error]) {
        NSLog(@"Failed to reset AVAudioSession category: %@", [error localizedDescription]);
    }
}

- (void)playDisconnectSound {
    NSString *ringtonePath = [[NSBundle mainBundle] pathForResource:@"disconnect" ofType:@"wav"];
    if ([ringtonePath length] <= 0) {
        NSLog(@"Can't find disconnect sound file");
        return;
    }
    
    self.ringtonePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:ringtonePath] error:nil];
    self.ringtonePlayer.delegate = self;
    self.ringtonePlaybackCallback = nil;
    
    [self playRingtone];
}

- (void)playRingtone {
    NSError *error = nil;
    if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                                error:&error]) {
        NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
    }
    
    self.ringtonePlayer.volume = 1.0f;
    [self.ringtonePlayer play];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if (self.ringtonePlaybackCallback) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) strongSelf = weakSelf;
            strongSelf.ringtonePlaybackCallback();
        });
        
        NSError *error = nil;
        if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                                    error:&error]) {
            NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
        }
    }
}

#pragma mark - Icon spinning
- (void)startSpin {
    if (!self.isSpinning) {
        self.spinning = YES;
        [self spinWithOptions:UIViewAnimationOptionCurveEaseIn];
    }
}

- (void)stopSpin {
    self.spinning = NO;
}

- (void)spinWithOptions:(UIViewAnimationOptions)options {
    typeof(self) __weak weakSelf = self;

    [UIView animateWithDuration:0.5f
                          delay:0.0f
                        options:options
                     animations:^{
                         typeof(self) __strong strongSelf = weakSelf;
                         strongSelf.iconView.transform = CGAffineTransformRotate(strongSelf.iconView.transform, M_PI / 2);
                     }
                     completion:^(BOOL finished) {
                         typeof(self) __strong strongSelf = weakSelf;
                         if (finished) {
                             if (strongSelf.isSpinning) {
                                 [strongSelf spinWithOptions:UIViewAnimationOptionCurveLinear];
                             } else if (options != UIViewAnimationOptionCurveEaseOut) {
                                 [strongSelf spinWithOptions:UIViewAnimationOptionCurveEaseOut];
                             }
                         }
                     }];
}


@end
