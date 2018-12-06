//
//  ViewController.m
//  Twilio Voice with CallKit Quickstart - Objective-C
//
//  Copyright © 2016-2018 Twilio, Inc. All rights reserved.
//

#import "ViewController.h"

@import AVFoundation;
@import PushKit;
@import CallKit;
@import TwilioVoice;

static NSString *const kYourServerBaseURLString = <#URL TO YOUR ACCESS TOKEN SERVER#>;
// If your token server is written in PHP, kAccessTokenEndpoint needs .php extension at the end. For example : /accessToken.php
static NSString *const kAccessTokenEndpoint = @"/accessToken";
static NSString *const kIdentity = @"alice";
static NSString *const kTwimlParamTo = @"to";

@interface ViewController () <PKPushRegistryDelegate, TVONotificationDelegate, TVOCallDelegate, CXProviderDelegate, UITextFieldDelegate>
@property (nonatomic, strong) NSString *deviceTokenString;

@property (nonatomic, strong) PKPushRegistry *voipRegistry;
@property (nonatomic, strong) TVOCallInvite *callInvite;
@property (nonatomic, strong) TVOCall *call;
@property (nonatomic, strong) void(^callKitCompletionCallback)(BOOL);
@property (nonatomic, strong) TVODefaultAudioDevice *audioDevice;

@property (nonatomic, strong) CXProvider *callKitProvider;
@property (nonatomic, strong) CXCallController *callKitCallController;

@property (nonatomic, weak) IBOutlet UIImageView *iconView;
@property (nonatomic, assign, getter=isSpinning) BOOL spinning;

@property (nonatomic, weak) IBOutlet UIButton *placeCallButton;
@property (nonatomic, weak) IBOutlet UITextField *outgoingValue;
@property (weak, nonatomic) IBOutlet UIView *callControlView;
@property (weak, nonatomic) IBOutlet UISwitch *muteSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *speakerSwitch;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    self.voipRegistry.delegate = self;
    self.voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];

    [self toggleUIState:YES showCallControl:NO];
    self.outgoingValue.delegate = self;

    [self configureCallKit];
    
    /*
     * The important thing to remember when providing a TVOAudioDevice is that the device must be set
     * before performing any other actions with the SDK (such as connecting a Call, or accepting an incoming Call).
     * In this case we've already initialized our own `TVODefaultAudioDevice` instance which we will now set.
     */
    self.audioDevice = [TVODefaultAudioDevice audioDevice];
    TwilioVoice.audioDevice = self.audioDevice;
}

- (void)configureCallKit {
    CXProviderConfiguration *configuration = [[CXProviderConfiguration alloc] initWithLocalizedName:@"CallKit Quickstart"];
    configuration.maximumCallGroups = 1;
    configuration.maximumCallsPerCallGroup = 1;
    UIImage *callkitIcon = [UIImage imageNamed:@"iconMask80"];
    configuration.iconTemplateImageData = UIImagePNGRepresentation(callkitIcon);

    _callKitProvider = [[CXProvider alloc] initWithConfiguration:configuration];
    [_callKitProvider setDelegate:self queue:nil];

    _callKitCallController = [[CXCallController alloc] init];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)dealloc {
    if (self.callKitProvider) {
        [self.callKitProvider invalidate];
    }
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
    if (self.call && self.call.state == TVOCallStateConnected) {
        [self performEndCallActionWithUUID:self.call.uuid];
        [self toggleUIState:NO showCallControl:NO];
    } else {
        NSUUID *uuid = [NSUUID UUID];
        NSString *handle = @"Voice Bot";
        
        [self checkRecordPermission:^(BOOL permissionGranted) {
            if (!permissionGranted) {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Voice Quick Start"
                                                                                         message:@"Microphone permission not granted."
                                                                                  preferredStyle:UIAlertControllerStyleAlert];

                typeof(self) __weak weakSelf = self;
                UIAlertAction *continueWithoutMic = [UIAlertAction actionWithTitle:@"Continue without microphone"
                                                                             style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    typeof(self) __strong strongSelf = weakSelf;
                    [strongSelf performStartCallActionWithUUID:uuid handle:handle];
                }];
                [alertController addAction:continueWithoutMic];

                NSDictionary *openURLOptions = @{UIApplicationOpenURLOptionUniversalLinksOnly: @NO};
                UIAlertAction *goToSettings = [UIAlertAction actionWithTitle:@"Settings"
                                                                       style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
                                                       options:openURLOptions
                                             completionHandler:nil];
                }];
                [alertController addAction:goToSettings];
                
                UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel"
                                                                 style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                    typeof(self) __strong strongSelf = weakSelf;
                    [strongSelf toggleUIState:YES showCallControl:NO];
                    [strongSelf stopSpin];
                }];
                [alertController addAction:cancel];
                
                [self presentViewController:alertController animated:YES completion:nil];
            } else {
                [self performStartCallActionWithUUID:uuid handle:handle];
            }
        }];
    }
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
        self.deviceTokenString = [credentials.token description];
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
    if ([type isEqualToString:PKPushTypeVoIP]) {
        if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self]) {
            NSLog(@"This is not a valid Twilio Voice notification.");
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        completion();
    });
}

#pragma mark - TVONotificationDelegate
- (void)callInviteReceived:(TVOCallInvite *)callInvite {
    NSLog(@"callInviteReceived:");
    
    if (self.callInvite) {
        NSLog(@"A CallInvite is already in progress. Ignoring the incoming CallInvite from %@", callInvite.from);
        return;
    } else if (self.call) {
        NSLog(@"Already an active call. Ignoring the incoming CallInvite from %@", callInvite.from);
        return;
    }

    self.callInvite = callInvite;

    [self reportIncomingCallFrom:@"Voice Bot" withUUID:callInvite.uuid];
}

- (void)cancelledCallInviteReceived:(TVOCancelledCallInvite *)cancelledCallInvite {
    NSLog(@"cancelledCallInviteReceived:");
    
    if (!self.callInvite ||
        ![self.callInvite.callSid isEqualToString:cancelledCallInvite.callSid]) {
        NSLog(@"No matching pending CallInvite. Ignoring the Cancelled CallInvite");
        return;
    }

    [self performEndCallActionWithUUID:self.callInvite.uuid];

    self.callInvite = nil;
}

#pragma mark - TVOCallDelegate
- (void)callDidConnect:(TVOCall *)call {
    NSLog(@"callDidConnect:");

    self.call = call;
    self.callKitCompletionCallback(YES);
    self.callKitCompletionCallback = nil;
    
    [self.placeCallButton setTitle:@"Hang Up" forState:UIControlStateNormal];
    
    [self toggleUIState:YES showCallControl:YES];
    [self stopSpin];
    [self toggleAudioRoute:YES];
}

- (void)call:(TVOCall *)call didFailToConnectWithError:(NSError *)error {
    NSLog(@"Call failed to connect: %@", error);
    
    self.callKitCompletionCallback(NO);
    [self performEndCallActionWithUUID:call.uuid];
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
    self.callKitCompletionCallback = nil;
    
    [self stopSpin];
    [self toggleUIState:YES showCallControl:NO];
    [self.placeCallButton setTitle:@"Call" forState:UIControlStateNormal];
}

#pragma mark - AVAudioSession
- (void)toggleAudioRoute:(BOOL)toSpeaker {
    // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
    self.audioDevice.block =  ^ {
        // We will execute `kDefaultAVAudioSessionConfigurationBlock` first.
        kDefaultAVAudioSessionConfigurationBlock();
        
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
    self.audioDevice.block();
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

#pragma mark - CXProviderDelegate
- (void)providerDidReset:(CXProvider *)provider {
    NSLog(@"providerDidReset:");
    self.audioDevice.enabled = YES;
}

- (void)providerDidBegin:(CXProvider *)provider {
    NSLog(@"providerDidBegin:");
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didActivateAudioSession:");
    self.audioDevice.enabled = YES;
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didDeactivateAudioSession:");
}

- (void)provider:(CXProvider *)provider timedOutPerformingAction:(CXAction *)action {
    NSLog(@"provider:timedOutPerformingAction:");
}

- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
    NSLog(@"provider:performStartCallAction:");
    
    [self toggleUIState:NO showCallControl:NO];
    [self startSpin];

    self.audioDevice.enabled = NO;
    self.audioDevice.block();
    
    [self.callKitProvider reportOutgoingCallWithUUID:action.callUUID startedConnectingAtDate:[NSDate date]];
    
    __weak typeof(self) weakSelf = self;
    [self performVoiceCallWithUUID:action.callUUID client:nil completion:^(BOOL success) {
        __strong typeof(self) strongSelf = weakSelf;
        if (success) {
            [strongSelf.callKitProvider reportOutgoingCallWithUUID:action.callUUID connectedAtDate:[NSDate date]];
            [action fulfill];
        } else {
            [action fail];
        }
    }];
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action {
    NSLog(@"provider:performAnswerCallAction:");

    NSAssert([self.callInvite.uuid isEqual:action.callUUID], @"We only support one Invite at a time.");
    
    self.audioDevice.enabled = NO;
    self.audioDevice.block();
    
    [self performAnswerVoiceCallWithUUID:action.callUUID completion:^(BOOL success) {
        if (success) {
            [action fulfill];
        } else {
            [action fail];
        }
    }];
    
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action {
    NSLog(@"provider:performEndCallAction:");

    if (self.callInvite) {
        [self.callInvite reject];
        self.callInvite = nil;
    } else if (self.call) {
        [self.call disconnect];
    }

    self.audioDevice.enabled = YES;
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performSetHeldCallAction:(CXSetHeldCallAction *)action {
    if (self.call && self.call.state == TVOCallStateConnected) {
        [self.call setOnHold:action.isOnHold];
        [action fulfill];
    } else {
        [action fail];
    }
}

#pragma mark - CallKit Actions
- (void)performStartCallActionWithUUID:(NSUUID *)uuid handle:(NSString *)handle {
    if (uuid == nil || handle == nil) {
        return;
    }

    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:handle];
    CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:uuid handle:callHandle];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];

    [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
        if (error) {
            NSLog(@"StartCallAction transaction request failed: %@", [error localizedDescription]);
        } else {
            NSLog(@"StartCallAction transaction request successful");

            CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
            callUpdate.remoteHandle = callHandle;
            callUpdate.supportsDTMF = YES;
            callUpdate.supportsHolding = YES;
            callUpdate.supportsGrouping = NO;
            callUpdate.supportsUngrouping = NO;
            callUpdate.hasVideo = NO;

            [self.callKitProvider reportCallWithUUID:uuid updated:callUpdate];
        }
    }];
}

- (void)reportIncomingCallFrom:(NSString *) from withUUID:(NSUUID *)uuid {
    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:from];

    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.remoteHandle = callHandle;
    callUpdate.supportsDTMF = YES;
    callUpdate.supportsHolding = YES;
    callUpdate.supportsGrouping = NO;
    callUpdate.supportsUngrouping = NO;
    callUpdate.hasVideo = NO;

    [self.callKitProvider reportNewIncomingCallWithUUID:uuid update:callUpdate completion:^(NSError *error) {
        if (!error) {
            NSLog(@"Incoming call successfully reported.");
        }
        else {
            NSLog(@"Failed to report incoming call successfully: %@.", [error localizedDescription]);
        }
    }];
}

- (void)performEndCallActionWithUUID:(NSUUID *)uuid {
    if (uuid == nil) {
        return;
    }

    CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:uuid];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];

    [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
        if (error) {
            NSLog(@"EndCallAction transaction request failed: %@", [error localizedDescription]);
        }
        else {
            NSLog(@"EndCallAction transaction request successful");
        }
    }];
}

- (void)performVoiceCallWithUUID:(NSUUID *)uuid
                          client:(NSString *)client
                      completion:(void(^)(BOOL success))completionHandler {
    __weak typeof(self) weakSelf = self;
    TVOConnectOptions *connectOptions = [TVOConnectOptions optionsWithAccessToken:[self fetchAccessToken] block:^(TVOConnectOptionsBuilder *builder) {
        __strong typeof(self) strongSelf = weakSelf;
        builder.params = @{kTwimlParamTo: strongSelf.outgoingValue.text};
        builder.uuid = uuid;
    }];
    self.call = [TwilioVoice connectWithOptions:connectOptions delegate:self];
    self.callKitCompletionCallback = completionHandler;
}

- (void)performAnswerVoiceCallWithUUID:(NSUUID *)uuid
                            completion:(void(^)(BOOL success))completionHandler {
    __weak typeof(self) weakSelf = self;
    TVOAcceptOptions *acceptOptions = [TVOAcceptOptions optionsWithCallInvite:self.callInvite block:^(TVOAcceptOptionsBuilder *builder) {
        __strong typeof(self) strongSelf = weakSelf;
        builder.uuid = strongSelf.callInvite.uuid;
    }];

    self.call = [self.callInvite acceptWithOptions:acceptOptions delegate:self];

    if (!self.call) {
        completionHandler(NO);
    } else {
        self.callKitCompletionCallback = completionHandler;
    }
    
    self.callInvite = nil;
}

@end
