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

@available(iOS 11.0, *)
private class CameraProviderHolder {
    private let sessionQueue = DispatchQueue(label: "capture session queue", qos: .userInitiated)
    
    private var activePreviewIds = [Int64]()
    private let activePreviews = NSMapTable<NSNumber, CameraPreviewView>(keyOptions: .weakMemory, valueOptions: .weakMemory)
    private let activePreviewSessions = NSMapTable<NSNumber, AVCaptureSession>(keyOptions: .weakMemory, valueOptions: .weakMemory)
    private let activePreviewOutputs = NSMapTable<NSNumber, AVCapturePhotoOutput>(keyOptions: .weakMemory, valueOptions: .weakMemory)

    func getPhotoOutput(viewId: Int64) -> AVCapturePhotoOutput? {
        return activePreviewOutputs.object(forKey: NSNumber(value: viewId))
    }

    func onPreviewCreated(viewId: Int64, previewView: CameraPreviewView, previewArgs: CameraPreviewArgs?) {
        let session = AVCaptureSession()
        prepareSession(session: session, viewId: viewId, previewArgs: previewArgs)
        previewView.captureSession = session

        sessionQueue.async {
            session.startRunning()
        }

        activePreviews.setObject(previewView, forKey: NSNumber(value: viewId))
        activePreviewIds.append(viewId)
    }
    
    func onPreviewDisposed(viewId: Int64) {
        let key = NSNumber(value: viewId)

        if let idIndex = activePreviewIds.firstIndex(of: viewId) {
            activePreviewIds.remove(at: idIndex)
        }
        
        if let session = activePreviewSessions.object(forKey: key) {
            sessionQueue.async {
                session.stopRunning()
            }
            activePreviewSessions.removeObject(forKey: key)
        }

        activePreviewOutputs.removeObject(forKey: key)

        activePreviews.removeObject(forKey: key)
    }
    
    func detachLastPreview() {
        guard let viewId = activePreviewIds.last else {
            return
        }
        let lastActivePreview = activePreviews.object(forKey: NSNumber(value: viewId))
        DispatchQueue.main.async {
            lastActivePreview?.captureSession = nil
        }
    }
    
    func prepareSession(session: AVCaptureSession, viewId: Int64, previewArgs: CameraPreviewArgs?) {
        session.beginConfiguration()

        // Set preferred resolution
        if previewArgs?.preferredPhotoWidth != nil && previewArgs?.preferredPhotoHeight != nil {
            session.sessionPreset = presetFromPreferredResolution(
                width: previewArgs!.preferredPhotoWidth!,
                height:previewArgs!.preferredPhotoHeight!
            )
        } else {
            session.sessionPreset = .photo
        }

        // Init camera input device
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
        
        // Init camera output
        let output = AVCapturePhotoOutput()
        
        if session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        
        // Store output and AVCaptureSession for later access
        activePreviewOutputs.setObject(output, forKey: NSNumber(value: viewId))
        activePreviewSessions.setObject(session, forKey: NSNumber(value: viewId))
    }
    
    private func presetFromPreferredResolution(width: Int, height: Int) -> AVCaptureSession.Preset {
        let pixels = width * height
        if (pixels <= 1280 * 720) {
            return .hd1280x720
        }
        if (pixels <= 1920 * 1080) {
            return .hd1920x1080
        }
        if (pixels <= 3840 * 2160) {
            return .hd4K3840x2160
        }
        return .photo
    }
}

private struct CameraPreviewArgs {
    let preferredPhotoWidth: Int?
    let preferredPhotoHeight: Int?
}

@available(iOS 11.0, *)
private class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger?
    private let cameraProviderHolder: CameraProviderHolder?
    
    init(messenger: FlutterBinaryMessenger, cameraProviderHolder: CameraProviderHolder) {
        self.messenger = messenger
        self.cameraProviderHolder = cameraProviderHolder
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        var previewArgs: CameraPreviewArgs?
        if let args = args as? Dictionary<String, Any?> {
            previewArgs = CameraPreviewArgs(
                preferredPhotoWidth: args["preferredPhotoWidth"] as? Int,
                preferredPhotoHeight: args["preferredPhotoHeight"] as? Int
            )
        }
        let view = CameraPreviewView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger,
            onDispose: {
                self.cameraProviderHolder?.onPreviewDisposed(viewId: viewId)
            },
            cameraProviderHolder: cameraProviderHolder
        )
        cameraProviderHolder?.onPreviewCreated(viewId: viewId, previewView: view, previewArgs: previewArgs)
        return view
    }
}

@available(iOS 11.0, *)
private class CameraPreviewView: NSObject, FlutterPlatformView {
    private var _view: UIPreviewView
    private let _viewId: Int64
    private let _onDispose: (() -> Void)?
    private let _cameraProviderHolder: CameraProviderHolder?
    private let _messenger: FlutterBinaryMessenger?
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureDelegate]()
    
    var captureSession: AVCaptureSession? {
        get { return _view.videoPreviewLayer.session }
        set { _view.videoPreviewLayer.session = newValue }
    }
    
    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?,
        onDispose: (() -> Void)?,
        cameraProviderHolder: CameraProviderHolder?
    ) {
        _view = UIPreviewView()
        _view.videoPreviewLayer.videoGravity = .resizeAspectFill

        _viewId = viewId
        _onDispose = onDispose
        _cameraProviderHolder = cameraProviderHolder
        _messenger = messenger
        super.init()
        
        let channel = FlutterMethodChannel(name: "dev.sonerik.camera2/preview_\(viewId)", binaryMessenger: messenger!)
        channel.setMethodCallHandler({[weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
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
    
    func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) -> Void {
        NSLog("call: \(call.method)")
        switch (call.method) {
        case "takePicture":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "", message: "Arguments must be provided", details: nil))
                return
            }
            let id = args["id"] as! Int64
            let pictureBytesChannel = FlutterMethodChannel(name: "dev.sonerik.camera2/takePicture/\(id)", binaryMessenger: _messenger!)
            
            let captureArgs = PhotoCaptureArgs(
                centerCropAspectRatio: args["centerCropAspectRatio"] as? Double,
                centerCropWidthPercent: args["centerCropWidthPercent"] as? Double
            )
            
            let photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            photoSettings.flashMode = .auto
            let delegate = PhotoCaptureDelegate(
                result: result,
                pictureBytesChannel: pictureBytesChannel,
                args: captureArgs,
                onComplete: { [weak self] in self?.inProgressPhotoCaptureDelegates[photoSettings.uniqueID] = nil }
            )
            inProgressPhotoCaptureDelegates[photoSettings.uniqueID] = delegate
            _cameraProviderHolder?.getPhotoOutput(viewId: _viewId)?.capturePhoto(with: photoSettings, delegate: delegate)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private struct PhotoCaptureArgs {
    let centerCropAspectRatio: Double?
    let centerCropWidthPercent: Double?
}

@available(iOS 11.0, *)
private class PhotoCaptureDelegate : NSObject, AVCapturePhotoCaptureDelegate {
    private let _result: FlutterResult
    private let _pictureBytesChannel: FlutterMethodChannel
    private let _args: PhotoCaptureArgs?
    private let _onComplete: () -> Void

    init(result: @escaping FlutterResult, pictureBytesChannel: FlutterMethodChannel, args: PhotoCaptureArgs?, onComplete: @escaping () -> Void) {
        _result = result
        _pictureBytesChannel = pictureBytesChannel
        _args = args
        _onComplete = onComplete
        super.init()
    }
    
    deinit {
        NSLog("deinit PhotoCaptureDelegate")
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        _result(nil)
    }
    
    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            _pictureBytesChannel.invokeMethod("error", arguments: error.localizedDescription)
        } else {
            var imageData: Data?
            if (_args?.centerCropAspectRatio != nil && _args?.centerCropWidthPercent != nil) {
                let croppedImage = cropPhoto(
                    photo: photo,
                    centerCropAspectRatio: _args!.centerCropAspectRatio!,
                    centerCropWidthPercent: _args!.centerCropWidthPercent!
                )
                imageData = croppedImage?.jpegData(compressionQuality: 80)
            } else {
                imageData = photo.fileDataRepresentation()
            }
            
            if let imageData = imageData {
                let resultData = FlutterStandardTypedData(bytes: imageData)
                _pictureBytesChannel.invokeMethod("result", arguments: resultData)
            } else {
                _pictureBytesChannel.invokeMethod("error", arguments: "couldn't read photo bytes")
            }
        }
    }
    
    func photoOutput(_: AVCapturePhotoOutput, didFinishCaptureFor: AVCaptureResolvedPhotoSettings, error: Error?) {
        _onComplete()
    }
    
    private func cropPhoto(
        photo: AVCapturePhoto,
        centerCropAspectRatio: Double,
        centerCropWidthPercent: Double
    ) -> UIImage? {
        let cgImage = photo.cgImageRepresentation()!.takeUnretainedValue()
        let orientation = photo.metadata[kCGImagePropertyOrientation as String] as! UInt32
        let imageOrientation = CGImagePropertyOrientation(rawValue: orientation)!

        let src = bakeOrientation(
            imageRef: cgImage,
            orienation: imageOrientation
        )

        let w = Double(src.width) * centerCropWidthPercent
        let h = w / centerCropAspectRatio
        
        let srcX = Double(src.width) / 2.0 - w / 2.0
        let srcY = Double(src.height) / 2.0 - h / 2.0
        
        let cropRect = CGRect(x: srcX, y: srcY, width: w, height: h)

        if let croppedCGImage = src.cropping(to: cropRect) {
            return UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: .up)
        }
        
        return nil
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

private func bakeOrientation(imageRef: CGImage, orienation: CGImagePropertyOrientation) -> CGImage {
    let originalWidth = imageRef.width
    let originalHeight = imageRef.height
    let bitsPerComponent = imageRef.bitsPerComponent
    let bytesPerRow = imageRef.bytesPerRow

    let bitmapInfo = imageRef.bitmapInfo

    guard let colorSpace = imageRef.colorSpace else {
        fatalError()
    }

    var degreesToRotate: Double
    var swapWidthHeight: Bool
    var mirrored: Bool
    switch orienation {
    case .up:
        degreesToRotate = 0.0
        swapWidthHeight = false
        mirrored = false
        break
    case .upMirrored:
        degreesToRotate = 0.0
        swapWidthHeight = false
        mirrored = true
        break
    case .right:
        degreesToRotate = -90.0
        swapWidthHeight = true
        mirrored = false
        break
    case .rightMirrored:
        degreesToRotate = -90.0
        swapWidthHeight = true
        mirrored = true
        break
    case .down:
        degreesToRotate = 180.0
        swapWidthHeight = false
        mirrored = false
        break
    case .downMirrored:
        degreesToRotate = 180.0
        swapWidthHeight = false
        mirrored = true
        break
    case .left:
        degreesToRotate = 90.0
        swapWidthHeight = true
        mirrored = false
        break
    case .leftMirrored:
        degreesToRotate = 90.0
        swapWidthHeight = true
        mirrored = true
        break
    }
    let radians = degreesToRotate * Double.pi / 180.0

    var width: Int
    var height: Int
    if swapWidthHeight {
        width = originalHeight
        height = originalWidth
    } else {
        width = originalWidth
        height = originalHeight
    }

    let contextRef = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)!
    contextRef.translateBy(x: CGFloat(width) / 2.0, y: CGFloat(height) / 2.0)
    if mirrored {
        contextRef.scaleBy(x: -1.0, y: 1.0)
    }
    contextRef.rotate(by: CGFloat(radians))
    if swapWidthHeight {
        contextRef.translateBy(x: -CGFloat(height) / 2.0, y: -CGFloat(width) / 2.0)
    } else {
        contextRef.translateBy(x: -CGFloat(width) / 2.0, y: -CGFloat(height) / 2.0)
    }
    contextRef.draw(imageRef, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(originalWidth), height: CGFloat(originalHeight)))
    return contextRef.makeImage()!
}
