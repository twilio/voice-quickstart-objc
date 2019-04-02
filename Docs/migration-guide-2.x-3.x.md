## 2.x to 3.x Migration Guide
This section describes API or behavioral changes when upgrading from Voice iOS 2.X to Voice iOS 3.X. Each section provides code snippets to assist in transitioning to the new API.

1. [Making a Call](#making-a-call)
2. [TVOCallInvite Changes](#tvocallinvite-changes)
3. [Specifying a Media Region](#specifying-a-media-region)
4. [TVOConnectOptions & TVOAcceptOptions](#tvoconnectoptions-and-tvoacceptoptions)
5. [Media Establishment & Connectivity](#media-establishment-and-connectivity)
6. [CallKit](#callkit)
7. [Microphone Permission](#microphone-permission)

#### <a name="making-a-call"></a>Making a Call
In Voice iOS 3.X, the API to make a call has changed from `[TwilioVoice call:params:delegate:]` to `[TwilioVoice connectWithAccessToken:delegate]` or `[TwilioVoice connectWithOptions:delegate:]`.

```.objc
TVOCall *call = [TwilioVoice connectWithAccessToken:token delegate:self];
```

#### <a name="tvocallinvite-changes"></a>TVOCallInvite Changes
In Voice iOS 3.X, the `notificationError:` delegate method is removed from the `TVONotificationDelegate` protocol and the `[TwilioVoice handleNotification:]` method no longer raises errors via this method if an invalid notification is provided, instead a `BOOL` value is returned when `[TwilioVoice handleNotification:]` is called. The returned value is `YES` when the provided data resulted in a `TVOCallInvite` or `TVOCancelledCallInvite` received in the `TVONotificationDelegate` methods. If `NO` is returned it means the data provided was not a Twilio Voice push notification.

```.objc
- (void)pushRegistry:(PKPushRegistry *)registry
didReceiveIncomingPushWithPayload:(PKPushPayload *)payload
             forType:(NSString *)type {
    if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self]) {
        // The push notification was not a Twilio Voice push notification.
    }
}

#pragma mark - TVONotificationDelegate
- (void)callInviteReceived:(TVOCallInvite *)callInvite {
    // Show notification to answer or reject call
}

- (void)cancelledCallInviteReceived:(TVOCancelledCallInvite *)cancelledCallInvite {
    // Hide notification
}
```

The `TVOCallInvite` has an `accept()` and `reject()` method. `TVOCallInviteState` has been removed from the `TVOCallInvite` in favor of distinguishing between call invites and call invite cancellations with discrete stateless objects. While the `TVOCancelledCallInvite` simply provides the `to`, `from`, and `callSid` fields also available in the `TVOCallInvite`. The property `callSid` can be used to associate a `TVOCallInvite` with a `TVOCancelledCallInvite`.

In Voice iOS 2.X passing a `cancel` notification into `[TwilioVoice handleNotification:delegate:]` would not raise a callback in the following two cases:

- This callee accepted the call
- This callee rejected the call

However, in Voice iOS 3.X passing a `cancel` notification payload into `[TwilioVoice handleNotification:delegate:]` will always result in a callback. A callback is raised whenever a valid notification is provided to `[TwilioVoice handleNotification:delegate:]`.

Note that Twilio will send a `cancel` notification to every registered device of the identity that accepts or rejects a call, even the device that accepted or rejected the call.

#### <a name="specifying-a-media-region"></a>Specifying a media region
Previously, a media region could be specified via `[TwilioVoice setRegion:]`. Now this configuration can be provided as part of `TVOConnectOptions` or `TVOAcceptOptions` as shown below:

```.objc
TVOConnectOptions *options = [TVOConnectOptions optionsWithAccessToken:accessToken
                                                                 block:^(TVOConnectOptionsBuilder *builder) {
    builder.region = region;
}];

TVOAcceptOptions *options = [TVOAcceptOptions optionsWithCallInvite:callInvite
                                                              block:^(TVOAcceptOptionsBuilder *builder) {
    builder.region = region;
}];
```

#### <a name="tvoconnectoptions-and-tvoacceptoptions"></a>TVOConnectOptions & TVOAcceptOptions
To support configurability upon making or accepting a call, new classes have been added. Create a `TVOConnectOptions` object and make configurations via the `TVOConnectOptionsBuilder` in the `block`. Once `TVOConnectOptions` is created it can be provided when connecting a Call as shown below:

```.objc
TVOConnectOptions *options = [TVOConnectOptions optionsWithAccessToken:accessToken
                                                                 block:^(TVOConnectOptionsBuilder *builder) {
    builder.params = params;
}];

self.call = [TwilioVoice connectWithOptions:options delegate:self];
```

A `TVOCallInvite` can also be accepted using `TVOAcceptOptions` as shown below:

```.objc
TVOAcceptOptions *options = [TVOAcceptOptions optionsWithCallInvite:callInvite
                                                              block:^(TVOAcceptOptionsBuilder *builder) {
    builder.region = region;
}];

self.call = [callInvite acceptWithOptions:options delegate:self];
```

#### <a name="media-establishment-and-connectivity"></a>Media Establishment & Connectivity
The Voice iOS 3.X SDK uses WebRTC. The exchange of real-time media requires the use of Interactive Connectivity Establishment(ICE) to establish a media connection between the client and the media server. In some network environments where network access is restricted it may be necessary to provide ICE servers to establish a media connection. We reccomend using the [Network Traversal Service (NTS)](https://www.twilio.com/stun-turn) to obtain ICE servers. ICE servers can be provided when making or accepting a call by passing them into `TVOConnectOptions` or `TVOAcceptOptions` in the following way:

```.objc
TVOIceOptions *iceOptions;

NSMutableArray *iceServers = [NSMutableArray array];
TVOIceServer *iceServer1 = [[TVOIceServer alloc] initWithURLString:@"stun:global.stun.twilio.com:3478?transport=udp"
                                                          username:@""
                                                          password:@""];
[iceServers addObject:iceServer];

TVOIceServer *iceServer2 = [[TVOIceServer alloc] initWithURLString:@"turn:global.turn.twilio.com:3478?transport=udp"
                                                          username:@"TURN_USERNAME"
                                                          password:@"TURN_PASSWORD"];
[iceServers addObject:iceServer2];

iceOptions = [TVOIceOptions optionsWithBlock:^(TVOIceOptionsBuilder *builder) {
    builder.servers = iceServers;
}];

// Specify ICE options in the builder
TVOConnectOptions *options = [TVOConnectOptions optionsWithAccessToken:accessToken
                                                                 block:^(TVOConnectOptionsBuilder *builder) {
    builder.iceOptions = iceOptions;
}];

TVOAcceptOptions *options = [TVOAcceptOptions optionsWithCallInvite:callInvite
                                                              block:^(TVOAcceptOptionsBuilder *builder) {
    builder.iceOptions = iceOptions;
}];
```

#### <a name="callkit"></a>CallKit
The Voice iOS 3.X SDK deprecates the `CallKitIntegration` category from `TwilioVoice` in favor of a new property called `TVODefaultAudioDevice.enabled`. This property provides developers with a mechanism to enable or disable the activation of the audio device prior to connecting to a Call or to stop or start the audio device while you are already connected to a Call. A Call can now be connected without activating the audio device by setting `TVODefaultAudioDevice.enabled` to `NO` and can be enabled during the lifecycle of the Call by setting `TVODefaultAudioDevice.enabled` to `YES`. The default value is `YES`. This API change was made to ensure full compatibility with CallKit as well as supporting other use cases where developers may need to disable the audio device during a call.

An example of managing the `TVODefaultAudioDevice` while connecting a CallKit Call:

```.objc
@property (nonatomic, strong) TVODefaultAudioDevice *audioDevice;

- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
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

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession {
    self.audioDevice.enabled = YES;
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action {
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
    // Disconnect or reject the call

    self.audioDevice.enabled = YES;
    [action fulfill];
}
```

See [CallKit Example](https://github.com/twilio/voice-quickstart-objc/blob/3.x/ObjCVoiceCallKitQuickstart/ViewController.m) for the complete implementation.

#### <a name="microphone-permission"></a>Microphone Permission
Unlike Voice iOS 2.X SDKs where microphone permission is not optional in Voice 3.X SDKs, the call will connect even when the microphone permission is denied or disabled by the user, and the SDK will play the remote audio. To ensure the microphone permission is enabled prior to making or accepting a call you can add the following to request the permission beforehand:

```
- (void)makeCall {
    // User's microphone option
    BOOL microphoneEnabled = YES;
    
    if (microphoneEnabled) {
        [self checkRecordPermission:^(BOOL permissionGranted) {
            if (!permissionGranted) {
                // The user might want to revisit the Privacy settings.
            } else {
                // Permission granted. Continue to make call.
            }
        }];
    } else {
        // Continue to make call without microphone.
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
```
