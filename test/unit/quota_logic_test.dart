// test/unit/quota_logic_test.dart
// Rating-based monthly order-quota business logic
// (job_actions.dart::monthlyOrderQuotaForRating/consumeOrderQuotaInTransaction).
// No refactor needed for these — monthlyOrderQuotaForRating is a pure
// function, and consumeOrderQuotaInTransaction already takes an explicit
// Transaction/DocumentReference/data map, so it's directly testable against
// a FakeFirebaseFirestore transaction.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_friend_app/screens/job_actions.dart';

void main() {
  group('monthlyOrderQuotaForRating', () {
    test('gives the starter quota when the worker has no reviews yet', () {
      expect(monthlyOrderQuotaForRating(ratingSum: 0, reviewCount: 0), 8);
    });

    test('maps each rounded star tier to the documented quota', () {
      // avg 0 → 0 stars → 0
      expect(monthlyOrderQuotaForRating(ratingSum: 0, reviewCount: 5), 0);
      // avg 1.0 → 1 star → 2
      expect(monthlyOrderQuotaForRating(ratingSum: 5, reviewCount: 5), 2);
      // avg 2.0 → 2 stars → 4
      expect(monthlyOrderQuotaForRating(ratingSum: 10, reviewCount: 5), 4);
      // avg 3.0 → 3 stars → 8
      expect(monthlyOrderQuotaForRating(ratingSum: 15, reviewCount: 5), 8);
      // avg 4.0 → 4 stars → 18
      expect(monthlyOrderQuotaForRating(ratingSum: 20, reviewCount: 5), 18);
      // avg 5.0 → 5 stars → 35
      expect(monthlyOrderQuotaForRating(ratingSum: 25, reviewCount: 5), 35);
    });

    test('rounds the average to the nearest star before mapping', () {
      // avg 3.6 rounds to 4 stars → 18, not 3 stars' 8.
      expect(monthlyOrderQuotaForRating(ratingSum: 18, reviewCount: 5), 18);
    });
  });

  group('consumeOrderQuotaInTransaction', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('a fresh worker with no quota history gets the starter quota',
        () async {
      final userRef = firestore.collection('users').doc('worker1');
      await firestore.runTransaction((tx) async {
        consumeOrderQuotaInTransaction(tx, userRef, null);
      });
      final snap = await userRef.get();
      expect(snap.data()!['orderQuotaUsed'], 1);
      expect(snap.data()!['orderQuotaMonth'], currentQuotaMonthKey());
    });

    test('increments orderQuotaUsed across repeated accepts within the month',
        () async {
      final userRef = firestore.collection('users').doc('worker1');
      // Pre-seed month + 2 already-used orders, high enough rating for a
      // quota of 18 so we're testing the increment, not the starter path.
      await userRef.set({
        'orderQuotaMonth': currentQuotaMonthKey(),
        'orderQuotaUsed': 2,
        'ratingSum': 20,
        'ratingCount': 5, // avg 4.0 -> quota 18
      });

      await firestore.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        consumeOrderQuotaInTransaction(tx, userRef, snap.data());
      });

      final after = await userRef.get();
      expect(after.data()!['orderQuotaUsed'], 3);
    });

    test('throws WorkerQuotaExceededException once the monthly limit is hit',
        () async {
      final userRef = firestore.collection('users').doc('worker1');
      // rating avg 1.0 -> quota 2; already used 2 -> next accept must fail.
      await userRef.set({
        'orderQuotaMonth': currentQuotaMonthKey(),
        'orderQuotaUsed': 2,
        'ratingSum': 5,
        'ratingCount': 5,
      });

      expect(
        () => firestore.runTransaction((tx) async {
          final snap = await tx.get(userRef);
          consumeOrderQuotaInTransaction(tx, userRef, snap.data());
        }),
        throwsA(isA<WorkerQuotaExceededException>()),
      );

      // The doc must be untouched — an exceeded quota should never write.
      final after = await userRef.get();
      expect(after.data()!['orderQuotaUsed'], 2);
    });

    test('resets the used-count when the stored month has rolled over',
        () async {
      final userRef = firestore.collection('users').doc('worker1');
      await userRef.set({
        'orderQuotaMonth': '2000-01', // long-past month
        'orderQuotaUsed': 999, // would exceed any real tier if not reset
        'ratingSum': 0,
        'ratingCount': 0, // starter tier, quota 8
      });

      await firestore.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        consumeOrderQuotaInTransaction(tx, userRef, snap.data());
      });

      final after = await userRef.get();
      expect(after.data()!['orderQuotaMonth'], currentQuotaMonthKey());
      expect(after.data()!['orderQuotaUsed'], 1);
    });

    test('orderLimitOverride bypasses the computed rating tier', () async {
      final userRef = firestore.collection('users').doc('worker1');
      await userRef.set({
        'orderQuotaMonth': currentQuotaMonthKey(),
        'orderQuotaUsed': 1,
        'ratingSum': 0,
        'ratingCount': 0, // would normally cap at starter quota 8
        'orderLimitOverride': 1, // admin manually restricted this worker
      });

      // Already used 1 of the overridden limit of 1 -> must throw.
      expect(
        () => firestore.runTransaction((tx) async {
          final snap = await tx.get(userRef);
          consumeOrderQuotaInTransaction(tx, userRef, snap.data());
        }),
        throwsA(isA<WorkerQuotaExceededException>()),
      );
    });
  });
}
