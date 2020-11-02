import Flutter
import UIKit
import AVKit

public class SwiftCamera2Plugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.sonerik.camera2", binaryMessenger: registrar.messenger())
        let instance = SwiftCamera2Plugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let cameraProviderHolder = CameraProviderHolder()
        let factory = CameraPreviewFactory(messenger: registrar.messenger(), cameraProviderHolder: cameraProviderHolder)
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

private class CameraProviderHolder {
    private var session: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "capture session queue")
    
    private var activePreviewIds = [Int64]()
    private let activePreviews = NSMapTable<NSNumber, CameraPreviewView>()
    
    func onPreviewCreated(viewId: Int64, previewView: CameraPreviewView) {
        //        if (session == nil) {
        //            session = AVCaptureSession()
        //        }
        if (activePreviews.count == 0) {
            session = prepareSession()
            sessionQueue.async { [weak self] in
                self?.session?.startRunning()
            }
        }
        activePreviews.setObject(previewView, forKey: NSNumber(value: viewId))
        activePreviewIds.append(viewId)
        previewView.captureSession = session
    }
    
    func onPreviewDisposed(viewId: Int64) {
        activePreviews.removeObject(forKey: NSNumber(value: viewId))
        if let idIndex = activePreviewIds.firstIndex(of: viewId) {
            activePreviewIds.remove(at: idIndex)
        }
        
        if (activePreviews.count == 0) {
            session?.stopRunning()
            session = nil
        } else {
            if let lastId = activePreviewIds.last {
                activePreviews.object(forKey: NSNumber(value: lastId))?.captureSession = session
            }
        }
    }
    
    func prepareSession() -> AVCaptureSession? {
        let session = AVCaptureSession()

        let videoDevice = AVCaptureDevice.devices(for: AVMediaType.video).first { (device) -> Bool in
            device.position == AVCaptureDevice.Position.back
        }
        let videoDeviceInput: AVCaptureDeviceInput!
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice!)
        } catch let error as NSError {
            videoDeviceInput = nil
            NSLog("Could not create video device input: %@", error)
        } catch _ {
            fatalError()
        }
        
        let stillImageOutput = AVCaptureStillImageOutput()
        stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
        
        session.beginConfiguration()
        if session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)
        }
        if session.canAddOutput(stillImageOutput) {
            session.addOutput(stillImageOutput)
        }
        session.commitConfiguration()
        
        return session
    }
}

private class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger?
    private let cameraProviderHolder: CameraProviderHolder?
    
    init(messenger: FlutterBinaryMessenger, cameraProviderHolder: CameraProviderHolder) {
        self.messenger = messenger
        self.cameraProviderHolder = cameraProviderHolder
        super.init()
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
            binaryMessenger: messenger,
            onDispose: {
                self.cameraProviderHolder?.onPreviewDisposed(viewId: viewId)
            }
        )
        cameraProviderHolder?.onPreviewCreated(viewId: viewId, previewView: view)
        return view
    }
}

private class CameraPreviewView: NSObject, FlutterPlatformView {
    private var _view: UIPreviewView
    private let _viewId: Int64
    private let _onDispose: (() -> Void)?
    
    var captureSession: AVCaptureSession? {
        get { return _view.videoPreviewLayer.session }
        set { _view.videoPreviewLayer.session = newValue }
    }
    
    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?,
        onDispose: (() -> Void)?
    ) {
        _view = UIPreviewView()
        _viewId = viewId
        _onDispose = onDispose
        super.init()
        
        let channel = FlutterMethodChannel(name: "dev.sonerik.camera2/preview_\(viewId)", binaryMessenger: messenger!)
        channel.setMethodCallHandler({[weak self] (call: FlutterMethodCall, result: FlutterResult) -> Void in
            self?.handleMethodCall(call: call, result: result)
        })
    }
    
    deinit {
        NSLog("deinit: \(_viewId)")
        if let onDispose = _onDispose {
            onDispose()
        }
    }
    
    func view() -> UIView {
        return _view
    }
    
    func handleMethodCall(call: FlutterMethodCall, result: FlutterResult) -> Void {
        NSLog("call: \(call.method)")
    }
}

private class UIPreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    /// Convenience wrapper to get layer as its statically known type.
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}
