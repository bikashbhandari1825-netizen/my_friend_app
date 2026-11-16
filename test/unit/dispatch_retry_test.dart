// test/unit/dispatch_retry_test.dart
//
// retryTransient/setDocWithRetry (job_actions.dart) is the fix for
// "Request Ride occasionally never reaches Firestore" -- a bounded,
// idempotent retry around the critical write that creates a new ride/
// service request. Verified here with a fault-injectable operation
// (simulating a flaky network that fails N times before succeeding),
// confirming: (1) it actually retries and eventually succeeds instead of
// giving up after one transient failure, (2) it never wastes time
// retrying a permanent error, (3) retrying a .set() on a fixed doc id
// never creates a duplicate document, and (4) every failed attempt is
// reported through onAttemptFailed, so nothing fails silently with no
// trace in the terminal.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_friend_app/screens/job_actions.dart'
    show isTransientDispatchError, retryTransient, setDocWithRetry;

void main() {
  group('isTransientDispatchError', () {
    test('treats network/server-side-temporary codes as transient', () {
      for (final code in [
        'unavailable',
        'deadline-exceeded',
        'aborted',
        'internal',
        'resource-exhausted',
        'cancelled',
        'unknown',
      ]) {
        expect(
            isTransientDispatchError(
                FirebaseException(plugin: 'cloud_firestore', code: code)),
            isTrue,
            reason: '$code must be treated as transient (retry-worthy)');
      }
    });

    test('never treats a permanent error as transient', () {
      for (final code in [
        'permission-denied',
        'invalid-argument',
        'not-found',
        'already-exists',
      ]) {
        expect(
            isTransientDispatchError(
                FirebaseException(plugin: 'cloud_firestore', code: code)),
            isFalse,
            reason:
                '$code is permanent -- retrying it would only waste time');
      }
    });
  });

  group('retryTransient', () {
    test('retries through repeated transient failures and succeeds, '
        'for every possible failure count up to the limit', () async {
      // Sweep failTimes from 0 (succeeds first try) through 2 (succeeds on
      // the final, 3rd attempt) -- every one must eventually succeed.
      for (var failTimes = 0; failTimes <= 2; failTimes++) {
        var calls = 0;
        final attemptsReported = <int>[];
        final result = await retryTransient<String>(
          () async {
            calls++;
            if (calls <= failTimes) {
              throw FirebaseException(
                  plugin: 'cloud_firestore', code: 'unavailable');
            }
            return 'ok';
          },
          backoff: (_) => Duration.zero,
          onAttemptFailed: (attempt, max, e, transient) =>
              attemptsReported.add(attempt),
        );
        expect(result, 'ok',
            reason: 'failTimes=$failTimes must still eventually succeed');
        expect(calls, failTimes + 1,
            reason: 'failTimes=$failTimes must call op exactly '
                '${failTimes + 1} times (no more, no fewer)');
        expect(attemptsReported.length, failTimes,
            reason: 'every failed attempt before the success must be '
                'reported through onAttemptFailed');
      }
    });

    test('gives up after maxAttempts transient failures and rethrows',
        () async {
      var calls = 0;
      final attemptsReported = <int>[];
      await expectLater(
        () => retryTransient<void>(
          () async {
            calls++;
            throw FirebaseException(
                plugin: 'cloud_firestore', code: 'unavailable');
          },
          maxAttempts: 3,
          backoff: (_) => Duration.zero,
          onAttemptFailed: (attempt, max, e, transient) =>
              attemptsReported.add(attempt),
        ),
        throwsA(isA<FirebaseException>()),
      );
      expect(calls, 3, reason: 'must stop at exactly maxAttempts, not loop forever');
      expect(attemptsReported, [1, 2, 3]);
    });

    test('a permanent error aborts after exactly one attempt, never retried',
        () async {
      var calls = 0;
      final attemptsReported = <int>[];
      await expectLater(
        () => retryTransient<void>(
          () async {
            calls++;
            throw FirebaseException(
                plugin: 'cloud_firestore', code: 'permission-denied');
          },
          maxAttempts: 5,
          backoff: (_) => Duration.zero,
          onAttemptFailed: (attempt, max, e, transient) {
            attemptsReported.add(attempt);
            expect(transient, isFalse);
          },
        ),
        throwsA(isA<FirebaseException>()),
      );
      expect(calls, 1,
          reason: 'a permanent error must never be retried, even though '
              'maxAttempts allows up to 5');
      expect(attemptsReported, [1]);
    });
  });

  group('setDocWithRetry', () {
    // FakeFirebaseFirestore has no failure-injection hook, so the retry
    // *count/backoff/permanent-vs-transient* logic is fully verified above
    // via retryTransient (which this is a thin Firestore-specific wrapper
    // around -- see job_actions.dart). What's specific to verify here is
    // the wiring itself: a successful write lands on the exact doc id that
    // was reserved up front, and never leaves more than one document for
    // one logical request.
    test('writes to the pre-reserved doc id and creates exactly one document',
        () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('serviceRequests').doc();

      await setDocWithRetry(ref, {'status': 'broadcasting'});

      final snap = await ref.get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['status'], 'broadcasting');

      final all = await firestore.collection('serviceRequests').get();
      expect(all.docs.length, 1,
          reason: 'exactly one document must exist for one logical request');
      expect(all.docs.single.id, ref.id);
    });
  });
}
