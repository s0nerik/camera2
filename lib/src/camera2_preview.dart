import 'dart:async';
import 'dart:typed_data';

import 'package:camera2/camera2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum FlashType { auto, on, off }

extension _FlashTypeStr on FlashType {
  String asString() {
    switch (this) {
      case FlashType.auto:
        return 'auto';
      case FlashType.on:
        return 'on';
      case FlashType.off:
        return 'off';
    }
    return 'auto';
  }
}

@immutable
class TakePictureResult {
  TakePictureResult._(this.picture);

  final Future<Uint8List> picture;
}

class CameraPreviewController {
  CameraPreviewController._(
    this.viewId,
  )   : assert(viewId != null),
        _channel = MethodChannel('dev.sonerik.camera2/preview_$viewId');

  final int viewId;
  final MethodChannel _channel;

  Completer<void> _takePictureCompleter = Completer()..complete();

  /// Make a shot.
  ///
  /// Returns [TakePictureResult] after the photo is taken (or null if photo
  /// wasn't taken at all). To get the actual photo bytes - wait for
  /// [TakePictureResult.picture].
  ///
  /// Parameters:
  ///
  /// [freezePreview] - whether the preview should be paused until photo bytes
  /// are read. Default value is `true`.
  ///
  /// [force] - whether to allow taking shots in parallel. If `false` - only
  /// the first call of the quick succession would resolve to a result, all
  /// other requests would resolve to null.
  /// USE WITH CAUTION! Requesting too many photos simultaneously would lead to
  /// errors on native side.
  /// Default value is `false`.
  ///
  /// [flash] - camera flashlight mode. Default: [FlashType.auto].
  ///
  /// [croppedJpegQuality] - Cropped photo JPEG compression quality. Non-cropped
  /// photos are returned in the same quality they were shot.
  /// Default: 80.
  ///
  /// [centerCropAspectRatio] - aspect ratio of rect cropped in the middle.
  /// Optional. Must not be null if [centerCropWidthPercent] is not null.
  ///
  /// [centerCropWidthPercent] - amount of cropped area width in percents.
  /// Optional. Must not be null if [centerCropAspectRatio] is not null.
  Future<TakePictureResult> takePicture({
    bool freezePreview = true,
    bool force = false,
    FlashType flash = FlashType.auto,
    int croppedJpegQuality = 80,
    double centerCropAspectRatio,
    double centerCropWidthPercent,
  }) async {
    assert(freezePreview != null);
    assert(force != null);
    assert(flash != null);
    assert(croppedJpegQuality > 0 && croppedJpegQuality <= 100);
    assert(centerCropAspectRatio != null && centerCropWidthPercent != null ||
        centerCropAspectRatio == null && centerCropWidthPercent == null);
    assert(centerCropWidthPercent == null ||
        centerCropWidthPercent >= 0 && centerCropWidthPercent <= 1);

    if (force || _takePictureCompleter.isCompleted) {
      // Can take a new shot
      _takePictureCompleter = Completer();
    } else {
      // Camera is busy
      return null;
    }

    try {
      final id = DateTime.now().microsecondsSinceEpoch;
      await _channel.invokeMethod<Uint8List>('takePicture', {
        'id': id,
        'freezePreview': freezePreview,
        'flash': flash.asString(),
        'jpegQuality': croppedJpegQuality,
        if (centerCropAspectRatio != null)
          'centerCropAspectRatio': centerCropAspectRatio,
        if (centerCropWidthPercent != null)
          'centerCropWidthPercent': centerCropWidthPercent,
      });
      final pictureCompleter = Completer<Uint8List>();
      final pictureBytesChannel =
          MethodChannel('dev.sonerik.camera2/takePicture/$id');
      pictureBytesChannel.setMethodCallHandler((call) async {
        pictureBytesChannel.setMethodCallHandler(null);
        switch (call.method) {
          case 'result':
            final Uint8List photoBytes = call.arguments;
            pictureCompleter.complete(photoBytes);
            _takePictureCompleter.complete();
            break;
          case 'error':
            final String error = call.arguments;
            pictureCompleter.completeError(Exception(error));
            _takePictureCompleter.complete();
            break;
          default:
            pictureCompleter.completeError(UnsupportedError(call.method));
            _takePictureCompleter.complete();
        }
      });
      return TakePictureResult._(pictureCompleter.future);
    } catch (_) {
      _takePictureCompleter.complete();
      rethrow;
    }
  }
}

typedef PlatformViewCreatedCallback = void Function(
  CameraPreviewController controller,
);

class Camera2Preview extends StatefulWidget {
  const Camera2Preview({
    Key key,
    this.onPlatformViewCreated,
    this.preferredPhotoSize,
  }) : super(key: key);

  final PlatformViewCreatedCallback onPlatformViewCreated;

  /// Preferred size of the resulting photo. Real photo can have different
  /// dimensions. To crop the resulting photo - use
  /// [CameraPreviewController.centerCropAspectRatio] and
  /// [CameraPreviewController.centerCropWidthPercent] combination.
  final Size preferredPhotoSize;

  @override
  _Camera2PreviewState createState() => _Camera2PreviewState();
}

class _Camera2PreviewState extends State<Camera2Preview> {
  @override
  void initState() {
    super.initState();
    _assertHasCameraPermission();
  }

  Future<void> _assertHasCameraPermission() async {
    final hasCameraPermission = await Camera2.hasCameraPermission;
    assert(hasCameraPermission,
        'Camera2Preview can only be used when camera permission is granted');
  }

  @override
  Widget build(BuildContext context) {
    final args = <String, dynamic>{
      if (widget.preferredPhotoSize != null)
        'preferredPhotoWidth': widget.preferredPhotoSize.width.toInt(),
      if (widget.preferredPhotoSize != null)
        'preferredPhotoHeight': widget.preferredPhotoSize.height.toInt(),
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'cameraPreview',
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: args,
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'cameraPreview',
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: args,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    return new Text(
        '$defaultTargetPlatform is not yet supported by this plugin');
  }

  void _onPlatformViewCreated(int id) {
    final ctrl = CameraPreviewController._(id);
    widget.onPlatformViewCreated?.call(ctrl);
  }
}
