package dev.sonerik.camera2

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.NonNull
import androidx.camera.core.*
import androidx.camera.lifecycle.ExperimentalCameraProviderConfiguration
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
import java.lang.Exception
import java.util.concurrent.Executor
import java.util.concurrent.ScheduledThreadPoolExecutor

/** Camera2Plugin */
class Camera2Plugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel

    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

    private lateinit var mainExecutor: Executor
    private lateinit var pictureCallbackExecutor: Executor

    @ExperimentalCameraProviderConfiguration
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.sonerik.camera2").apply {
            setMethodCallHandler(this@Camera2Plugin)
        }
        mainExecutor = ContextCompat.getMainExecutor(flutterPluginBinding.applicationContext)
        pictureCallbackExecutor = ScheduledThreadPoolExecutor(1)
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
            "takePicture" -> {
                ImageCapture.Builder()
                        .setFlashMode(ImageCapture.FLASH_MODE_AUTO)
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .build()
                        .takePicture(pictureCallbackExecutor, object : ImageCapture.OnImageCapturedCallback() {
                            override fun onCaptureSuccess(image: ImageProxy) {
                                super.onCaptureSuccess(image)
                                val buffer = image.planes[0].buffer
                                buffer.rewind()
                                val bytes = ByteArray(buffer.capacity())
                                buffer.get(bytes)
                                val decodedBitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                val os = ByteArrayOutputStream()
                                decodedBitmap.compress(Bitmap.CompressFormat.PNG, 100, os)
                                result.success(os.toByteArray())
                            }

                            override fun onError(exception: ImageCaptureException) {
                                super.onError(exception)
                            }
                        })
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
                "cameraPreview",
                CameraPreviewFactory(
                        flutterPluginBinding.binaryMessenger,
                        binding.activity as LifecycleOwner,
                        pictureCallbackExecutor
                )
        )
    }

    override fun onDetachedFromActivityForConfigChanges() {
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    }

    override fun onDetachedFromActivity() {
    }
}

private class CameraPreviewFactory(
        private val messenger: BinaryMessenger,
        private val lifecycleOwner: LifecycleOwner,
        private val pictureCallbackExecutor: Executor
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return CameraPreview(context, messenger, lifecycleOwner, viewId, pictureCallbackExecutor)
    }
}

private class CameraPreview(
        context: Context,
        private val messenger: BinaryMessenger,
        private val lifecycleOwner: LifecycleOwner,
        id: Int,
        private val pictureCallbackExecutor: Executor
) : PlatformView, MethodCallHandler {
    private lateinit var cameraProvider: ProcessCameraProvider

    private val previewView = PreviewView(context)
    private val cameraShotOverlayView = View(context).apply { visibility = View.INVISIBLE }
    private val view = FrameLayout(context).apply {
        addView(previewView)
        addView(cameraShotOverlayView)
    }
    private val resources = context.resources

    private val channel = MethodChannel(messenger, "dev.sonerik.camera2/preview_$id")
            .apply { setMethodCallHandler(this@CameraPreview) }

    private val imagePreview = Preview.Builder()
            .build()
            .apply { setSurfaceProvider(previewView.surfaceProvider) }

    private val imageAnalysis = ImageAnalysis.Builder()
            .build()

    private val imageCapture = ImageCapture.Builder()
            .setFlashMode(ImageCapture.FLASH_MODE_AUTO)
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()

    private val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_BACK)
            .build()

    init {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        ProcessCameraProvider.getInstance(context).addListener(Runnable {
            cameraProvider = cameraProviderFuture.get()
            cameraProvider.bindToLifecycle(lifecycleOwner, cameraSelector, imageCapture, imagePreview)
        }, ContextCompat.getMainExecutor(context))
    }

    private fun freezePreview() {
        cameraShotOverlayView.background = BitmapDrawable(resources, previewView.bitmap)
        cameraShotOverlayView.visibility = View.VISIBLE
    }

    private fun unfreezePreview() {
        cameraShotOverlayView.visibility = View.INVISIBLE
    }

    override fun getView() = view

    override fun dispose() {
        cameraProvider.unbindAll()
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
                            Handler(Looper.getMainLooper()).post {
                                pictureBytesChannel.invokeMethod("result", resultBytes)
                                if (shouldFreezePreview) {
                                    unfreezePreview()
                                }
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                pictureBytesChannel.invokeMethod("error", e.localizedMessage)
                            }
                        }
                        image.close()
                    }

                    override fun onError(exception: ImageCaptureException) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("", exception.localizedMessage, exception.toString())
                        }
                    }
                })
            }
        }
    }

}