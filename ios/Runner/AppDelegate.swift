import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // `google_maps_flutter` (Dart widget) र Native Vehicle Map Overlay दुवैलाई
    // चाहिने — Android (`AndroidManifest.xml` भित्रको `com.google.android.geo.API_KEY`)
    // कै समानान्तर, तर यो फरक (iOS-specific) key हो, Android कै reuse गर्न
    // मिल्दैन (Google Cloud Console मा iOS bundle ID restriction सहितको
    // छुट्टै key बनाउनुपर्छ, अनि Info.plist भित्रको "GMSApiKey" मा राख्नुपर्छ)।
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }

    // Native Vehicle Map Overlay — यो factory दर्ता नगरे Dart तर्फको
    // `UiKitView(viewType: "kaamMitra/native_vehicle_map")` ले कहिल्यै कुनै
    // native view भेट्दैन (silently खाली देखिन्छ)। Android (`MainActivity.kt`)
    // कै उही भूमिका।
    if let registrar = self.registrar(forPlugin: "NativeVehicleMap") {
      let factory = NativeVehicleMapViewFactory(messenger: registrar.messenger())
      registrar.register(factory, withId: "kaamMitra/native_vehicle_map")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
