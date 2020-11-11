package dev.sonerik.camera2

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.drawable.BitmapDrawable
import android.media.MediaActionSound
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.NonNull
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import kotlin.math.max

/** Camera2Plugin */
class Camera2Plugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel

    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

    private lateinit var mainExecutor: Executor
    private val pictureCallbackExecutor = Executors.newSingleThreadExecutor()
    private val analysisBufferExecutor = Executors.newSingleThreadExecutor()

    private lateinit var cameraProviderHolder: CameraProviderHolder

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.sonerik.camera2").apply {
            setMethodCallHandler(this@Camera2Plugin)
        }
        mainExecutor = ContextCompat.getMainExecutor(flutterPluginBinding.applicationContext)
        cameraProviderHolder = CameraProviderHolder(flutterPluginBinding.applicationContext, analysisBufferExecutor)
        flutterPluginBinding.platformViewRegistry
                .registerViewFactory(
                        "cameraPreview",
                        CameraPreviewFactory(
                                messenger = flutterPluginBinding.binaryMessenger,
                                pictureCallbackExecutor = pictureCallbackExecutor,
                                analysisBufferExecutor = analysisBufferExecutor,
                                cameraProviderHolder = cameraProviderHolder
                        )
                )

    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "hasCameraPermission" -> {
                val permissionState = ContextCompat.checkSelfPermission(
                        flutterPluginBinding.applicationContext,
                        Manifest.permission.CAMERA
                )
                if (permissionState == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        cameraProviderHolder.lifecycleOwner = binding.activity as LifecycleOwner
    }

    override fun onDetachedFromActivity() {
        cameraProviderHolder.lifecycleOwner = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    }
}

private data class AnalysisOptions(
        val imageSize: Size,
        val colorOrder: ColorOrder,
        val normalization: Normalization
)

private data class CameraPreviewArgs(
        val preferredPhotoSize: Size?,
        val analysisOptions: AnalysisOptions?
) {
    companion object {
        fun fromMap(args: Map<*, *>): CameraPreviewArgs {
            val preferredPhotoWidth = args["preferredPhotoWidth"] as? Int
            val preferredPhotoHeight = args["preferredPhotoHeight"] as? Int
            val preferredPhotoSize = if (preferredPhotoWidth != null && preferredPhotoHeight != null)
                Size(preferredPhotoWidth, preferredPhotoHeight)
            else
                null

            val analysisOptions = (args["analysisOptions"] as? Map<*, *>)?.let { opts ->
                AnalysisOptions(
                        imageSize = Size(opts["imageWidth"] as Int, opts["imageHeight"] as Int),
                        colorOrder = when (opts["colorOrder"] as String) {
                            "rgb" -> ColorOrder.RGB
                            "rbg" -> ColorOrder.RBG
                            "gbr" -> ColorOrder.GBR
                            "grb" -> ColorOrder.GRB
                            "brg" -> ColorOrder.BRG
                            "bgr" -> ColorOrder.BGR
                            else -> error("'colorOrder' value must be one of ['rgb', 'bgr']")
                        },
                        normalization = when (opts["normalization"] as? String) {
                            "ubyte" -> Normalization.UBYTE
                            "byte" -> Normalization.BYTE
                            "ufloat" -> Normalization.UFLOAT
                            "float" -> Normalization.FLOAT
                            else -> error("'normalization' value must be one of ['ubyte', 'byte', 'ufloat', 'float']")
                        }
                )
            }

            return CameraPreviewArgs(
                    preferredPhotoSize = preferredPhotoSize,
                    analysisOptions = analysisOptions
            )
        }
    }
}

private class CameraPreviewFactory(
        private val messenger: BinaryMessenger,
        private val pictureCallbackExecutor: Executor,
        private val analysisBufferExecutor: Executor,
        private val cameraProviderHolder: CameraProviderHolder
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val previewArgs = CameraPreviewArgs.fromMap(args as Map<*, *>)

        val view = CameraPreviewView(
                id = viewId,
                args = previewArgs,
                context = context,
                messenger = messenger,
                pictureCallbackExecutor = pictureCallbackExecutor,
                analysisBufferExecutor = analysisBufferExecutor,
                cameraProviderHolder = cameraProviderHolder
        )
        cameraProviderHolder.onPreviewCreated(context, viewId, view, previewArgs)
        return view
    }
}

private class CameraProviderHolder(
        private val context: Context,
        private val analysisBufferExecutor: Executor
) {
    var lifecycleOwner: LifecycleOwner? = null

    private var cameraProviderFuture: ListenableFuture<ProcessCameraProvider>? = null
    private val activePreviews = mutableMapOf<Int, CameraPreviewView>()

    private val cameraProvider
        get() = cameraProviderFuture?.get()

    val imagePreview = Preview.Builder()
            .build()

    private var _imageAnalysis: ImageAnalysis? = null
    private var _analysisHelper: ImageAnalysisHelper? = null
    val analysisFrame get() = _analysisHelper?.lastFrame

    private lateinit var _imageCapture: ImageCapture

    val imageCapture: ImageCapture
        get() = _imageCapture

    private val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_BACK)
            .build()

    private lateinit var mainExecutor: Executor

    private fun initImageCapture(args: CameraPreviewArgs) {
        val imageCaptureBuilder = ImageCapture.Builder()
                .setFlashMode(ImageCapture.FLASH_MODE_AUTO)
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
        args.preferredPhotoSize?.let { imageCaptureBuilder.setTargetResolution(it) }
        _imageCapture = imageCaptureBuilder.build()
    }

    private fun initImageAnalysis(args: CameraPreviewArgs) {
        args.analysisOptions?.let { opts ->
            _analysisHelper = ImageAnalysisHelper(
                    targetSize = opts.imageSize,
                    context = context,
                    colorOrder = opts.colorOrder,
                    normalization = opts.normalization
            )

            _imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(opts.imageSize)
                    .build()
            _imageAnalysis!!.setAnalyzer(analysisBufferExecutor, ImageAnalysis.Analyzer { image ->
                image.use { _analysisHelper?.getAnalysisFrame(it) }
            })
        }
    }

    fun onPreviewCreated(context: Context, viewId: Int, previewView: CameraPreviewView, args: CameraPreviewArgs) {
        mainExecutor = ContextCompat.getMainExecutor(context)
        if (cameraProviderFuture == null) {
            cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        }
        if (activePreviews.isEmpty()) {
            initImageCapture(args)
            initImageAnalysis(args)
            withCameraProvider { cameraProvider ->
                if (_imageAnalysis != null) {
                    imagePreview.setSurfaceProvider(previewView.surfaceProvider)
                    cameraProvider?.bindToLifecycle(lifecycleOwner!!, cameraSelector, imagePreview, imageCapture, _imageAnalysis)
                } else {
                    cameraProvider?.bindToLifecycle(lifecycleOwner!!, cameraSelector, imageCapture, imagePreview)
                }
            }
        }
        activePreviews[viewId] = previewView
        withCameraProvider {
            imagePreview.setSurfaceProvider(previewView.surfaceProvider)
        }
    }

    fun onPreviewDisposed(viewId: Int) {
        activePreviews -= viewId
        if (activePreviews.isEmpty()) {
            _analysisHelper = null
            withCameraProvider { cameraProvider ->
                imagePreview.setSurfaceProvider(null)
                cameraProvider?.unbindAll()
            }
        } else {
            activePreviews.values.lastOrNull()?.apply {
                withCameraProvider {
                    imagePreview.setSurfaceProvider(surfaceProvider)
                }
            }
        }
    }

    private fun withCameraProvider(fn: (ProcessCameraProvider?) -> Unit) {
        cameraProviderFuture?.addListener(Runnable {
            fn(cameraProvider)
        }, mainExecutor)
    }
}

private class CameraPreviewView(
        context: Context,
        args: CameraPreviewArgs,
        private val messenger: BinaryMessenger,
        private val id: Int,
        private val pictureCallbackExecutor: Executor,
        private val analysisBufferExecutor: Executor,
        private val cameraProviderHolder: CameraProviderHolder
) : PlatformView, MethodCallHandler {
    private val previewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    }
    private val cameraShotOverlayView = View(context).apply { visibility = View.INVISIBLE }
    private val view = FrameLayout(context).apply {
        addView(previewView)
        addView(cameraShotOverlayView)
    }
    private val resources = context.resources

    private val channel = MethodChannel(messenger, "dev.sonerik.camera2/preview_$id")
            .apply { setMethodCallHandler(this@CameraPreviewView) }

    val surfaceProvider: Preview.SurfaceProvider
        get() = previewView.surfaceProvider

    private fun freezePreview() {
        cameraShotOverlayView.background = BitmapDrawable(resources, previewView.bitmap)
        cameraShotOverlayView.visibility = View.VISIBLE
    }

    private fun unfreezePreview() {
        cameraShotOverlayView.visibility = View.INVISIBLE
    }

    override fun getView() = view

    override fun dispose() {
        cameraProviderHolder.onPreviewDisposed(id)
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "takePicture" -> {
                val id = call.argument<Long>("id")
                val shouldFreezePreview = call.argument("freezePreview") ?: true
                if (shouldFreezePreview) {
                    freezePreview()
                }
                val centerCropAspectRatio = call.argument<Double?>("centerCropAspectRatio")
                val centerCropWidthPercent = call.argument<Double?>("centerCropWidthPercent")

                when (call.argument<String>("flash")) {
                    "on" -> cameraProviderHolder.imageCapture.flashMode = ImageCapture.FLASH_MODE_ON
                    "off" -> cameraProviderHolder.imageCapture.flashMode = ImageCapture.FLASH_MODE_OFF
                    else -> cameraProviderHolder.imageCapture.flashMode = ImageCapture.FLASH_MODE_AUTO
                }

                val pictureBytesChannel = MethodChannel(messenger, "dev.sonerik.camera2/takePicture/$id")
                cameraProviderHolder.imageCapture.takePicture(pictureCallbackExecutor, object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(image: ImageProxy) {
                        if (call.argument<Boolean>("shutterSound")!!) {
                            MediaActionSound().play(MediaActionSound.SHUTTER_CLICK)
                        }
                        Handler(Looper.getMainLooper()).post {
                            result.success(null)
                        }
                        try {
                            val resultBytes = if (centerCropAspectRatio != null && centerCropWidthPercent != null) {
                                readImageCropped(
                                        image,
                                        previewAspectRatio = previewView.width.toDouble() / previewView.height.toDouble(),
                                        centerCropAspectRatio = centerCropAspectRatio,
                                        centerCropWidthPercent = centerCropWidthPercent,
                                        quality = call.argument<Int>("jpegQuality")!!
                                )
                            } else {
                                readImageNonCropped(image)
                            }
                            Handler(Looper.getMainLooper()).post {
                                pictureBytesChannel.invokeMethod("result", resultBytes)
                                if (shouldFreezePreview) {
                                    unfreezePreview()
                                }
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                pictureBytesChannel.invokeMethod("error", e.localizedMessage)
                                if (shouldFreezePreview) {
                                    unfreezePreview()
                                }
                            }
                        }
                        image.close()
                    }

                    override fun onError(exception: ImageCaptureException) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("", exception.localizedMessage, exception.toString())
                            if (shouldFreezePreview) {
                                unfreezePreview()
                            }
                        }
                    }
                })
            }
            "requestImageForAnalysis" -> result.success(cameraProviderHolder.analysisFrame)
            else -> result.notImplemented()
        }
    }

}

private fun readImageCropped(
        image: ImageProxy,
        previewAspectRatio: Double,
        centerCropAspectRatio: Double,
        centerCropWidthPercent: Double,
        quality: Int
): ByteArray {
    lateinit var resultBytes: ByteArray
    val buffer = image.planes[0].buffer
    buffer.rewind()
    ByteArrayOutputStream().use {
        while (buffer.hasRemaining()) {
            it.write(buffer.get().toInt())
        }
        resultBytes = it.toByteArray()
    }
    val bitmap = BitmapFactory.decodeByteArray(resultBytes, 0, resultBytes.size)
    val src = bakeExifOrientation(bitmap, image.imageInfo.rotationDegrees)

    val srcAspectRatio = src.width.toDouble() / src.height.toDouble()

    val previewSrcRatio = previewAspectRatio / srcAspectRatio
    val adjustedSrcWidth = src.width * previewSrcRatio
    val extraWidth = max(0.0, src.width - adjustedSrcWidth)

    val w = (src.width - extraWidth) * centerCropWidthPercent
    val h = w / centerCropAspectRatio

    val srcX = src.width / 2.0 - w / 2.0
    val srcY = src.height / 2.0 - h / 2.0
    val croppedBitmap = Bitmap.createBitmap(src, srcX.toInt(), srcY.toInt(), w.toInt(), h.toInt())
    src.recycle()

    ByteArrayOutputStream().use { stream ->
        croppedBitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        resultBytes = stream.toByteArray()
    }
    croppedBitmap.recycle()

    return resultBytes
}

private fun readImageNonCropped(
        image: ImageProxy
): ByteArray {
    val buffer = image.planes[0].buffer
    buffer.rewind()
    return ByteArrayOutputStream().use {
        while (buffer.hasRemaining()) {
            it.write(buffer.get().toInt())
        }
        it.toByteArray()
    }
}

private fun bakeExifOrientation(bitmap: Bitmap, rotationDegrees: Int): Bitmap {
    if (rotationDegrees == 0) {
        return bitmap
    }
    val matrix = Matrix()
    matrix.postRotate(rotationDegrees.toFloat())
    val result = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width,
            bitmap.height, matrix, true)
    bitmap.recycle()
    return result
}