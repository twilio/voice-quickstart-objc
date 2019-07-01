## SDK 4.0 New Features
Voice iOS SDK 4.0 introduced a new call state: `TVOCallStateReconnecting`. You will need to update any logic you have implemented that relies on the call state. The simplest approach is to treat a `TVOCallStateReconnecting` just like a `TVOCallStateConnected` and keep the current behavior.

For more advanced behaviour, you can make use of TVOCallDelegate’s new protocol methods `call:isReconnectingWithError:` and `callDidReconnect:` to update the UI for example and indicate the ongoing disruption.

For example:

```
- (void)call:(TVOCall *)call isReconnectingWithError:(NSError *)error {
    NSLog(@"Call is reconnecting");

    // Update UI
    // Check the error: It could be either
    // TVOErrorSignalingConnectionDisconnectedError (53001) or
    // TVOErrorMediaConnectionError (53405).
}

- (void)callDidReconnect:(TVOCall *)call {
    NSLog(@"Call reconnected");

    // Update UI
}
```