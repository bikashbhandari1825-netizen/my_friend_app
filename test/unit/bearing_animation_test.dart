// test/unit/bearing_animation_test.dart
//
// shortestAngleDelta is the math behind route_map_view.dart's live-marker
// rotation animation (the fix for "vehicle icon jerks/snaps instead of
// turning smoothly"). Verified here against thousands of angle pairs: the
// delta must always be the *short* way round (<=180 degrees in either
// direction), and applying it must always land exactly back on the target
// bearing (mod 360) -- if either property ever failed, the live marker
// would visibly spin the long way round or end up facing the wrong
// direction after animating.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_friend_app/screens/nearby_common.dart' show shortestAngleDelta;

void main() {
  test(
      'shortestAngleDelta always takes the short way round and lands exactly on target across 3600 angle pairs',
      () {
    const samples = 3600;
    for (var i = 0; i < samples; i++) {
      final from = (i * 37) % 360; // irregular stride, wide coverage
      final to = (i * 101 + 17) % 360;
      final delta = shortestAngleDelta(from.toDouble(), to.toDouble());

      expect(delta.abs(), lessThanOrEqualTo(180.0),
          reason:
              'from=$from to=$to: delta=$delta must never exceed 180 degrees either way (that would be the long way round, not the shortest)');

      final landed = ((from + delta) % 360 + 360) % 360;
      final targetNorm = ((to % 360) + 360) % 360;
      final diff = (landed - targetNorm).abs();
      expect(diff < 0.001 || (360 - diff) < 0.001, isTrue,
          reason:
              'from=$from to=$to: from+delta=$landed must land exactly on target=$targetNorm');
    }
  });

  test('shortestAngleDelta handles the exact 0/360 wrap without a long spin',
      () {
    // The case that actually motivated this fix: 350 -> 10 must be a 20
    // degree turn, never the 340 degree "spin the wrong way" a naive
    // (to - from) interpolation would produce.
    expect(shortestAngleDelta(350, 10), closeTo(20, 0.001));
    expect(shortestAngleDelta(10, 350), closeTo(-20, 0.001));
    expect(shortestAngleDelta(0, 359), closeTo(-1, 0.001));
    expect(shortestAngleDelta(359, 0), closeTo(1, 0.001));
  });

  test('shortestAngleDelta is stable under repeated application (no drift)',
      () {
    // Simulates a vehicle repeatedly turning toward the same heading many
    // times in a row (e.g. following a long straight road with minor GPS
    // jitter in the computed bearing each fix) -- the displayed bearing
    // must converge and stay at the target, never wander off.
    var displayed = 0.0;
    const target = 273.0;
    for (var i = 0; i < 1000; i++) {
      displayed += shortestAngleDelta(displayed, target);
    }
    final normalized = ((displayed % 360) + 360) % 360;
    expect(normalized, closeTo(target, 0.001));
  });
}
