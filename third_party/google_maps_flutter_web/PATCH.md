# Local patch: google_maps_flutter_web 0.6.3+1

Vendored copy of the upstream package (unchanged except one method) to fix a
real crash-in-waiting on Flutter web:

```
DartError: Assertion failed: google_maps_flutter_web-0.6.3+1/lib/src/google_maps_flutter_web.dart:32:12
"Maps cannot be retrieved before calling buildView!"
```

## Root cause

`GoogleMapsPlugin.dispose({required int mapId})` unconditionally called the
private `_map(mapId)` helper, which `assert`s that a controller was already
registered in `_mapById` for that id. `buildViewWithConfiguration` only
registers the controller once Flutter actually renders the platform view —
but a `GoogleMap` widget can be disposed before that ever happens (e.g. it's
built, then torn down again within the same frame, before ever painting).
That's a legitimate, harmless situation: disposing something that was never
fully built should be a no-op, not a thrown assertion. In debug builds this
prints the error above; in release builds `assert` is stripped but the
following `controller!` null-check would still throw.

This is an upstream defect (still present as of 0.6.3+1, the latest release
at the time of this patch) — see `lib/src/google_maps_flutter_web.dart`.

## The fix

`dispose()` now looks the controller up directly and disposes it only if it
exists, instead of routing through the asserting `_map()` helper:

```dart
void dispose({required int mapId}) {
  _mapById.remove(mapId)?.dispose();
}
```

No other files were changed.

## Re-syncing after a pub upgrade

If `google_maps_flutter_web` is upgraded, re-copy the new version's `lib/`
folder over this one and re-apply the one-line change above to `dispose()`
in `lib/src/google_maps_flutter_web.dart` (search for
`"Maps cannot be retrieved before calling buildView!"` to find the original
`_map()` helper it used to route through). Check upstream's changelog first —
if they've fixed this themselves, this whole `third_party/` override and the
`dependency_overrides` entry in `pubspec.yaml` can be deleted.
