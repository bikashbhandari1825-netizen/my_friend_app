# Local patch: flutter_webrtc 1.6.2+hotfix.3

Vendored copy of the upstream package (unchanged except one method) to fix a
real, reproducible native crash on Android:

```
F/libc: Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid NNNNN (signaling_threa), pid NNNNN
E/rtc: # Fatal error in: ../../../sdk/android/src/jni/jvm.cc, line 81
E/rtc: # Check failed: false
W/System.err: java.lang.IllegalStateException: RtpTransceiver has been disposed.
  (or: MediaStreamTrack has been disposed. / RtpSender has been disposed.)
    at org.webrtc.RtpTransceiver.checkRtpTransceiverExists(RtpTransceiver.java:124)
    at org.webrtc.PeerConnection.getTransceivers(PeerConnection.java:1089)
    at com.cloudwebrtc.webrtc.PeerConnectionObserver.onAddTrack(PeerConnectionObserver.java:556)
```

Captured live via `adb logcat` on-device during a voice/video call's connecting
phase — reproducible on repeated back-to-back calls, though the underlying
race can in principle hit on any single call.

## Root cause

Upstream issue: https://github.com/flutter-webrtc/flutter-webrtc/issues/2162

`PeerConnectionObserver.onAddTrack(...)` fires once per remote track — once
for audio, once for video, moments apart in a normal audio+video call. Its
"For unified-plan" block calls `peerConnection.getTransceivers()` on *every*
invocation to look up per-track metadata. Google's own Android WebRTC SDK
(`org.webrtc.PeerConnection.getTransceivers()`) disposes the previously-
returned `RtpTransceiver`/`RtpSender`/`MediaStreamTrack` wrapper objects as
an internal side effect of being called again. So the video track's
`onAddTrack` can dispose wrapper objects the audio track's `onAddTrack` (or
vice versa) is still using a few milliseconds later, throwing
`IllegalStateException: "<X> has been disposed"` on the native signaling
thread. That exception is never caught anywhere in the call stack down to
the JNI boundary, so the process aborts (`SIGABRT`) instead of the exception
ever reaching Dart — no amount of Dart-side try/catch or delay can intercept
it, since it never crosses back into Dart at all.

The project's own `lib/services/call_service.dart` already follows the one
documented app-level workaround (`pc.addTrack(track, stream)` instead of
`pc.addTransceiver(...)` for local tracks) and the crash still reproduced,
confirming the race can also originate from the receiving side, independent
of how local tracks were added — i.e. a real fix needs to live in this
plugin's own native code, not just the app's Dart usage of it.

## The fix

Only the `peerConnection.getTransceivers()` lookup inside the "For
unified-plan" block is wrapped in `try/catch (RuntimeException)` — not the
whole block, and not the `sendEvent(params)` call. The Dart side
(`rtc_peerconnection_impl.dart`'s `'onTrack'` case) already treats
`map['transceiver']` as fully optional (`!= null ? ... : null`); it only
requires `streams`/`track`/`receiver`, none of which depend on
`getTransceivers()`. An earlier version of this patch wrapped the entire
block, which would have silently dropped the essential streams/track/
receiver data too on every race hit — losing the remote video/audio
attachment for that track (a real black-screen risk) instead of just the
optional transceiver metadata. Guarding only the risky lookup means the
call's audio/video keeps working normally even when this exact race fires;
only the optional transceiver metadata for that one track is missing, and
only on the rare race — no other files were changed.

## Re-syncing after a pub upgrade

If `flutter_webrtc` is upgraded, re-copy the new version's files over this
one and re-apply the try/catch wrap above to the "For unified-plan" block in
`android/src/main/java/com/cloudwebrtc/webrtc/PeerConnectionObserver.java`'s
`onAddTrack` method (search for `getTransceivers()` to find it — line
numbers will have shifted). Check the upstream issue first — if a future
release fixes this natively, this whole `third_party/` override and the
`dependency_overrides` entry in `pubspec.yaml` can be deleted. The bundled
`example/` app was deleted from this vendored copy since it's not needed and
was adding ~1.5MB of unused weight.
