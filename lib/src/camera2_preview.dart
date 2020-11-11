import 'dart:async';
import 'dart:typed_data';

import 'package:camera2/camera2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pedantic/pedantic.dart';

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
  const TakePictureResult._(this.picture);

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

  Completer<Uint8List> _requestImageForAnalysisCompleter;

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
  /// [shutterSound] - whether to play shutter sound. Default: true.
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
    bool shutterSound = true,
    double centerCropAspectRatio,
    double centerCropWidthPercent,
  }) async {
    assert(freezePreview != null);
    assert(force != null);
    assert(flash != null);
    assert(croppedJpegQuality > 0 && croppedJpegQuality <= 100);
    assert(shutterSound != null);
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
        'shutterSound': shutterSound,
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
            final photoBytes = call.arguments as Uint8List;
            pictureCompleter.complete(photoBytes);
            _takePictureCompleter.complete();
            break;
          case 'error':
            final error = call.arguments as String;
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

  Future<Uint8List> requestImageForAnalysis() async {
    if (_requestImageForAnalysisCompleter == null ||
        _requestImageForAnalysisCompleter.isCompleted) {
      _requestImageForAnalysisCompleter = Completer();
      unawaited(
        _channel.invokeMethod<Uint8List>('requestImageForAnalysis').then(
              _requestImageForAnalysisCompleter.complete,
              onError: _requestImageForAnalysisCompleter.completeError,
            ),
      );
    }
    return _requestImageForAnalysisCompleter.future;
  }
}

typedef PlatformViewCreatedCallback = void Function(
  CameraPreviewController controller,
);

typedef ImageCallback = void Function(Uint8List imageBytes);

@immutable
class Camera2AnalysisOptions {
  const Camera2AnalysisOptions({
    this.imageSize = const Size(224, 224),
    this.colorOrder = ColorOrder.rgb,
    this.normalization = Normalization.byte,
  })  : assert(imageSize != null),
        assert(colorOrder != null),
        assert(normalization != null);

  /// Size of the images acquired with
  /// [CameraPreviewController.requestImageForAnalysis].
  final Size imageSize;

  /// Order of colors in the byte array acquired with
  /// [CameraPreviewController.requestImageForAnalysis].
  final ColorOrder colorOrder;

  /// Normalization type for colors in the byte array acquired with
  /// [CameraPreviewController.requestImageForAnalysis].
  final Normalization normalization;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'imageWidth': imageSize.width.toInt(),
      'imageHeight': imageSize.height.toInt(),
      'colorOrder': colorOrder.asString(),
      'normalization': normalization.asString(),
    };
  }
}

enum ColorOrder { rgb, rbg, grb, gbr, brg, bgr }

extension _ColorOrderStr on ColorOrder {
  String asString() {
    switch (this) {
      case ColorOrder.rgb:
        return 'rgb';
      case ColorOrder.rbg:
        return 'rbg';
      case ColorOrder.grb:
        return 'grb';
      case ColorOrder.gbr:
        return 'gbr';
      case ColorOrder.brg:
        return 'brg';
      case ColorOrder.bgr:
        return 'bgr';
    }
    return 'rgb';
  }
}

enum Normalization {
  /// Range: [0, 255]
  ubyte,

  /// Range: [-127, 127]
  byte,

  /// Range: [0.0, 1.0]
  ufloat,

  /// Range: [-1.0, 1.0]
  float,
}

extension _NormalizationStr on Normalization {
  String asString() {
    switch (this) {
      case Normalization.ubyte:
        return 'ubyte';
      case Normalization.byte:
        return 'byte';
      case Normalization.ufloat:
        return 'ufloat';
      case Normalization.float:
        return 'float';
    }
    return 'byte';
  }
}

class Camera2Preview extends StatefulWidget {
  const Camera2Preview({
    Key key,
    this.onPlatformViewCreated,
    this.preferredPhotoSize,
    this.analysisOptions,
  }) : super(key: key);

  final PlatformViewCreatedCallback onPlatformViewCreated;

  /// Preferred size of the resulting photo. Real photo can have different
  /// dimensions. To crop the resulting photo - use
  /// [CameraPreviewController.takePicture]'s `centerCropAspectRatio` and
  /// `centerCropWidthPercent` combination.
  final Size preferredPhotoSize;

  final Camera2AnalysisOptions analysisOptions;

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
      if (widget.analysisOptions != null)
        'analysisOptions': widget.analysisOptions.toMap(),
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

    return Text('$defaultTargetPlatform is not yet supported by this plugin');
  }

  void _onPlatformViewCreated(int id) {
    final ctrl = CameraPreviewController._(id);
    widget.onPlatformViewCreated?.call(ctrl);
  }
}
