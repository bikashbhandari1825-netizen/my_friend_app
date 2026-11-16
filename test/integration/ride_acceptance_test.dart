// test/integration/ride_acceptance_test.dart
// End-to-end coverage of the Firestore ride/job-acceptance transactions in
// job_actions.dart: claimJobForWorker, acceptRideOffer, and
// acceptWorkerCounterOffer. These exercise multiple collections together
// (serviceRequests, rideOffers, users) through a single FakeFirebaseFirestore
// instance, the same way the real transactions touch them in production —
// this is what caught the real "permission-denied" bug earlier in this
// project (the transaction's combined diff on users/{workerUid} didn't
// match the security-rules carve-out). FakeFirebaseFirestore doesn't
// enforce security rules, so these tests verify the transaction's *data*
// correctness (atomicity, quota gating, busy-worker gating); the rules
// themselves live in firestore.rules and are a separate concern.
//
// Known fake_cloud_firestore (v3.1.0) limitation: when a transaction calls
// tx.set(sameRef, ..., merge: true) twice against the *same* document (as
// claimJobForWorker/acceptRideOffer/acceptWorkerCounterOffer all do — once
// inside consumeOrderQuotaInTransaction for the quota fields, once again
// for activeJobId), the fake's second write replaces the first instead of
// merging with it, so the quota fields don't survive in these tests even
// though real Firestore merges them correctly (this exact multi-field
// merge behavior is what the firestore.rules carve-out for users/{uid} was
// fixed to allow). The quota logic itself is fully covered in isolation by
// test/unit/quota_logic_test.dart; these tests assert on activeJobId
// (which does survive, since it's the later write) instead of re-asserting
// the quota fields here.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_friend_app/screens/job_actions.dart';

/// Pumps a minimal widget tree just deep enough to hand back a real
/// BuildContext with a ScaffoldMessenger ancestor, since acceptRideOffer/
/// acceptWorkerCounterOffer call ScaffoldMessenger.of(context).
Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Builder(builder: (context) {
      ctx = context;
      return const SizedBox();
    })),
  ));
  return ctx;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // acceptRideAtListedPrice (unlike the other accept paths) calls
  // workerLocationForWrite -> getCurrentLocation -> Geolocator, which uses a
  // platform MethodChannel. In a plain widget test there's no platform
  // implementation registered for it, so with no mock handler the await
  // hangs forever instead of failing fast (confirmed live: the test run
  // never progressed past this point). getCurrentLocation() already has its
  // own try/catch that falls back to LocationResult(..., 'error') for any
  // exception — this mock just makes the channel reject immediately so that
  // fallback actually gets a chance to run, matching how the app behaves for
  // real on a device with no location plugin/permission.
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

  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('claimJobForWorker', () {
    test('claims a broadcasting job and stamps the worker as busy',
        () async {
      await firestore.collection('serviceRequests').doc('job1').set({
        'status': 'broadcasting',
        'employerUid': 'employer1',
        'service': 'Plumber',
      });

      await claimJobForWorker(
        docId: 'job1',
        workerUid: 'worker1',
        updateFields: {
          'status': 'accepted',
          'workerUid': 'worker1',
          'acceptedAt': FieldValue.serverTimestamp(),
        },
        firestore: firestore,
      );

      final job =
          await firestore.collection('serviceRequests').doc('job1').get();
      expect(job.data()!['status'], 'accepted');
      expect(job.data()!['workerUid'], 'worker1');

      final user = await firestore.collection('users').doc('worker1').get();
      expect(user.data()!['activeJobId'], 'job1');
    });

    test('refuses to claim a second job while another is still active',
        () async {
      await firestore.collection('users').doc('worker1').set({
        'activeJobId': 'job-existing',
      });
      await firestore.collection('serviceRequests').doc('job-existing').set({
        'status': 'in_progress',
      });
      await firestore.collection('serviceRequests').doc('job-new').set({
        'status': 'broadcasting',
        'employerUid': 'employer2',
      });

      expect(
        () => claimJobForWorker(
          docId: 'job-new',
          workerUid: 'worker1',
          updateFields: {'status': 'accepted', 'workerUid': 'worker1'},
          firestore: firestore,
        ),
        throwsA(isA<WorkerBusyException>()),
      );
    });

    test('a worker whose previous job already ended is free to claim again',
        () async {
      await firestore.collection('users').doc('worker1').set({
        'activeJobId': 'job-old',
      });
      await firestore.collection('serviceRequests').doc('job-old').set({
        'status': 'completed', // no longer active
      });
      await firestore.collection('serviceRequests').doc('job-new').set({
        'status': 'broadcasting',
        'employerUid': 'employer2',
      });

      await claimJobForWorker(
        docId: 'job-new',
        workerUid: 'worker1',
        updateFields: {'status': 'accepted', 'workerUid': 'worker1'},
        firestore: firestore,
      );

      final job =
          await firestore.collection('serviceRequests').doc('job-new').get();
      expect(job.data()!['status'], 'accepted');
      final user = await firestore.collection('users').doc('worker1').get();
      expect(user.data()!['activeJobId'], 'job-new');
    });
  });

  group('acceptRideOffer', () {
    Future<void> seedBroadcastingRide() async {
      await firestore.collection('serviceRequests').doc('ride1').set({
        'status': 'broadcasting',
        'isRide': true,
        'employerUid': 'employer1',
        'proposedPrice': 300,
      });
    }

    Future<void> seedOffer({String status = 'pending'}) async {
      await firestore
          .collection('serviceRequests')
          .doc('ride1')
          .collection('rideOffers')
          .doc('offer1')
          .set({
        'workerUid': 'driver1',
        'workerName': 'Bijay Budha',
        'workerPhone': '9748329291',
        'offerPrice': 250,
        'status': status,
      });
    }

    const offerData = {
      'workerUid': 'driver1',
      'workerName': 'Bijay Budha',
      'workerPhone': '9748329291',
      'offerPrice': 250,
      'vehicleMake': 'Honda',
      'vehicleModel': 'Shine',
      'vehiclePlate': 'BA 12 PA 3456',
      'vehicleDetails': '',
    };

    testWidgets('happy path — accepts a pending offer atomically',
        (tester) async {
      await seedBroadcastingRide();
      await seedOffer();
      final ctx = await _pumpContext(tester);

      await acceptRideOffer(ctx, 'ride1', 'offer1', offerData,
          firestore: firestore);

      final ride =
          await firestore.collection('serviceRequests').doc('ride1').get();
      expect(ride.data()!['status'], 'accepted');
      expect(ride.data()!['workerUid'], 'driver1');
      expect(ride.data()!['finalPrice'], 250);
      expect(ride.data()!['rideStartCode'], isNotNull);
      // Vehicle Details Persistence — the offer's vehicle fields must be
      // copied onto the parent doc, since that's what the passenger's
      // live-tracking screen reads after acceptance (not the offer doc).
      expect(ride.data()!['vehicleMake'], 'Honda');
      expect(ride.data()!['vehicleModel'], 'Shine');
      expect(ride.data()!['vehiclePlate'], 'BA 12 PA 3456');

      final offer = await firestore
          .collection('serviceRequests')
          .doc('ride1')
          .collection('rideOffers')
          .doc('offer1')
          .get();
      expect(offer.data()!['status'], 'accepted');

      final worker = await firestore.collection('users').doc('driver1').get();
      expect(worker.data()!['activeJobId'], 'ride1');
    });

    testWidgets('declines every other pending offer once one is accepted',
        (tester) async {
      await seedBroadcastingRide();
      await seedOffer();
      await firestore
          .collection('serviceRequests')
          .doc('ride1')
          .collection('rideOffers')
          .doc('offer2')
          .set({
        'workerUid': 'driver2',
        'offerPrice': 260,
        'status': 'pending',
      });
      final ctx = await _pumpContext(tester);

      await acceptRideOffer(ctx, 'ride1', 'offer1', offerData,
          firestore: firestore);
      // Let the best-effort "decline other offers" step (post-transaction)
      // run to completion.
      await tester.pumpAndSettle();

      final otherOffer = await firestore
          .collection('serviceRequests')
          .doc('ride1')
          .collection('rideOffers')
          .doc('offer2')
          .get();
      expect(otherOffer.data()!['status'], 'declined');
    });

    testWidgets('a stale (already-accepted) ride refuses a second accept',
        (tester) async {
      await firestore.collection('serviceRequests').doc('ride1').set({
        'status': 'accepted', // already accepted by someone else
        'isRide': true,
        'employerUid': 'employer1',
      });
      await seedOffer();
      final ctx = await _pumpContext(tester);

      // acceptRideOffer catches its own StateError internally (shows a
      // SnackBar) rather than rethrowing, so we assert on the resulting
      // state instead of expecting a thrown exception.
      await acceptRideOffer(ctx, 'ride1', 'offer1', offerData,
          firestore: firestore);

      final offer = await firestore
          .collection('serviceRequests')
          .doc('ride1')
          .collection('rideOffers')
          .doc('offer1')
          .get();
      // Untouched — the transaction must have aborted before writing.
      expect(offer.data()!['status'], 'pending');
    });

    testWidgets('a driver who is already busy elsewhere cannot be accepted',
        (tester) async {
      await seedBroadcastingRide();
      await seedOffer();
      await firestore.collection('users').doc('driver1').set({
        'activeJobId': 'ride-existing',
      });
      await firestore.collection('serviceRequests').doc('ride-existing').set({
        'status': 'in_progress',
      });
      final ctx = await _pumpContext(tester);

      await acceptRideOffer(ctx, 'ride1', 'offer1', offerData,
          firestore: firestore);

      final ride =
          await firestore.collection('serviceRequests').doc('ride1').get();
      // Still broadcasting — the busy-worker guard must have blocked it.
      expect(ride.data()!['status'], 'broadcasting');
    });

    testWidgets('a driver over their monthly quota cannot be accepted',
        (tester) async {
      await seedBroadcastingRide();
      await seedOffer();
      await firestore.collection('users').doc('driver1').set({
        'orderQuotaMonth': currentQuotaMonthKey(),
        'orderQuotaUsed': 2,
        'ratingSum': 5,
        'ratingCount': 5, // avg 1.0 star -> quota 2, already exhausted
      });
      final ctx = await _pumpContext(tester);

      await acceptRideOffer(ctx, 'ride1', 'offer1', offerData,
          firestore: firestore);

      final ride =
          await firestore.collection('serviceRequests').doc('ride1').get();
      expect(ride.data()!['status'], 'broadcasting');
      final worker = await firestore.collection('users').doc('driver1').get();
      // Quota counter must not have been bumped by the aborted transaction.
      expect(worker.data()!['orderQuotaUsed'], 2);
    });
  });

  group('acceptWorkerCounterOffer', () {
    testWidgets('confirms the job at the worker\'s countered price',
        (tester) async {
      await firestore.collection('serviceRequests').doc('job1').set({
        'status': 'pending_employer_approval',
        'employerUid': 'employer1',
        'workerUid': 'worker1',
        'proposedPrice': 500,
        'workerCounterPrice': 650,
        // Non-empty so acceptWorkerCounterOffer skips its myPhoneNumber()
        // backfill call — that helper isn't test-injectable and would hit
        // the real (uninitialized) Firebase singleton in this test.
        'employerPhone': '9800000000',
      });
      final ctx = await _pumpContext(tester);

      await acceptWorkerCounterOffer(ctx, 'job1', firestore: firestore);

      final job =
          await firestore.collection('serviceRequests').doc('job1').get();
      expect(job.data()!['status'], 'confirmed');
      expect(job.data()!['finalPrice'], 650);
      expect(job.data()!['agreedAmount'], 650);

      final worker = await firestore.collection('users').doc('worker1').get();
      expect(worker.data()!['activeJobId'], 'job1');
    });

    testWidgets('a busy worker\'s counter-offer cannot be confirmed',
        (tester) async {
      await firestore.collection('serviceRequests').doc('job1').set({
        'status': 'pending_employer_approval',
        'employerUid': 'employer1',
        'workerUid': 'worker1',
        'workerCounterPrice': 650,
      });
      await firestore.collection('users').doc('worker1').set({
        'activeJobId': 'job-existing',
      });
      await firestore.collection('serviceRequests').doc('job-existing').set({
        'status': 'accepted',
      });
      final ctx = await _pumpContext(tester);

      await acceptWorkerCounterOffer(ctx, 'job1', firestore: firestore);

      final job =
          await firestore.collection('serviceRequests').doc('job1').get();
      expect(job.data()!['status'], 'pending_employer_approval');
    });
  });

  group('acceptRideAtListedPrice', () {
    // Ride Direct-Accept — added when the driver-side "Accept" button was
    // changed to confirm the ride immediately (no passenger approval step)
    // instead of routing through the rideOffers/submitRideOffer flow. Unlike
    // acceptRideOffer, this reads the driver's name/phone fresh via
    // myWorkerName()/myPhoneNumber() rather than from a pre-submitted offer,
    // so it needs an injected MockFirebaseAuth too (see the FirebaseAuth
    // overrides added to myWorkerName/myPhoneNumber alongside this feature).
    MockFirebaseAuth authFor(String uid, {String name = 'Bijay Budha'}) =>
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: uid, displayName: name),
        );

    Future<void> seedBroadcastingRide({num proposedPrice = 210}) async {
      await firestore.collection('serviceRequests').doc('ride1').set({
        'status': 'broadcasting',
        'isRide': true,
        'employerUid': 'employer1',
        'proposedPrice': proposedPrice,
      });
    }

    testWidgets('accepts immediately at the passenger\'s listed price',
        (tester) async {
      await seedBroadcastingRide();
      final ctx = await _pumpContext(tester);

      await acceptRideAtListedPrice(
          ctx, 'ride1', {'proposedPrice': 210, 'employerUid': 'employer1'},
          firestore: firestore, auth: authFor('driver1'));

      final ride =
          await firestore.collection('serviceRequests').doc('ride1').get();
      expect(ride.data()!['status'], 'accepted');
      expect(ride.data()!['workerUid'], 'driver1');
      expect(ride.data()!['finalPrice'], 210);
      expect(ride.data()!['rideStartCode'], isNotNull);

      final worker = await firestore.collection('users').doc('driver1').get();
      expect(worker.data()!['activeJobId'], 'ride1');
    });

    testWidgets(
        'direct-accept copies the driver\'s own vehicle details onto the ride',
        (tester) async {
      await seedBroadcastingRide();
      await firestore.collection('users').doc('driver1').set({
        'vehicleMake': 'Bajaj',
        'vehicleModel': 'Pulsar',
        'vehiclePlate': 'BA 5 KHA 7890',
      });
      final ctx = await _pumpContext(tester);

      await acceptRideAtListedPrice(
          ctx, 'ride1', {'proposedPrice': 210, 'employerUid': 'employer1'},
          firestore: firestore, auth: authFor('driver1'));

      final ride =
          await firestore.collection('serviceRequests').doc('ride1').get();
      expect(ride.data()!['vehicleMake'], 'Bajaj');
      expect(ride.data()!['vehicleModel'], 'Pulsar');
      expect(ride.data()!['vehiclePlate'], 'BA 5 KHA 7890');
    });

    testWidgets(
        'a second driver tapping Accept on an already-accepted ride is '
        'refused (first one wins)', (tester) async {
      await firestore.collection('serviceRequests').doc('ride1').set({
        'status': 'accepted', // driver1 already got it
        'isRide': true,
        'employerUid': 'employer1',
        'workerUid': 'driver1',
        'proposedPrice': 210,
      });
      final ctx = await _pumpContext(tester);

      await acceptRideAtListedPrice(
          ctx, 'ride1', {'proposedPrice': 210, 'employerUid': 'employer1'},
          firestore: firestore, auth: authFor('driver2'));

      final ride =
          await firestore.collection('serviceRequests').doc('ride1').get();
      // Still driver1's — driver2's attempt must have aborted, not overwritten it.
      expect(ride.data()!['workerUid'], 'driver1');
      final driver2 =
          await firestore.collection('users').doc('driver2').get();
      expect(driver2.data()?['activeJobId'], isNot('ride1'));
    });

    testWidgets('a driver who is already busy elsewhere cannot direct-accept',
        (tester) async {
      await seedBroadcastingRide();
      await firestore.collection('users').doc('driver1').set({
        'activeJobId': 'ride-existing',
      });
      await firestore.collection('serviceRequests').doc('ride-existing').set({
        'status': 'in_progress',
      });
      final ctx = await _pumpContext(tester);

      await acceptRideAtListedPrice(
          ctx, 'ride1', {'proposedPrice': 210, 'employerUid': 'employer1'},
          firestore: firestore, auth: authFor('driver1'));

      final ride =
          await firestore.collection('serviceRequests').doc('ride1').get();
      // Still broadcasting — the busy-worker guard must have blocked it.
      expect(ride.data()!['status'], 'broadcasting');
    });

    testWidgets('a driver over their monthly quota cannot direct-accept',
        (tester) async {
      await seedBroadcastingRide();
      await firestore.collection('users').doc('driver1').set({
        'orderQuotaMonth': currentQuotaMonthKey(),
        'orderQuotaUsed': 2,
        'ratingSum': 5,
        'ratingCount': 5, // avg 1.0 star -> quota 2, already exhausted
      });
      final ctx = await _pumpContext(tester);

      await acceptRideAtListedPrice(
          ctx, 'ride1', {'proposedPrice': 210, 'employerUid': 'employer1'},
          firestore: firestore, auth: authFor('driver1'));

      final ride =
          await firestore.collection('serviceRequests').doc('ride1').get();
      expect(ride.data()!['status'], 'broadcasting');
    });
  });
}
