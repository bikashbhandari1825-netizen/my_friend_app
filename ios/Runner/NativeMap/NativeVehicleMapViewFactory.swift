import Flutter
import UIKit

/// Dart तर्फको `UiKitView(viewType: "kaamMitra/native_vehicle_map")` ले यही
/// factory पुग्छ — Android (`NativeVehicleMapViewFactory.kt`) कै उही भूमिका।
class NativeVehicleMapViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return NativeVehicleMapView(frame: frame, viewId: viewId, messenger: messenger)
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
