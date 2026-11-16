# सहयात्री — Sahyatri App

**Sahyatri (सहयात्री)** — Bikash Bhandari को आफ्नै Flutter app: स्थानीय worker marketplace (ride/driver, handyman, hotel, salon, wallet, chat/call)।

> Local worker marketplace app built with Flutter + Firebase.

## के के छ (Structure)

| Folder | काम |
|---|---|
| `lib/` | Flutter app को मुख्य code (screens, services, widgets) |
| `functions/` | Firebase Cloud Functions (backend) |
| `android/`, `ios/`, `web/` | Platform files |
| `assets/` | Logo, images, fonts |
| `firestore.rules`, `storage.rules` | Firebase security rules |
| `third_party/` | Patch गरिएको `flutter_webrtc` |
| `scripts/release/` | Release / test-data scripts |

## चलाउने तरिका (Run)

```bash
flutter pub get
flutter run
```

Release signing को लागि `android/key.properties.example` हेर्नुहोस्।
