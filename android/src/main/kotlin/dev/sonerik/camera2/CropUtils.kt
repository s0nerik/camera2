package dev.sonerik.camera2

import android.graphics.Rect

fun centerCroppedSourceRect(
        sourceWidth: Float,
        sourceHeight: Float,
        targetWidth: Float,
        targetHeight: Float,
        inSourceCoordinates: Boolean = true
): Rect {
    val sourceAspectRatio = sourceWidth / sourceHeight
    val targetAspectRatio = targetWidth / targetHeight
    val widthFactor = sourceWidth / targetWidth
    val heightFactor = sourceHeight / targetHeight
    val scale = if (sourceAspectRatio <= targetAspectRatio) widthFactor else heightFactor
    val targetSourceWidth = sourceWidth / scale
    val targetSourceHeight = sourceHeight / scale
    val extraTargetWidth = targetSourceWidth - targetWidth
    val extraSourceWidth = extraTargetWidth * scale
    val extraTargetHeight = targetSourceHeight - targetHeight
    val extraSourceHeight = extraTargetHeight * scale

    if (inSourceCoordinates) {
        val width = sourceWidth - extraSourceWidth
        val height = sourceHeight - extraSourceHeight
        val left = extraSourceWidth / 2
        val top = extraSourceHeight / 2
        val right = left + width
        val bottom = top + height
        return Rect(left.toInt(), top.toInt(), right.toInt(), bottom.toInt())
    } else {
        val width = targetWidth - extraTargetWidth
        val height = targetHeight - extraTargetHeight
        val left = extraTargetWidth / 2
        val top = extraTargetHeight / 2
        val right = left + width
        val bottom = top + height
        return Rect(left.toInt(), top.toInt(), right.toInt(), bottom.toInt())
    }
}

fun centerCroppedStencilRect(
        rect: Rect,
        stencilWidthPercent: Float,
        stencilAspectRatio: Float
): Rect {
    val targetCropWidth = rect.width() * stencilWidthPercent
    val targetCropHeight = targetCropWidth / stencilAspectRatio
    val targetCropExtraWidth = rect.width() - targetCropWidth
    val targetCropExtraHeight = rect.height() - targetCropHeight

    val left = rect.left + targetCropExtraWidth / 2
    val top = rect.top + targetCropExtraHeight / 2
    val right = left + targetCropWidth
    val bottom = top + targetCropHeight
    return Rect(left.toInt(), top.toInt(), right.toInt(), bottom.toInt())
}