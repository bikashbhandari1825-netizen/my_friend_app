# एक्लो developer का लागि पूरा-ride परीक्षण (दुई फोन र बाहिर नगई)

**सेटअप:** laptop को Chrome = **यात्री (passenger)**, तपाईंको एउटै फोन = **driver**। इन्टरनेट एउटै hotspot बाट चले पनि हुन्छ।

## ० – एकपटक तयारी
- दुई फरक खाता: एउटा यात्री (Chrome), अर्को स्वीकृत driver (फोन)।
- driver खाता: `role=worker`, `verificationStatus=approved`, सेवा Auto/Bike/Car।

## १ – चलाउने आदेश (project folder बाट)

**Chrome (यात्री):**
```bash
flutter run -d chrome --web-port 5001
```

**फोन (driver) — असली GPS को सट्टा नक्कली हिँडाइ सहित:**
```bash
flutter run -d <फोन-id> --dart-define=SIM_GPS=1
```
`flutter devices` ले फोनको id देखाउँछ। `SIM_GPS=1` केवल debug/profile मा चल्छ, release APK मा कहिल्यै होइन।

## २ – परीक्षण A: Home नक्सामा driver को लाइभ स्थान
1. फोनमा driver लगइन गर्नुहोस्, "Online" राख्नुहोस्। लगमा `ONLINE_LOC SIMULATION started` र हरेक ~३ सेकेन्डमा `ONLINE_LOC wrote … (SIM)` देखिनुपर्छ।
2. Chrome मा यात्री लगइन → Home → सेवा "Auto" छान्नुहोस्।
3. नक्सामा driver को आइकन ~४०० मिटरको वर्गमा सर्नुपर्छ। driver लाई Offline गर्दा वा ५ मिनेट अपडेट नभए आइकन हराउनुपर्छ।

## ३ – परीक्षण B: पूरा ride (अनुरोध → भुक्तानी → रेटिङ)
1. **Chrome (यात्री):** Auto छानेर pickup/drop राख्नुहोस्, अनुरोध पठाउनुहोस्। "बाँकी समय" गणना देखिनुपर्छ; चाहे "भाडा बढाउनुहोस्" थिचेर जाँच्नुहोस्।
2. **फोन (driver):** "Find Nearby Rides" → कार्ड देखिन्छ → Accept।
3. **OTP:** यात्रीको स्क्रिनमा ४-अंकको कोड देखिन्छ; driver ले आइपुगेपछि त्यही हालेर ride सुरु गर्छ।
4. **लाइभ ट्र्याकिङ:** driver को route स्क्रिनमा **"Simulate GPS"** थिच्नुहोस् (debug मा देखिन्छ) → गाडी बाटोमा आफैं चल्छ; Chrome मा यात्रीको नक्सामा सँगसँगै सर्नुपर्छ। यात्रीको Chrome कन्सोल (F12) मा `GPS_LATENCY ms=… gapMs=…` हेर्नुहोस्।
5. **पूरा:** driver "Job Completed" → यात्रीले "Complete" थिचेर रेटिङ दिन्छ। वालेटमा कमिसन काटिनुपर्छ, `Completed` र रिभ्यू गन्ती एक-एक बढ्नुपर्छ।

## ४ – लगमा के खोज्ने
| लग उपसर्ग | अर्थ |
|---|---|
| `ONLINE_LOC wrote …` | driver को स्थान लेखियो (`(SIM)` = नक्कली) |
| `FEED_SNAPSHOT added/removed`, `FEED_FILTER result: shown=` | अनुरोध driver सम्म आयो / कार्ड बन्यो |
| `GPS_LATENCY ms=` | यात्रीले लाइभ स्थान पाउने ढिलाइ |
| `GPS_WRITE_FAILED` | driver को लेखाइ असफल |
| `permission-denied` | rules/सुरक्षाले रोक्यो (सुधार चाहिन्छ) |

## ५ – यसले जाँच्छ र जाँच्दैन
**जाँच्छ:** अनुरोध → कार्ड → accept → OTP → ट्र्याकिङ चल्ने तर्क → पूरा/कमिसन/रेटिङ → सुरक्षा rules, सर्भर function, Firestore सिंक।
**जाँच्दैन:** असली GPS शोर, सडकको असली नेटवर्क ढिलाइ, फोनको background ब्याट्री-नियन्त्रण, धेरै driver। यसका लागि सार्वजनिक गर्नुअघि १०–२० जना परीक्षकसँग Play Store को Internal testing मा एक हप्ता चलाउनुहोस्।

## नोट
- Firebase Emulator (Java) र Android emulator यो laptop मा अहिले छैनन्। चाहियो भने JDK र AVD राखेर पछि थप्न सकिन्छ, तर माथिको सेटअपले यही hardware मा काम गर्छ।
