import Foundation
import AVKit

func centerCroppedSourceRect(sourceWidth: CGFloat, sourceHeight: CGFloat, targetWidth: CGFloat, targetHeight: CGFloat, inSourceCoordinates: Bool = true) -> CGRect {
    let sourceAspectRatio = sourceWidth / sourceHeight
    let targetAspectRatio = targetWidth / targetHeight
    let widthFactor = sourceWidth / targetWidth
    let heightFactor = sourceHeight / targetHeight
    let scale = sourceAspectRatio <= targetAspectRatio ? widthFactor : heightFactor
    let targetSourceWidth = sourceWidth / scale
    let targetSourceHeight = sourceHeight / scale
    let extraTargetWidth = targetSourceWidth - targetWidth
    let extraSourceWidth = extraTargetWidth * scale
    let extraTargetHeight = targetSourceHeight - targetHeight
    let extraSourceHeight = extraTargetHeight * scale
    
    if (inSourceCoordinates) {
        return CGRect(
            x: extraSourceWidth / 2,
            y: extraSourceHeight / 2,
            width: sourceWidth - extraSourceWidth,
            height: sourceHeight - extraSourceHeight
        )
    } else {
        return CGRect(
            x: extraTargetWidth / 2,
            y: extraTargetHeight / 2,
            width: targetWidth - extraTargetWidth,
            height: targetHeight - extraTargetHeight
        )
    }
}

func centerCroppedStencilRect(rect: CGRect, stencilWidthPercent: CGFloat, stencilAspectRatio: CGFloat) -> CGRect {
    let targetCropWidth = rect.width * stencilWidthPercent
    let targetCropHeight = targetCropWidth / stencilAspectRatio
    let targetCropExtraWidth = rect.width - targetCropWidth
    let targetCropExtraHeight = rect.height - targetCropHeight
    return CGRect(
        x: rect.minX + targetCropExtraWidth / 2,
        y: rect.minY + targetCropExtraHeight / 2,
        width: targetCropWidth,
        height: targetCropHeight
    )
}
