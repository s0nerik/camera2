import Foundation
import AVKit

enum C2ColorOrder {
    case rgb
    case rbg
    case grb
    case gbr
    case brg
    case bgr
}

enum C2Normalization {
    case ubyte
    case byte
    case ufloat
    case float
}

struct C2AnalysisOptions {
    let imageSize: CGSize
    let colorOrder: C2ColorOrder
    let normalization: C2Normalization
    let centerCropAspectRatio: CGFloat?
    let centerCropWidthPercent: CGFloat?
    
    init(dictionary opts: Dictionary<String, Any?>) {
        switch (opts["colorOrder"] as! String) {
        case "rgb": self.colorOrder = C2ColorOrder.rgb
        case "rbg": self.colorOrder = C2ColorOrder.rbg
        case "gbr": self.colorOrder = C2ColorOrder.gbr
        case "grb": self.colorOrder = C2ColorOrder.grb
        case "brg": self.colorOrder = C2ColorOrder.brg
        case "bgr": self.colorOrder = C2ColorOrder.bgr
        default:
            fatalError("'colorOrder' value must be one of ['rgb', 'rbg', 'gbr', 'grb', 'brg', 'bgr']")
        }
        
        switch (opts["normalization"] as! String) {
        case "ubyte" : self.normalization = C2Normalization.ubyte
        case "byte"  : self.normalization = C2Normalization.byte
        case "ufloat": self.normalization = C2Normalization.ufloat
        case "float" : self.normalization = C2Normalization.float
        default:
            fatalError("'normalization' value must be one of ['ubyte', 'byte', 'ufloat', 'float']")
        }
        
        self.imageSize = CGSize(
            width: (opts["imageWidth"] as! NSNumber).intValue,
            height: (opts["imageHeight"] as! NSNumber).intValue
        )
        
        if let centerCropAspectRatio = (opts["centerCropAspectRatio"] as? NSNumber)?.floatValue {
            self.centerCropAspectRatio = CGFloat(centerCropAspectRatio)
        } else {
            self.centerCropAspectRatio = nil
        }
        if let centerCropWidthPercent = (opts["centerCropWidthPercent"] as? NSNumber)?.floatValue {
            self.centerCropWidthPercent = CGFloat(centerCropWidthPercent)
        } else {
            self.centerCropWidthPercent = nil
        }
    }
}

class C2ImageAnalysisBitmapHelper : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "analysis bitmap helper queue")
    
    private let helpers: Dictionary<String, C2ImageAnalysisHelper>
    
    init(helpers: Dictionary<String, C2ImageAnalysisHelper>) {
        self.helpers = helpers
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        connection.videoOrientation = AVCaptureVideoOrientation.portrait
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return  }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        let context = CIContext()
        guard let origCgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        helpers.forEach { (_: String, helper: C2ImageAnalysisHelper) in
            helper.getAnalysisFrame(origCgImage: origCgImage)
        }
        
        context.clearCaches()
    }
}

class C2ImageAnalysisHelper : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let opts: C2AnalysisOptions
    private var analysisBuffer: UnsafeMutableBufferPointer<UInt8>?

    var lastFrame: Data? {
        get {
            if let buf = analysisBuffer {
                if (buf.isEmpty) {
                    return nil
                }
                return Data(bytesNoCopy: buf.baseAddress!, count: buf.count, deallocator: .none)
            } else {
                return nil
            }
        }
    }
    
    init(opts: C2AnalysisOptions) {
        self.opts = opts
        self.analysisBuffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(opts.imageSize.width * opts.imageSize.height * 3))
        super.init()
    }
    
    deinit {
        analysisBuffer?.deallocate()
    }
    
    func getAnalysisFrame(origCgImage: CGImage) {
        guard let cgImage = resize(origCgImage),
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return
        }
        
        if (cgImage.height != Int(opts.imageSize.height) || cgImage.width != Int(opts.imageSize.width)) {
            fatalError("Analysis image size must stay the same")
        }

        let bytesPerPixel = cgImage.bitsPerPixel / cgImage.bitsPerComponent
        
        guard let analysisBuffer = analysisBuffer else { return }
        
        var i = 0
        for y in 0 ..< cgImage.height {
            for x in 0 ..< cgImage.width {
                let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
                analysisBuffer[i] = bytes[offset]
                analysisBuffer[i + 1] = bytes[offset + 1]
                analysisBuffer[i + 2] = bytes[offset + 2]
                i += 3
            }
        }
    }
    
    private func resize(_ image: CGImage) -> CGImage? {
        guard let colorSpace = image.colorSpace else { return nil }
        guard let context = CGContext(
            data: nil,
            width: Int(opts.imageSize.width),
            height: Int(opts.imageSize.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: image.bytesPerRow,
            space: colorSpace,
            bitmapInfo: image.alphaInfo.rawValue
        ) else { return nil }
        
        var croppedImage = image
        
        if let centerCropWidthPercent = opts.centerCropWidthPercent,
           let centerCropAspectRatio = opts.centerCropAspectRatio {
            let targetCropRect = centerCroppedStencilRect(
                rect: CGRect(
                    x: 0,
                    y: 0,
                    width: Int(image.width),
                    height: Int(image.height)
                ),
                stencilWidthPercent: CGFloat(centerCropWidthPercent),
                stencilAspectRatio: CGFloat(centerCropAspectRatio)
            )
            croppedImage = image.cropping(to: targetCropRect)!
        }
        
        // draw image to context (resizing it)
        context.interpolationQuality = .none
        context.draw(
            croppedImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: Int(opts.imageSize.width),
                height: Int(opts.imageSize.height)
            )
        )
        
        // extract resulting image from context
        return context.makeImage()
    }
}
