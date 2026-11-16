import CoreLocation
import Flutter
import GoogleMaps
import UIKit

/// Native Vehicle Map Overlay — Android (`NativeVehicleMapView.kt`) कै उही
/// architecture र method-channel contract (`snapTo`/`updateTarget`/`setRoute`/
/// `setDestination`): साँचो Google Maps iOS SDK माथि, मार्कर native साइडमै
/// (Dart setState/widget rebuild बिना) `CADisplayLink`-driven animation ले
/// एनिमेट गर्छ। `CADisplayLink` स्वतः iOS को frame-pacing सँग synced हुन्छ
/// (Android कै `ValueAnimator`/Choreographer कै समानान्तर)। Road-snapping
/// (route.points माथिको cumulative-दूरी interpolation) पनि route_map_view.dart
/// (Dart) र Android native view दुवैसँग उस्तै एल्गोरिदम।
///
/// यो फाइल यो Windows मेसिनबाट कहिल्यै compile/test हुन सकेको छैन — iOS मा
/// Xcode बाट पहिलोपटक build हुँदा नै साँच्चै प्रमाणित हुन्छ।
class NativeVehicleMapView: NSObject, FlutterPlatformView {
    private let mapView: GMSMapView
    private var vehicleMarker: GMSMarker?
    private var destinationMarker: GMSMarker?
    private var routePolyline: GMSPolyline?

    private var displayedLat: Double = 0
    private var displayedLng: Double = 0
    private var displayedBearing: Double = 0

    private var vehicleType = "bike"
    private let vehicleIconCache = NSCache<NSString, UIImage>()
    private var routePoints: [CLLocationCoordinate2D] = []

    private var displayLink: CADisplayLink?
    private var animStart: CFTimeInterval = 0
    private let animDuration: CFTimeInterval = 0.8
    private var animFromLat: Double = 0
    private var animFromLng: Double = 0
    private var animFromBearing: Double = 0
    private var animToLat: Double = 0
    private var animToLng: Double = 0
    private var animToBearing: Double = 0
    private var animUseRoute = false
    private var animFromDist: Double = 0
    private var animToDist: Double = 0

    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        // `GMSMapView(options:)` लाई SDK 7.4+ चाहिने भएकोले — पहिलोपटक Mac मा
        // `pod install` ले ठ्याक्कै कुन GoogleMaps version तान्छ भन्ने यो
        // मेसिनबाट प्रमाणित गर्न नसकिने भएकोले, धेरै पुरानो SDK देखि नै
        // स्थिर रहेको classic initializer प्रयोग (version-compat जोखिम हटाउन)।
        let camera = GMSCameraPosition(latitude: 0, longitude: 0, zoom: 16)
        mapView = GMSMapView(frame: frame, camera: camera)
        channel = FlutterMethodChannel(
            name: "kaamMitra/native_vehicle_map_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()
        // Rotate/tilt gesture toggle Android (`uiSettings.isRotateGesturesEnabled`)
        // जस्तो सिधै mapView माथि होइन — iOS SDK मा `GMSUISettings` (मार्फत
        // `mapView.settings`) मुनि मात्र पुग्छ।
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    func view() -> UIView { mapView }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "updateTarget":
            if let lat = args["lat"] as? Double, let lng = args["lng"] as? Double {
                let bearing = args["bearing"] as? Double ?? 0
                animateTo(lat: lat, lng: lng, bearing: bearing)
            }
            result(nil)
        case "snapTo":
            // पहिलोपटक (वा route फेरिएको क्षण) — कुनै glide बिना, सिधै।
            if let type = args["vehicleType"] as? String { vehicleType = type }
            if let lat = args["lat"] as? Double, let lng = args["lng"] as? Double {
                let bearing = args["bearing"] as? Double ?? 0
                displayLink?.invalidate()
                displayLink = nil
                displayedLat = lat
                displayedLng = lng
                displayedBearing = bearing
                placeOrMoveMarker(lat: lat, lng: lng, bearing: bearing)
                mapView.camera = GMSCameraPosition(
                    target: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    zoom: 19, bearing: bearing, viewingAngle: 0
                )
            }
            result(nil)
        case "setRoute":
            let rawPoints = args["points"] as? [[String: Double]] ?? []
            routePoints = rawPoints.compactMap { p in
                guard let lat = p["lat"], let lng = p["lng"] else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            drawRoutePolyline()
            result(nil)
        case "setDestination":
            if let lat = args["lat"] as? Double, let lng = args["lng"] as? Double {
                placeDestinationMarker(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func drawRoutePolyline() {
        routePolyline?.map = nil
        guard routePoints.count >= 2 else {
            routePolyline = nil
            return
        }
        let path = GMSMutablePath()
        for pt in routePoints { path.add(pt) }
        let polyline = GMSPolyline(path: path)
        polyline.strokeWidth = 5
        polyline.strokeColor = UIColor(red: 0.486, green: 0.302, blue: 1.0, alpha: 1.0)
        polyline.map = mapView
        routePolyline = polyline
    }

    private func placeDestinationMarker(_ pos: CLLocationCoordinate2D) {
        if let existing = destinationMarker {
            existing.position = pos
        } else {
            let marker = GMSMarker(position: pos)
            marker.groundAnchor = CGPoint(x: 0.5, y: 1.0)
            marker.icon = GMSMarker.markerImage(with: .orange)
            marker.map = mapView
            destinationMarker = marker
        }
    }

    private func vehicleIcon(_ type: String) -> UIImage? {
        let key = type as NSString
        if let cached = vehicleIconCache.object(forKey: key) { return cached }
        let assetFile: String
        switch type {
        case "car": assetFile = "assets/images/car_top.png"
        case "walking": assetFile = "assets/images/walking_top.png"
        default: assetFile = "assets/images/bike_top.png"
        }
        guard let image = loadFlutterAssetImage(assetFile) else { return nil }
        // Dart कै route_map_view.dart मा उही 92 logical-px लक्ष्य-उचाइ —
        // दुवै साइडमा आइकन उस्तै साइज देखियोस् भनेर।
        let targetH: CGFloat = 92
        let targetW = targetH * image.size.width / image.size.height
        let resized = resize(image, to: CGSize(width: targetW, height: targetH))
        vehicleIconCache.setObject(resized, forKey: key)
        return resized
    }

    private func resize(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Flutter ले IPA भित्र बन्डल गरेको asset — Android कै `FlutterLoader`
    /// lookup key कै समानान्तर, iOS मा `FlutterDartProject.lookupKey`।
    private func loadFlutterAssetImage(_ assetPath: String) -> UIImage? {
        let key = FlutterDartProject.lookupKey(forAsset: assetPath)
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    private func placeOrMoveMarker(lat: Double, lng: Double, bearing: Double) {
        let pos = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        if let existing = vehicleMarker {
            existing.position = pos
            existing.rotation = bearing
        } else {
            let marker = GMSMarker(position: pos)
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.rotation = bearing
            // Asset कुनै कारणले नभेटिए पनि test harness कहिल्यै crash नहोस्।
            marker.icon = vehicleIcon(vehicleType) ?? GMSMarker.markerImage(with: .red)
            marker.flat = true
            marker.map = mapView
            vehicleMarker = marker
        }
    }

    private func animateTo(lat: Double, lng: Double, bearing: Double) {
        guard vehicleMarker != nil else {
            // पहिलो बिन्दु — सिधै राख्ने, glide भोलिको नयाँ बिन्दुदेखि मात्र।
            displayedLat = lat
            displayedLng = lng
            displayedBearing = bearing
            placeOrMoveMarker(lat: lat, lng: lng, bearing: bearing)
            return
        }
        displayLink?.invalidate()

        animFromLat = displayedLat
        animFromLng = displayedLng
        animFromBearing = displayedBearing
        animToLat = lat
        animToLng = lng

        // Road Snapping — route उपलब्ध भए सीधा chord होइन, route.points
        // माथिकै cumulative-दूरी interpolation (Android/Dart कै उही एल्गोरिदम)।
        animUseRoute = routePoints.count >= 2
        if animUseRoute {
            animFromDist = projectDistanceAlongRoute(
                routePoints, CLLocationCoordinate2D(latitude: animFromLat, longitude: animFromLng))
            animToDist = projectDistanceAlongRoute(
                routePoints, CLLocationCoordinate2D(latitude: lat, longitude: lng))
            animToBearing = bearingAtRouteDistance(routePoints, animToDist) ?? bearing
        } else {
            animToBearing = bearing
        }

        animStart = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(onAnimTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func onAnimTick() {
        let now = CACurrentMediaTime()
        var t = (now - animStart) / animDuration
        let finished = t >= 1
        if finished { t = 1 }

        let lat: Double
        let lng: Double
        if animUseRoute {
            let dist = animFromDist + (animToDist - animFromDist) * t
            if let snapped = pointAtRouteDistance(routePoints, dist) {
                lat = snapped.latitude
                lng = snapped.longitude
            } else {
                lat = animFromLat + (animToLat - animFromLat) * t
                lng = animFromLng + (animToLng - animFromLng) * t
            }
        } else {
            lat = animFromLat + (animToLat - animFromLat) * t
            lng = animFromLng + (animToLng - animFromLng) * t
        }

        // 0°/360° wrap नघुमी सधैँ छोटो बाटोबाट मात्र घुम्ने।
        var bearingDelta = (animToBearing - animFromBearing).truncatingRemainder(dividingBy: 360)
        if bearingDelta > 180 { bearingDelta -= 360 }
        if bearingDelta < -180 { bearingDelta += 360 }
        let bearing = animFromBearing + bearingDelta * t

        displayedLat = lat
        displayedLng = lng
        displayedBearing = bearing
        placeOrMoveMarker(lat: lat, lng: lng, bearing: bearing)
        mapView.camera = GMSCameraPosition(
            target: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            zoom: 19, bearing: bearing, viewingAngle: 0
        )

        if finished {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    // ── Road-Snapping हेल्पर — route_map_view.dart (Dart) र Android native
    // view (Kotlin) कै उही तीन function को Swift port ──

    private func haversineKm(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6371.0088
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private func projectDistanceAlongRoute(
        _ pts: [CLLocationCoordinate2D], _ query: CLLocationCoordinate2D
    ) -> Double {
        guard pts.count >= 2 else { return 0 }
        let latKmPerDeg = 111.32
        var bestDistSq = Double.greatestFiniteMagnitude
        var bestCum = 0.0
        var cum = 0.0
        for i in 1..<pts.count {
            let a = pts[i - 1]
            let b = pts[i]
            let segLen = haversineKm(a.latitude, a.longitude, b.latitude, b.longitude)
            let lngKmPerDeg = latKmPerDeg * cos(a.latitude * .pi / 180)
            let bx = (b.longitude - a.longitude) * lngKmPerDeg
            let by = (b.latitude - a.latitude) * latKmPerDeg
            let qx = (query.longitude - a.longitude) * lngKmPerDeg
            let qy = (query.latitude - a.latitude) * latKmPerDeg
            let segLenSq = bx * bx + by * by
            var t = segLenSq <= 0 ? 0 : (qx * bx + qy * by) / segLenSq
            t = min(max(t, 0), 1)
            let dx = qx - bx * t
            let dy = qy - by * t
            let distSq = dx * dx + dy * dy
            if distSq < bestDistSq {
                bestDistSq = distSq
                bestCum = cum + segLen * t
            }
            cum += segLen
        }
        return bestCum
    }

    private func pointAtRouteDistance(
        _ pts: [CLLocationCoordinate2D], _ distKm: Double
    ) -> CLLocationCoordinate2D? {
        guard !pts.isEmpty else { return nil }
        if pts.count < 2 { return pts.first }
        let remaining = max(distKm, 0)
        var cum = 0.0
        for i in 1..<pts.count {
            let a = pts[i - 1]
            let b = pts[i]
            let segLen = haversineKm(a.latitude, a.longitude, b.latitude, b.longitude)
            if cum + segLen >= remaining {
                let t = segLen <= 0 ? 0 : (remaining - cum) / segLen
                return CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
            }
            cum += segLen
        }
        return pts.last
    }

    private func bearingAtRouteDistance(
        _ pts: [CLLocationCoordinate2D], _ distKm: Double
    ) -> Double? {
        guard pts.count >= 2 else { return nil }
        var cum = 0.0
        for i in 1..<pts.count {
            let a = pts[i - 1]
            let b = pts[i]
            let segLen = haversineKm(a.latitude, a.longitude, b.latitude, b.longitude)
            if cum + segLen >= distKm || i == pts.count - 1 {
                return bearingBetween(a, b)
            }
            cum += segLen
        }
        return bearingBetween(pts[pts.count - 2], pts[pts.count - 1])
    }

    private func bearingBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    deinit {
        displayLink?.invalidate()
        channel.setMethodCallHandler(nil)
    }
}
