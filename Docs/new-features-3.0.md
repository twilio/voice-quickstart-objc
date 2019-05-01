## SDK 3.0 New Features
Voice iOS 3.0 has a number of new features listed below:

1. [WebRTC](#webrtc)
2. [Custom Parameters](#custom-parameters)
3. [Call Ringing APIs](#call-ringing-apis)
4. [Media Stats](#media-stats)
5. [Audio Device APIs](#audio-device-apis)
    * [Default Audio Device](#default-audio-device)
    * [Custom Audio Device](#custom-audio-device)
6. [Preferred Audio Codec](#preferred-audio-codec)

#### <a name="webrtc"></a>WebRTC
The SDK is built using Chromium WebRTC for iOS. This ensures that over time developers will get the best real-time media streaming capabilities available for iOS. Additionally, upgrades to new versions of Chromium WebRTC will happen without changing the public API whenever possible.

#### <a name="custom-parameters"></a>Custom Parameters
Custom Parameters is now supported in `TVOCallInvite`. `TVOCallInvite.customParamaters` returns a `NSDictionary` of custom parameters sent from the caller side to the callee.

Pass custom parameters in TwiML:

```.xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Dial callerId="client:alice">
    <Client>
      <Identity>bob</Identity>
      <Parameter name="caller_first_name" value="alice" />
      <Parameter name="caller_last_name" value="smith" />
    </Client>
  </Dial>
</Response>
```

`callInvite.customParameters` returns a dictionary of key-value pairs passed in the TwiML:

```.objc
{
  "caller_first_name" = "alice";
  "caller_last_name" = "smith";
}
```

#### <a name="call-ringing-apis"></a>Call Ringing APIs
Ringing is now provided as a call state. The delegate method `callDidStartRinging:` corresponding to this state transition is called once before the `callDidConnect:` method when the callee is being alerted of a Call. The behavior of this callback is determined by the `answerOnBridge` flag provided in the `Dial` verb of your TwiML application associated with this client. If the `answerOnBridge` flag is `false`, which is the default, the `callDidConnect:` callback will be called immediately after `callDidStartRinging:`. If the `answerOnBridge` flag is `true`, this will cause the `callDidConnect:` method being called only after the Call is answered. See [answerOnBridge](https://www.twilio.com/docs/voice/twiml/dial#answeronbridge) for more details on how to use it with the `Dial` TwiML verb. If the TwiML response contains a `Say` verb, then the `callDidConnect:` method will be called immediately after `callDidStartRinging:` is called, irrespective of the value of `answerOnBridge` being set to `true` or `false`.

These changes are added as follows:

```.objc
// TVOCall.h
typedef NS_ENUM(NSUInteger, TVOCallState) {
    TVOCallStateConnecting = 0, ///< The Call is connecting.
    TVOCallStateRinging,        ///< The Call is ringing.
    TVOCallStateConnected,      ///< The Call is connected.
    TVOCallStateDisconnected    ///< The Call is disconnected.
};

// TVOCallDelegate.h
@protocol TVOCallDelegate

@optional
- (void)callDidStartRinging:(nonnull TVOCall *)call;

@end
```

#### <a name="media-stats"></a>Media Stats
In Voice iOS 3.0 SDK you can now access media stats in a Call using the `[TVOCall getStatsWithBlock:]` method. 

```.objc
[call getStatsWithBlock:^(NSArray<TVOStatsReport *> *statsReports) {
    for (TVOStatsReport *report in statsReports) {
        NSArray *localAudioTracks = report.localAudioTrackStats;
        TVOLocalAudioTrackStats *localAudioTrackStats = localAudioTracks[0];
        NSArray *remoteAudioTracks = report.remoteAudioTrackStats;
        TVORemoteAudioTrackStats *remoteAudioTrackStats = remoteAudioTracks[0];

        NSLog(@"Local Audio Track - audio level: %lu, packets sent: %lu", localAudioTrackStats.audioLevel, localAudioTrackStats.packetsSent);
        NSLog(@"Remote Audio Track - audio level: %lu, packets received: %lu", remoteAudioTrackStats.audioLevel, remoteAudioTrackStats.packetsReceived);
    }
}
```
### <a name="audio-device-apis"></a>Audio Device APIs

#### <a name="default-audio-device"></a>Default Audio Device
In Voice iOS 3.0 SDK, `TVODefaultAudioDevice` is used as the default device for rendering and capturing audio.

An example of using `TVODefaultAudioDevice` to change the audio route from receiver to the speaker in a live call:

```.objc
// The Voice SDK uses TVODefaultAudioDevice by default.
// ... connect to a Call. The `TVODefaultAudioDevice` is configured to route audio to the receiver by default.

TVODefaultAudioDevice *audioDevice = (TVODefaultAudioDevice *)TwilioVoice.audioDevice;

audioDevice.block =  ^ {
    // We will execute `kDefaultAVAudioSessionConfigurationBlock` first.
    kDefaultAVAudioSessionConfigurationBlock();

    if (![session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error]) {
        NSLog(@"AVAudiosession overrideOutputAudioPort %@",error);
    }
};
audioDevice.block();
```

#### <a name="custom-audio-device"></a>Custom Audio Device
The `TVOAudioDevice` protocol gives you the ability to replace `TVODefaultAudioDevice`. By implementing the `TVOAudioDevice` protocol, you can write your own audio capturer to feed audio samples to the Voice SDK and an audio renderer to receive the remote audio samples. For example, you could integrate with `ReplayKit2` and capture application audio for broadcast or play music using `AVAssetReader`.

Connecting to a Call using the `AVAudioSessionCategoryPlayback` category:

```.objc
id<TVOAudioDevice> audioDevice = [TVODefaultAudioDevice audioDeviceWithBlock:^ {

    // Execute the `kDefaultAVAudioSessionConfigurationBlock` first.
    kDefaultAVAudioSessionConfigurationBlock();

    // Overwrite the category to `playback`
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback
                         mode:AVAudioSessionModeVoiceChat
                      options:AVAudioSessionCategoryOptionAllowBluetooth
                        error:&error]) {
        NSLog(@"AVAudioSession setCategory:options:mode:error: %@",error);
    }
}];

TwilioVoice.audioDevice = audioDevice;

TVOCall *call = [TwilioVoice connectWithOptions:connectOptions delegate:self];
```

### <a name="preferred-audio-codec"></a>Preferred Audio Codec
You can provide your preferred audio codecs in the `TVOConnectOptions` and the `TVOAcceptOptions`. Opus is the default codec used by the mobile infrastructure. To use PCMU as the negotiated audio codec instead of Opus you can add it as the first codec in the `preferredAudioCodecs` list.

```.objc
#import "TVOAudioCodec.h"

TVOConnectOptions *options = [TVOConnectOptions optionsWithAccessToken:accessToken
                                                                 block:^(TVOConnectOptionsBuilder *builder) {
    builder.preferredAudioCodecs = @[ [TVOPcmuCodec new], [TVOOpusCodec new] ];
}];

self.call = [TwilioVoice connectWithOptions:options delegate:self];
```
