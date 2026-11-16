// functions/appcheck.js
//
// Firebase App Check को सर्भर-साइड "enforce" स्विच — एउटै ठाउँबाट।
// `true` गरेपछि App Check token नभएका (बोट/स्क्रिप्ट/क्लोन एप) कल सुरुमै रोकिन्छन्।
//
// ⚠ अहिले `false` राखिएको छ किनभने क्लाइन्ट Play Integrity provider प्रयोग
// गर्छ: Play Store बाट install नगरिएको (adb/APK बाट sideload गरेको) एपमा
// token बन्दैन, र `true` गर्दा तपाईंका आफ्नै परीक्षण build पनि रोकिन्छन्।
// Play Store/Internal testing मा एप राखेपछि: (१) Firebase Console → App Check
// → Play Integrity दर्ता, (२) यहाँ `true` बनाएर deploy।
exports.ENFORCE_APP_CHECK = false;
