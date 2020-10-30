import Flutter
import UIKit
import AVKit

public class SwiftCamera2Plugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.sonerik.camera2", binaryMessenger: registrar.messenger())
        let instance = SwiftCamera2Plugin()
        let factory = CameraPreviewFactory(messenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(factory, withId: "cameraPreview")
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "hasCameraPermission":
            if AVCaptureDevice.authorizationStatus(for: AVMediaType.video) == AVAuthorizationStatus.authorized {
                result(true)
            } else {
                result(false)
            }
        default: result(FlutterMethodNotImplemented)
        }
    }
}

private class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var messenger: FlutterBinaryMessenger?
    
    init(messenger: FlutterBinaryMessenger) {
        super.init()
        self.messenger = messenger
    }
    
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let view = CameraPreviewView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
        return view
    }
}

private class CameraPreviewView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private let _viewId: Int64
    
    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        _view = UIView()
        _viewId = viewId
        super.init()
        
        let channel = FlutterMethodChannel(name: "dev.sonerik.camera2/preview_\(viewId)", binaryMessenger: messenger!)
        channel.setMethodCallHandler({[weak self] (call: FlutterMethodCall, result: FlutterResult) -> Void in
            self?.handleMethodCall(call: call, result: result)
        })
    }
    
    deinit {
        NSLog("deinit: \(_viewId)")
    }
    
    func view() -> UIView {
        return _view
    }
    
    func handleMethodCall(call: FlutterMethodCall, result: FlutterResult) -> Void {
        NSLog("call: \(call.method)")
    }
}
