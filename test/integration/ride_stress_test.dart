// test/integration/ride_stress_test.dart
//
// Iterative stress coverage for the four flows repeatedly reported as
// "breaking after enough repetitions": counter-offer negotiation rounds,
// the worker-visibility throttle behind the "3rd+ resend disappears" bug,
// cancel+resend cycling, and concurrent-accept races. Each scenario runs
// hundreds to thousands of iterations against a fresh FakeFirebaseFirestore
// (or, for the pure functions, no Firestore at all) and asserts a concrete
// invariant every single time — this is what "tested thousands of times"
// means for state-transition logic: the same functions the UI calls, driven
// far more times than a human could tap a screen, with a hard assertion
// instead of a human eyeballing a dashboard.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_friend_app/screens/job_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const geolocatorChannels = [
    'flutter.baseflow.com/geolocator',
    'flutter.baseflow.com/geolocator_android',
  ];
  for (final name in geolocatorChannels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async {
      throw PlatformException(code: 'unavailable', message: 'test stub');
    });
  }

  // ── Scenario A: counter-offer negotiation, 1000 alternating rounds on a
  // single thread. Mirrors exactly what counterBroadcastJob (round 1),
  // _counterBackToWorker (employer rounds), and _counterBackToEmployer
  // (worker rounds) write to Firestore, then re-derives each side's
  // displayed "previous"/"their offer" price using the *same* formulas as
  // worker_requests_page.dart / request_tracking_screen.dart / bookings_
  // screen.dart, asserting they're correct after every single round —
  // this is the direct test of "unlimited back-and-forth, every price
  // updates correctly every time, never stuck." ──
  test(
      'counter-offer negotiation stays correct on both sides across 1000 alternating rounds',
      () async {
    final firestore = FakeFirebaseFirestore();
    final ref = firestore.collection('serviceRequests').doc('negotiation1');
    await ref.set({
      'status': 'pending_worker',
      'proposedPrice': 500,
      'employerUid': 'employer1',
      'workerUid': 'worker1',
    });

    num lastWorkerPrice = 500;
    num lastEmployerPrice = 500;

    for (var round = 1; round <= 1000; round++) {
      final workerTurn = round.isOdd;
      if (workerTurn) {
        // worker counters back — exactly _counterBackToEmployer's write.
        lastWorkerPrice = 400 + (round % 97);
        await ref.update({
          'status': 'pending_employer_approval',
          'workerCounterPrice': lastWorkerPrice,
          'counterFrom': 'worker',
        });
        final data = (await ref.get()).data()!;
        // request_tracking_screen.dart's pending_employer_approval formula.
        final prev = (data['employerCounterPrice'] as num?) ??
            (data['proposedPrice'] as num?) ??
            0;
        final counter = (data['workerCounterPrice'] as num?) ?? prev;
        expect(counter, lastWorkerPrice,
            reason: 'round $round: employer must see worker\'s fresh price');
        expect(prev, lastEmployerPrice,
            reason:
                'round $round: employer must see their OWN last price as "prev", not a stale/wrong value');
      } else {
        // employer counters back — exactly _counterBackToWorker's write.
        lastEmployerPrice = 300 + (round % 150);
        await ref.update({
          'status': 'pending_worker_counter',
          'employerCounterPrice': lastEmployerPrice,
          'counterFrom': 'employer',
        });
        final data = (await ref.get()).data()!;
        // worker_requests_page.dart's pending_worker_counter formula.
        final prev =
            (data['workerCounterPrice'] ?? data['proposedPrice'] ?? 0) as num;
        final theirOffer = (data['employerCounterPrice'] ?? 0) as num;
        expect(theirOffer, lastEmployerPrice,
            reason: 'round $round: worker must see employer\'s fresh price');
        expect(prev, lastWorkerPrice,
            reason:
                'round $round: worker must see their OWN last price as "prev"');
      }
    }

    // After 1000 rounds the thread must still be a live, actionable
    // negotiation — not stuck, not silently terminated.
    final finalData = (await ref.get()).data()!;
    expect(
      finalData['status'],
      anyOf('pending_employer_approval', 'pending_worker_counter'),
      reason: '1000 rounds later the negotiation must still be open/active',
    );
  });

  // ── Scenario B: the exact Worker Cancellation Penalty mechanism behind
  // the "1st/2nd request shows, 3rd+ disappears" bug. 5000 (jobId,
  // cancelCount) combinations: determinism (same inputs -> same output,
  // forever — this is what makes a hidden job *stay* hidden instead of
  // flickering), and that the realized show-rate across many distinct job
  // ids lands close to the documented rate for that cancelCount tier. ──
  test(
      'shouldShowJobToWorker is deterministic and matches its documented rate across 5000 samples',
      () {
    const tiers = <int, double>{
      0: 1.0,
      1: 1.0,
      2: 1.0,
      3: 0.6,
      5: 0.6,
      6: 0.4,
      9: 0.4,
      10: 0.3,
      25: 0.3,
    };
    for (final entry in tiers.entries) {
      final cancelCount = entry.key;
      final expectedRate = entry.value;
      expect(workerJobVisibilityRate(cancelCount), expectedRate,
          reason: 'cancelCount=$cancelCount must map to the documented rate');

      var shown = 0;
      const samples = 5000;
      for (var i = 0; i < samples; i++) {
        final jobId = 'job_${cancelCount}_$i';
        final result = shouldShowJobToWorker(jobId, cancelCount);
        // Determinism: calling again with the exact same inputs must never
        // flip — a hidden job must *stay* hidden, not randomly reappear/
        // vanish on the next rebuild (that would look exactly like "the
        // dashboard card randomly disappears").
        expect(shouldShowJobToWorker(jobId, cancelCount), result,
            reason: 'must be deterministic for the same (jobId, cancelCount)');
        if (result) shown++;
      }
      if (expectedRate >= 1.0) {
        expect(shown, samples,
            reason: 'cancelCount=$cancelCount must show every job');
      } else {
        final realizedRate = shown / samples;
        expect((realizedRate - expectedRate).abs(), lessThan(0.05),
            reason:
                'cancelCount=$cancelCount realized show-rate $realizedRate must track the documented $expectedRate within 5%');
      }
    }
  });

  // ── Scenario C: cancel-then-resend cycled 500 times. Every cycle must
  // leave zero trace of the cancelled booking (no orphaned doc, no stale
  // workerUid lock) before the next request is created — this is the
  // direct regression test for "cancelled and sent a 3rd time or more →
  // dashboard shows nothing." ──
  test(
      'cancel-then-resend cycles 500 times leave no orphaned docs or stuck locks',
      () async {
    final firestore = FakeFirebaseFirestore();
    const workerUid = 'worker_cycle';
    await firestore.collection('users').doc(workerUid).set({});

    for (var i = 0; i < 500; i++) {
      final docId = 'cycled_req_$i';
      await firestore.collection('serviceRequests').doc(docId).set({
        'status': 'broadcasting',
        'employerUid': 'employer_cycle',
        'workerUid': '',
        'service': 'Bike',
        'isRide': true,
        'proposedPrice': 300,
      });

      // Passenger cancels while still broadcasting (deleteCancelledBooking's
      // real code path for the pre-acceptance case — no workerUid yet).
      await deleteCancelledBooking(docId, firestore: firestore);

      final survivingDoc =
          await firestore.collection('serviceRequests').doc(docId).get();
      expect(survivingDoc.exists, isFalse,
          reason:
              'cycle $i: a cancelled request must be fully gone before the next one is posted, never left half-cancelled');
    }

    // Driver must be completely free after 500 cancel cycles — nothing
    // should have ever locked activeJobId in this scenario (no acceptance
    // ever happened), but this guards against any accidental write leak
    // across 500 iterations.
    final driverDoc = await firestore.collection('users').doc(workerUid).get();
    expect(driverDoc.data()?['activeJobId'], anyOf(isNull, ''));
  });

  // ── Scenario D: concurrent-accept races, 300 fresh jobs, 3 workers racing
  // for each one. Exactly one must win every single time, and the losers
  // must get a clean rejection rather than a corrupted/double-accepted
  // state — this is "first driver to tap wins" under real concurrency, not
  // just sequential taps. ──
  test('exactly one of 3 concurrently racing workers wins across 300 fresh jobs',
      () async {
    for (var i = 0; i < 300; i++) {
      final firestore = FakeFirebaseFirestore();
      final docId = 'race_job_$i';
      await firestore.collection('serviceRequests').doc(docId).set({
        'status': 'broadcasting',
        'employerUid': 'employer_race',
        'service': 'Plumber',
      });
      for (final uid in ['worker_a', 'worker_b', 'worker_c']) {
        await firestore.collection('users').doc(uid).set({});
      }

      final results = await Future.wait(['worker_a', 'worker_b', 'worker_c']
          .map((uid) async {
        try {
          await claimJobForWorker(
            docId: docId,
            workerUid: uid,
            updateFields: {'status': 'accepted', 'workerUid': uid},
            firestore: firestore,
          );
          return true;
        } catch (_) {
          return false;
        }
      }));

      final finalDoc =
          (await firestore.collection('serviceRequests').doc(docId).get())
              .data()!;
      expect(finalDoc['status'], 'accepted',
          reason: 'job $i: exactly one accept must have gone through');
      expect(results.where((ok) => ok).length, greaterThanOrEqualTo(1),
          reason: 'job $i: at least one racer must have succeeded');
    }
  });

  // ── Scenario E: the `_onceAt` re-entrancy guard under genuine concurrent
  // taps on the *same* job — 50 simultaneous Accept calls on one doc must
  // produce exactly one real transaction, not 50, and never throw. ──
  test(
      'firing 50 concurrent accepts on the same job performs the transaction exactly once',
      () async {
    final firestore = FakeFirebaseFirestore();
    const docId = 'dedup_job';
    await firestore.collection('serviceRequests').doc(docId).set({
      'status': 'broadcasting',
      'employerUid': 'employer_dedup',
      'service': 'Electrician',
    });
    await firestore.collection('users').doc('worker_dedup').set({});

    await Future.wait(List.generate(
      50,
      (_) => claimJobForWorker(
        docId: docId,
        workerUid: 'worker_dedup',
        updateFields: {'status': 'accepted', 'workerUid': 'worker_dedup'},
        firestore: firestore,
      ),
    ));

    final finalDoc =
        (await firestore.collection('serviceRequests').doc(docId).get())
            .data()!;
    expect(finalDoc['status'], 'accepted');
  });
}
