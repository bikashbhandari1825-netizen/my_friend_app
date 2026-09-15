// functions/index.js
//
// KaamMitra का लागि एउटै, सामान्य (generic) Cloud Function: `notifications`
// collection मा जतिपटक नयाँ document बन्छ (जुन client-side बाट
// `createNotification`/`createNotificationForUser` ले लेख्छ — job accepted,
// counter-offer, आदि जुनसुकै feature बाट), त्यसैको `uid` फिल्डको प्रयोगकर्ताको
// `users/{uid}.fcmToken` पढेर, त्यही एउटा notification real FCM push को
// रूपमा पनि पठाउँछ।
//
// किन यहाँ (server-side) मात्र सम्भव: client (Flutter app) बाट सिधै अर्को
// प्रयोगकर्तालाई FCM push पठाउन FCM server key चाहिन्छ, जुन client app मा
// राख्नु insecure हुन्छ (जसले पायो उसैले त्यो key चोरेर जोसुकैलाई जे-सुकै
// push पठाउन सक्छ)। Cloud Function ले भने Admin SDK मार्फत, प्रोजेक्टकै
// service account प्रयोग गरेर, सुरक्षित रूपमा पठाउँछ।
//
// Deploy गर्न (Firebase project Blaze/pay-as-you-go plan मा हुनुपर्छ —
// Cloud Functions Spark/free plan मा चल्दैन):
//   cd functions && npm install
//   firebase deploy --only functions
//
// (firebase.json मा "functions": { "source": "functions" } थप्नुपर्छ —
// यो deploy गर्ने बेला थपिनेछ, deploy नगरेसम्म बाँकी app मा कुनै असर पर्दैन।)
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

// यही Maps API key — AndroidManifest.xml/web/index.html मै पनि प्रयोग भएकै
// (Maps SDK/JS API लाई)। Directions call भने अब सिधै browser बाट होइन, यहीँ
// server-side बाट मात्र हुन्छ — त्यसैले न त CORS ले रोक्छ, न key नै browser
// को network tab मा देखिन्छ। Cloud Secret Manager मा राखिएको — कोडमा
// plaintext होइन; `firebase functions:secrets:set MAPS_API_KEY` ले
// deploy अघि एकपटक सेट गर्नुपर्छ।
const MAPS_API_KEY = defineSecret("MAPS_API_KEY");

/**
 * दुई बिन्दुबीचको सडक-मार्ग — Directions API सधैँ यहाँबाट (server-side) कल
 * हुन्छ, browser (विशेष गरी Flutter web) बाट सिधै कल गर्दा CORS ले रोक्ने
 * समस्या यहाँ आउँदैन। Android/web दुवैले यही एउटा function बाट उही
 * polyline/दूरी/समय पाउँछन् — दुई फरक बाटो छैन।
 *
 * Directions असफल भए (quota/no-route) OSRM (नि:शुल्क, त्यो पनि server-side)
 * मा गिर्छ — त्यो पनि साँचो सडक-मार्ग नै हो, केवल स्रोत फरक। दुवै असफल भए
 * मात्र error फर्काउँछ — कहिल्यै सीधा रेखालाई "route" भनेर देखाउँदैन; त्यो
 * निर्णय अब client ले होइन, यहीँ लिन्छ।
 */
exports.getRoute = onCall({secrets: [MAPS_API_KEY]}, async (request) => {
  const {originLat, originLng, destLat, destLng} = request.data || {};
  const nums = [originLat, originLng, destLat, destLng];
  if (nums.some((v) => typeof v !== "number" || Number.isNaN(v))) {
    throw new HttpsError(
        "invalid-argument",
        "originLat, originLng, destLat, destLng (numbers) चाहिन्छ।",
    );
  }

  // १) Google Directions
  try {
    const url = "https://maps.googleapis.com/maps/api/directions/json" +
        `?origin=${originLat},${originLng}` +
        `&destination=${destLat},${destLng}` +
        `&mode=driving&key=${MAPS_API_KEY.value()}`;
    const res = await fetch(url);
    const body = await res.json();
    const route = body.status === "OK" ? body.routes?.[0] : null;
    const leg = route?.legs?.[0];
    const encoded = route?.overview_polyline?.points;
    if (encoded && leg) {
      return {
        polyline: encoded,
        km: (leg.distance?.value || 0) / 1000,
        minutes: Math.round((leg.duration?.value || 0) / 60),
        real: true,
        source: "google",
      };
    }
    console.warn("Directions non-OK:", body.status);
  } catch (err) {
    console.error("Directions call failed:", err);
  }

  // २) OSRM fallback — geometries=polyline ले Google कै Encoded Polyline
  // Algorithm Format दिन्छ, client ले उही decoder प्रयोग गर्न सकोस् भनेर।
  try {
    const url = "https://router.project-osrm.org/route/v1/driving/" +
        `${originLng},${originLat};${destLng},${destLat}` +
        "?overview=full&geometries=polyline";
    const res = await fetch(url, {
      headers: {"User-Agent": "KaamMitra/1.0"},
    });
    const body = await res.json();
    const route = body.routes?.[0];
    if (route?.geometry) {
      return {
        polyline: route.geometry,
        km: (route.distance || 0) / 1000,
        minutes: Math.round((route.duration || 0) / 60),
        real: true,
        source: "osrm",
      };
    }
  } catch (err) {
    console.error("OSRM call failed:", err);
  }

  // दुवै असफल — client ले यसलाई "route unavailable" भनेर देखाउने, कुनै
  // सीधा-रेखा fallback कहिल्यै बनाउँदैन।
  throw new HttpsError("unavailable", "Route भेटिएन।");
});

exports.sendPushForNotification = onDocumentCreated(
    "notifications/{notifId}",
    async (event) => {
      const data = event.data?.data();
      if (!data || !data.uid) return;

      const userSnap = await admin.firestore()
          .collection("users").doc(data.uid).get();
      const token = userSnap.data()?.fcmToken;
      if (!token) return; // token नभेटिए in-app notification doc मात्रै पर्याप्त

      const requestId = data.requestId;
      // सबै extra field (type/mode/callerName/callerUid जस्ता) client ले
      // पहिले `requestId` मात्र नछोडी forward गर्ने — नत्र client-side FCM
      // message.data मा ती कहिल्यै आउँदैनथे, र incoming-call push notification
      // ट्याप गर्दा client ले "call" भनेर चिन्नै नसकी सामान्य job-update जस्तै
      // (गलत रूपमा नक्सा screen मा) पठाउँथ्यो।
      const pushData = {};
      if (requestId) pushData.requestId = String(requestId);
      if (data.type) pushData.type = String(data.type);
      if (data.mode) pushData.mode = String(data.mode);
      if (data.callerName) pushData.callerName = String(data.callerName);
      if (data.callerUid) pushData.callerUid = String(data.callerUid);
      try {
        await admin.messaging().send({
          token,
          notification: {
            title: data.title || "",
            body: data.body || "",
          },
          data: pushData,
          android: {
            notification: {channelId: "kaammitra_job_updates"},
          },
        });
      } catch (err) {
        // token expire/invalid भएको सामान्य केस — फेरि कहिल्यै valid नहुने
        // भए हटाइदिने, ताकि भविष्यका push हरूले फेरि-फेरि असफल नहोऊन्।
        if (
          err.code === "messaging/registration-token-not-registered" ||
          err.code === "messaging/invalid-registration-token"
        ) {
          await admin.firestore().collection("users").doc(data.uid)
              .update({fcmToken: admin.firestore.FieldValue.delete()})
              .catch(() => {});
        } else {
          console.error("FCM send failed:", err);
        }
      }
    },
);

/**
 * Completed Bookings Cleanup — काम "completed" भएको ठ्याक्कै ३ दिनपछि
 * त्यसको `serviceRequests` doc (+ associated `chats/{id}` doc/messages र
 * `calls/{id}` signaling doc) आफैं मेटिन्छ। `Cancelled` भएका booking त
 * client ले नै accept/cancel गर्नेबित्तिकै तुरुन्तै मेटिसक्छन्
 * (job_actions.dart::deleteCancelledBooking) — यो scheduled function ले
 * केवल "completed" (payment/rating सकिएको, history मा अस्थायी रूपमा
 * देखिनुपर्ने) booking हरू ३ दिनपछि सफा गर्छ।
 *
 * `reviews` collection (worker rating) कहिल्यै मेटिँदैन — त्यो worker कै
 * स्थायी history हो, यो booking record को जीवनकालसँग बाँधिएको छैन।
 */
exports.cleanupCompletedBookings = onSchedule(
    {schedule: "every 24 hours", timeZone: "UTC"},
    async () => {
      const cutoff = admin.firestore.Timestamp.fromMillis(
          Date.now() - 3 * 24 * 60 * 60 * 1000,
      );
      const snap = await admin.firestore()
          .collection("serviceRequests")
          .where("status", "==", "completed")
          .where("completedAt", "<=", cutoff)
          .get();
      if (snap.empty) {
        console.log("cleanupCompletedBookings: nothing due.");
        return;
      }

      for (const doc of snap.docs) {
        const id = doc.id;
        try {
          const msgs = await admin.firestore()
              .collection("chats").doc(id).collection("messages").get();
          const batch = admin.firestore().batch();
          msgs.docs.forEach((m) => batch.delete(m.ref));
          batch.delete(admin.firestore().collection("chats").doc(id));
          batch.delete(
              admin.firestore().collection("serviceRequests").doc(id),
          );
          await batch.commit();
          await admin.firestore().collection("calls").doc(id).delete()
              .catch(() => {});
        } catch (err) {
          console.error(`cleanupCompletedBookings failed for ${id}:`, err);
        }
      }
      console.log(
          `cleanupCompletedBookings: removed ${snap.size} booking(s).`,
      );
    },
);
