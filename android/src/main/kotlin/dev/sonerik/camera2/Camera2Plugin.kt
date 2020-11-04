package dev.sonerik.camera2

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.*
import android.graphics.drawable.BitmapDrawable
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
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.concurrent.Executor
import java.util.concurrent.ScheduledThreadPoolExecutor
import kotlin.math.min

/** Camera2Plugin */
class Camera2Plugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel

    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

    private lateinit var mainExecutor: Executor
    private lateinit var pictureCallbackExecutor: Executor

    private val cameraProviderHolder = CameraProviderHolder()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.sonerik.camera2").apply {
            setMethodCallHandler(this@Camera2Plugin)
        }
        mainExecutor = ContextCompat.getMainExecutor(flutterPluginBinding.applicationContext)
        pictureCallbackExecutor = ScheduledThreadPoolExecutor(1)
        flutterPluginBinding.platformViewRegistry
                .registerViewFactory(
                        "cameraPreview",
                        CameraPreviewFactory(
                                messenger = flutterPluginBinding.binaryMessenger,
                                pictureCallbackExecutor = pictureCallbackExecutor,
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

private class CameraPreviewFactory(
        private val messenger: BinaryMessenger,
        private val pictureCallbackExecutor: Executor,
        private val cameraProviderHolder: CameraProviderHolder
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val view = CameraPreviewView(
                id = viewId,
                context = context,
                messenger = messenger,
                pictureCallbackExecutor = pictureCallbackExecutor,
                imageCapture = cameraProviderHolder.imageCapture,
                onDispose = { cameraProviderHolder.onPreviewDisposed(viewId) }
        )
        cameraProviderHolder.onPreviewCreated(context, viewId, view)
        return view
    }
}

private class CameraProviderHolder {
    var lifecycleOwner: LifecycleOwner? = null

    private var cameraProviderFuture: ListenableFuture<ProcessCameraProvider>? = null
    private val activePreviews = mutableMapOf<Int, CameraPreviewView>()

    private val cameraProvider
        get() = cameraProviderFuture?.get()

    val imagePreview = Preview.Builder()
            .build()

    val imageAnalysis = ImageAnalysis.Builder()
            .build()

    val imageCapture = ImageCapture.Builder()
            .setFlashMode(ImageCapture.FLASH_MODE_AUTO)
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .setTargetResolution(Size(720, 1280))
            .build()

    private val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_BACK)
            .build()

    private lateinit var mainExecutor: Executor

    fun onPreviewCreated(context: Context, viewId: Int, previewView: CameraPreviewView) {
        mainExecutor = ContextCompat.getMainExecutor(context)
        if (cameraProviderFuture == null) {
            cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        }
        if (activePreviews.isEmpty()) {
            withCameraProvider { cameraProvider ->
                cameraProvider?.bindToLifecycle(lifecycleOwner!!, cameraSelector, imageCapture, imagePreview)
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
        private val messenger: BinaryMessenger,
        id: Int,
        private val pictureCallbackExecutor: Executor,
        private val imageCapture: ImageCapture,
        private val onDispose: () -> Unit
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
        onDispose()
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

                val pictureBytesChannel = MethodChannel(messenger, "dev.sonerik.camera2/takePicture/$id")
                imageCapture.takePicture(pictureCallbackExecutor, object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(image: ImageProxy) {
                        Handler(Looper.getMainLooper()).post {
                            result.success(null)
                        }
                        try {
                            lateinit var resultBytes: ByteArray
                            val buffer = image.planes[0].buffer
                            buffer.rewind()
                            ByteArrayOutputStream().use {
                                while (buffer.hasRemaining()) {
                                    it.write(buffer.get().toInt())
                                }
                                resultBytes = it.toByteArray()
                            }
                            if (centerCropAspectRatio != null && centerCropWidthPercent != null) {
//                                val bitmap = decodeByteArray(resultBytes, image.width, image.height)
                                val bitmap = BitmapFactory.decodeByteArray(resultBytes, 0, resultBytes.size)
                                val rotatedBitmap = bakeExifOrientation(bitmap, image.imageInfo.rotationDegrees)

                                val width = rotatedBitmap.width * centerCropWidthPercent
                                val height = width / centerCropAspectRatio

                                val croppedBitmap = centerCrop(rotatedBitmap, width.toInt(), height.toInt())

                                ByteArrayOutputStream().use { stream ->
                                    croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
                                    resultBytes = stream.toByteArray()
                                }
                                bitmap.recycle()
                                rotatedBitmap.recycle()
                                croppedBitmap.recycle()
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
        }
    }

}

private fun decodeByteArray(src: ByteArray, w: Int, h: Int): Bitmap {
    // calculate sample size based on w/h
    // calculate sample size based on w/h
    val opts: BitmapFactory.Options = BitmapFactory.Options()
    opts.inJustDecodeBounds = true
    BitmapFactory.decodeByteArray(src, 0, src.size, opts)
    if (opts.mCancel || opts.outWidth == -1 || opts.outHeight == -1) {
        throw IllegalStateException()
    }
    opts.inSampleSize = min(opts.outWidth / w, opts.outHeight / h)
    opts.inJustDecodeBounds = false
    return BitmapFactory.decodeByteArray(src, 0, src.size, opts)
}

private fun centerCrop(src: Bitmap, w: Int, h: Int): Bitmap {
    val srcX = src.width / 2 - w / 2
    val srcY = src.height / 2 - h / 2
    return Bitmap.createBitmap(src, srcX, srcY, w, h)
}

private fun bakeExifOrientation(bitmap: Bitmap, rotationDegrees: Int): Bitmap {
    if (rotationDegrees == 0) {
        return bitmap
    }
    val matrix = Matrix()
    matrix.postRotate(rotationDegrees.toFloat())
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width,
            bitmap.height, matrix, true)
}