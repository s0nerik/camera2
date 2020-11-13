package dev.sonerik.camera2

import android.content.Context
import android.graphics.*
import android.util.Size
import androidx.camera.core.ImageProxy
import java.nio.ByteBuffer

enum class ColorOrder {
    RGB, RBG, GRB, GBR, BRG, BGR,
}

enum class Normalization {
    UBYTE, BYTE, UFLOAT, FLOAT
}

class ImageAnalysisHelper(
        context: Context,
        private val targetSize: Size,
        private val colorOrder: ColorOrder,
        private val normalization: Normalization
) {
    private lateinit var analysisBitmap: Bitmap

    private var targetRotationDegrees: Int = 0
    private lateinit var targetBitmap: Bitmap

    private val yuvToRgbConverter = YuvToRgbConverter(context)

    private val outBuffer = ByteBuffer.allocate(targetSize.width * targetSize.height * 3)
    private val bitmapBuffer = IntArray(targetSize.width * targetSize.height * 4)

    private val colorsBuffer = IntArray(3) { 0 }

    private var _lastFrame: ByteArray? = null
    val lastFrame: ByteArray?
        get() = _lastFrame

    fun getAnalysisFrame(image: ImageProxy): ByteArray {
        if (!::analysisBitmap.isInitialized || analysisBitmap.width != image.width || analysisBitmap.height != image.height) {
            analysisBitmap = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        }
        yuvToRgbConverter.yuvToRgb(image, analysisBitmap)

        if (!::targetBitmap.isInitialized || targetRotationDegrees != image.imageInfo.rotationDegrees) {
            targetRotationDegrees = image.imageInfo.rotationDegrees
            targetBitmap = createTargetBitmap(
                    targetSize = targetSize,
                    rotationDegrees = image.imageInfo.rotationDegrees
            )
        }

        writeScaledRotatedBitmap(analysisBitmap, targetBitmap)
        writeAnalyzableBitmapToBuffer(targetBitmap, outBuffer)
        val frame = outBuffer.array()
        _lastFrame = frame
        return frame
    }

    private fun writeAnalyzableBitmapToBuffer(bitmap: Bitmap, buffer: ByteBuffer) {
        buffer.rewind()
        bitmap.getPixels(bitmapBuffer, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val colors = colorsBuffer
        for (y in 0 until bitmap.height) {
            for (x in 0 until bitmap.width) {
                val i = y * bitmap.width + x
                val px = bitmapBuffer[i]

                // Get channel values from the pixel value.
                when (colorOrder) {
                    ColorOrder.RGB -> {
                        colors[0] = Color.red(px)
                        colors[1] = Color.green(px)
                        colors[2] = Color.blue(px)
                    }
                    ColorOrder.RBG -> {
                        colors[0] = Color.red(px)
                        colors[1] = Color.blue(px)
                        colors[2] = Color.green(px)
                    }
                    ColorOrder.GRB -> {
                        colors[0] = Color.green(px)
                        colors[1] = Color.red(px)
                        colors[2] = Color.blue(px)
                    }
                    ColorOrder.GBR -> {
                        colors[0] = Color.green(px)
                        colors[1] = Color.blue(px)
                        colors[2] = Color.red(px)
                    }
                    ColorOrder.BRG -> {
                        colors[0] = Color.blue(px)
                        colors[1] = Color.red(px)
                        colors[2] = Color.green(px)
                    }
                    ColorOrder.BGR -> {
                        colors[0] = Color.blue(px)
                        colors[1] = Color.green(px)
                        colors[2] = Color.red(px)
                    }
                }

                // Normalize channel values.
                //
                // Ranges:
                // UBYTE: [0, 255]
                // BYTE: [-127, 127]
                // UFLOAT: [0.0, 1.0]
                // FLOAT: [-1.0, 1.0]
                //
                when (normalization) {
                    Normalization.UBYTE -> {
                        buffer.put(colors[0].toByte())
                        buffer.put(colors[1].toByte())
                        buffer.put(colors[2].toByte())
                    }
                    Normalization.BYTE -> {
                        buffer.put((colors[0] - 127).toByte())
                        buffer.put((colors[1] - 127).toByte())
                        buffer.put((colors[2] - 127).toByte())
                    }
                    Normalization.UFLOAT -> {
                        buffer.putFloat(colors[0] / 255f)
                        buffer.putFloat(colors[1] / 255f)
                        buffer.putFloat(colors[2] / 255f)
                    }
                    Normalization.FLOAT -> {
                        buffer.putFloat((colors[0] - 127) / 127f)
                        buffer.putFloat((colors[1] - 127) / 127f)
                        buffer.putFloat((colors[2] - 127) / 127f)
                    }
                }
            }
        }
    }

    private fun createTargetBitmap(targetSize: Size, rotationDegrees: Int): Bitmap {
        val swapWithHeight = rotationDegrees == 90 || rotationDegrees == 270
        return Bitmap.createBitmap(
                if (!swapWithHeight) targetSize.width else targetSize.height,
                if (!swapWithHeight) targetSize.height else targetSize.width,
                Bitmap.Config.ARGB_8888
        )
    }

    private fun writeScaledRotatedBitmap(source: Bitmap, target: Bitmap) {
        val canvas = Canvas(target)
        canvas.rotate(targetRotationDegrees.toFloat(), target.width.toFloat() / 2, target.height.toFloat() / 2)
        canvas.drawBitmap(source, null, Rect(0, 0, target.width, target.height), null)
    }
}
