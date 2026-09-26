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
// Google Directions को मोड नाम नै "साँचो" (canonical) — client/Firestore ले
// यही तीन मध्ये एउटा मात्र पठाउन पाउँछ, नत्र अमान्य/जालसाजी input सिधै
// third-party API मा नजाओस्। OSRM fallback मा यही keys बाट फरक profile
// नाममा नक्सा गरिन्छ (OSRM ले "bicycling" चिन्दैन, "cycling" चाहिन्छ)।
const VALID_MODES = new Set(["driving", "walking", "bicycling"]);
const OSRM_PROFILE = {driving: "driving", walking: "foot", bicycling: "cycling"};

exports.getRoute = onCall({secrets: [MAPS_API_KEY]}, async (request) => {
  const {originLat, originLng, destLat, destLng} = request.data || {};
  const nums = [originLat, originLng, destLat, destLng];
  if (nums.some((v) => typeof v !== "number" || Number.isNaN(v))) {
    throw new HttpsError(
        "invalid-argument",
        "originLat, originLng, destLat, destLng (numbers) चाहिन्छ।",
    );
  }
  const modeInput = String(request.data?.mode || "driving");
  const mode = VALID_MODES.has(modeInput) ? modeInput : "driving";

  // १) Google Directions
  try {
    const url = "https://maps.googleapis.com/maps/api/directions/json" +
        `?origin=${originLat},${originLng}` +
        `&destination=${destLat},${destLng}` +
        `&mode=${mode}&key=${MAPS_API_KEY.value()}`;
    const res = await fetch(url);
    const body = await res.json();
    const route = body.status === "OK" ? body.routes?.[0] : null;
    const leg = route?.legs?.[0];
    const encoded = route?.overview_polyline?.points;
    if (encoded && leg) {
      console.log("getRoute google source origin=", originLat, originLng,
          "dest=", destLat, destLng, "km=", (leg.distance?.value || 0) / 1000,
          "steps=", leg.steps?.length, "encodedLen=", encoded.length,
          "summary=", route.summary, "polyline=", encoded);
      console.log("getRoute step start/end points=", JSON.stringify(
          (leg.steps || []).map((s) => ({
            start: s.start_location, end: s.end_location,
            instr: (s.html_instructions || "").replace(/<[^>]+>/g, ""),
          })),
      ));
      return {
        polyline: encoded,
        km: (leg.distance?.value || 0) / 1000,
        minutes: Math.round((leg.duration?.value || 0) / 60),
        real: true,
        source: "google",
        mode,
      };
    }
    console.warn("Directions non-OK:", body.status);
  } catch (err) {
    console.error("Directions call failed:", err);
  }

  // २) OSRM fallback — geometries=polyline ले Google कै Encoded Polyline
  // Algorithm Format दिन्छ, client ले उही decoder प्रयोग गर्न सकोस् भनेर।
  // सार्वजनिक OSRM demo server ले profile-अनुसार फरक होस्ट चलाउँछ भन्ने
  // ग्यारेन्टी छैन, तर driving/foot/cycling तीनै router.project-osrm.org
  // मा नै उपलब्ध छन्।
  try {
    const profile = OSRM_PROFILE[mode] || "driving";
    const url = `https://router.project-osrm.org/route/v1/${profile}/` +
        `${originLng},${originLat};${destLng},${destLat}` +
        "?overview=full&geometries=polyline";
    const res = await fetch(url, {
      headers: {"User-Agent": "KaamMitra/1.0"},
    });
    const body = await res.json();
    const route = body.routes?.[0];
    if (route?.geometry) {
      console.log("getRoute osrm source origin=", originLat, originLng,
          "dest=", destLat, destLng, "km=", (route.distance || 0) / 1000,
          "encodedLen=", route.geometry.length);
      return {
        polyline: route.geometry,
        km: (route.distance || 0) / 1000,
        minutes: Math.round((route.duration || 0) / 60),
        real: true,
        source: "osrm",
        mode,
      };
    }
  } catch (err) {
    console.error("OSRM call failed:", err);
  }

  // दुवै असफल — client ले यसलाई "route unavailable" भनेर देखाउने, कुनै
  // सीधा-रेखा fallback कहिल्यै बनाउँदैन।
  throw new HttpsError("unavailable", "Route भेटिएन।");
});

/**
 * Ride-Hailing destination search — Google Geocoding API सधैँ यहाँबाट
 * (server-side) कल हुन्छ, `getRoute` कै उही कारणले (CORS + key कहिल्यै
 * browser मा नदेखिने)। अघि client (Flutter) बाटै सिधै Nominatim (OSM)
 * प्रयोग हुँदै थियो — त्यसले Nepal-बाहिरका ठेगाना (टेस्ट/विदेशी) भेट्दैनथ्यो
 * (`countrycodes=np` restriction) र प्रायः native Google Maps जस्तो
 * प्रस्ट/सही नतिजा दिँदैनथ्यो। अब त्यही एउटै Maps API key (Directions कै,
 * यसमा Geocoding API पनि enabled हुनुपर्छ — Google Cloud Console मा
 * "Geocoding API" enable गर्नुपर्ने हुनसक्छ) प्रयोग गर्छ। `region=np` ले
 * Nepal-नजिकका नतिजा प्राथमिकतामा राख्छ, तर बाहिरका पूर्ण रूपमा रोक्दैन —
 * ठ्याक्कै native Google Maps जस्तै global खोजी।
 */
exports.geocodeSearch = onCall({secrets: [MAPS_API_KEY]}, async (request) => {
  const query = String(request.data?.query || "").trim();
  if (query.length < 2) {
    throw new HttpsError("invalid-argument", "query (कम्तिमा २ अक्षर) चाहिन्छ।");
  }
  const biasLat = request.data?.biasLat;
  const biasLng = request.data?.biasLng;
  // पहिले यहाँ bias बिन्दु Nepal भित्रै हो कि छैन जाँचेर, Nepal-बाहिर भए
  // bounds नै नलगाउने (unbiased global खोजी) गरिएको थियो — त्यो त्यो बेला
  // देखिएको Poland नतिजा (जो साँच्चै stale client build कै bug थियो, यो
  // bounds mechanism कै होइन) बाट डराएर थपिएको अत्यधिक सावधानी थियो। तर
  // यसले वास्तविक समस्या ल्यायो: प्रयोगकर्ता Nepal-बाहिर (जस्तै टेस्टिङका
  // क्रममा Poland बाट) भए, स्थानीय खोजी (उस्तै/नजिकैको सडक-नाम भएका फरक-फरक
  // सहर, जस्तै Szczecin भित्रको "Chorwacka/Rondo" टाढाको Poznań मा गएर
  // बस्ने) कहिल्यै सही disambiguate हुँदैनथ्यो — किनभने bounds नै पठाइँदैनथ्यो।
  // अब जहाँसुकैको बायस बिन्दु भए पनि (Nepal-मात्र सीमित होइन) सधैँ त्यही
  // वरपर bounds लगाउने — यही नै साँचो "प्रयोगकर्ता हाल कहाँ छ, त्यहीं
  // प्राथमिकता" व्यवहार हो (native Google Maps जस्तै)।
  const hasBias = typeof biasLat === "number" && typeof biasLng === "number";

  // haversine (km) — बायस बिन्दुदेखि हरेक नतिजा साँच्चै कति टाढा छ भनेर।
  const distKm = (lat, lng) => {
    const R = 6371;
    const dLat = (lat - biasLat) * Math.PI / 180;
    const dLng = (lng - biasLng) * Math.PI / 180;
    const a = Math.sin(dLat / 2) ** 2 +
        Math.cos(biasLat * Math.PI / 180) * Math.cos(lat * Math.PI / 180) *
        Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
  };

  const runGeocode = async (useBias) => {
    const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
    url.searchParams.set("address", query);
    url.searchParams.set("key", MAPS_API_KEY.value());
    if (useBias && hasBias) {
      // `bounds` Google का अनुसार "bias मात्र, restrict होइन" — व्यवहारमा
      // यसले टाढाको (तर bounds भित्रै पर्ने ठूलो box मा) उस्तै-नाम भएको
      // ठाउँलाई नजिकैको भन्दा माथि राख्न सक्छ (जस्तै एउटै "Szkolna 23"
      // Goleniów नजिकै भए पनि टाढाको Międzywodzie नै दिने)। त्यसैले box
      // सानो (~15-18km, साँच्चै "यही सहर/वरपर" जति मात्र) राख्ने, अनि तलको
      // दूरी-अनुसार sort ले नै अन्तिम टुङ्गो लगाउने — bounds त सुरुमै टाढाका
      // धेरै असम्बन्धित नतिजा हटाउने पहिलो तह मात्र हो।
      url.searchParams.set(
          "bounds", `${biasLat - 0.15},${biasLng - 0.15}|${biasLat + 0.15},${biasLng + 0.15}`,
      );
    } else if (!hasBias) {
      // बायस बिन्दु नै नआएको (दुर्लभ) अवस्थामा मात्र — यो app मूलतः Nepal-
      // केन्द्रित भएकोले हल्का ccTLD झुकाव।
      url.searchParams.set("region", "np");
    }
    const res = await fetch(url.toString());
    return res.json();
  };

  try {
    console.log("geocodeSearch query:", query, "hasBias:", hasBias,
        "biasLat:", biasLat, "biasLng:", biasLng);
    let body = await runGeocode(true);
    // Local-First Fallback — स्थानीय (bounds-सीमित) खोजीले केही नभेटे मात्र
    // (कहिल्यै त्यसैले सधैँ हुने होइन) फेरि सिधै bounds-रहित (फराकिलो/global)
    // खोजी — नत्र bounds बाहिरको साँच्चै मात्र-त्यहीँ भएको ठाउँ (टाढाको सहर/
    // देशको ठ्याक्कै ठेगाना खोज्दा) कहिल्यै भेटिँदैनथ्यो।
    if (body.status === "ZERO_RESULTS" && hasBias) {
      console.log("geocodeSearch local bounds empty — falling back to wider search");
      body = await runGeocode(false);
    }
    console.log("geocodeSearch status:", body.status,
        "topResult:", body.results?.[0]?.formatted_address);
    if (body.status !== "OK" && body.status !== "ZERO_RESULTS") {
      console.warn("Geocode non-OK:", body.status, body.error_message);
    }
    const results = Array.isArray(body.results) ? body.results : [];
    let mapped = results.map((r) => ({
      label: r.formatted_address || "",
      lat: r.geometry?.location?.lat,
      lng: r.geometry?.location?.lng,
    })).filter((r) => r.label && typeof r.lat === "number" && typeof r.lng === "number");
    // bounds "bias मात्र, restrict होइन" भएकोले Google ले नै टाढाको उस्तै-
    // नाम भएको नतिजालाई नजिकैको भन्दा माथि राखिदिन सक्छ — त्यसैले यहाँ
    // साँच्चै दूरी (haversine) अनुसार पुनः-क्रमबद्ध गरेर नजिकैको सधैँ
    // पहिलो (Enter/Search key ले सिधै छान्ने पनि यही "पहिलो" नै हो) बनाउने।
    if (hasBias) {
      mapped = mapped
          .map((r) => ({...r, _km: distKm(r.lat, r.lng)}))
          .sort((a, b) => a._km - b._km)
          .map(({_km, ...rest}) => rest);
    }
    return {results: mapped.slice(0, 6)};
  } catch (err) {
    console.error("Geocode call failed:", err);
    throw new HttpsError("unavailable", "खोजी असफल भयो।");
  }
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

// NOTE: completed-booking auto-delete (previously `cleanupCompletedBookings`,
// a 24-hourly scheduled function that hard-deleted any `serviceRequests` doc
// 3 days after `status == 'completed'`) was removed — completed jobs must
// now stay permanently, both in the worker's own history and the admin/owner
// dashboard, for accounting. Sensitive chat/phone data is already purged
// immediately at completion time (job_actions.dart::
// purgeSensitiveDataOnCompletion), so nothing private lingers in the kept
// doc — only transaction metadata (price, payment method, timestamps,
// commission split) remains, which is exactly what accounting needs.
// `reviews` docs were already permanent and are unaffected.
