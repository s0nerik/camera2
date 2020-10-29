import 'dart:async';
import 'dart:typed_data';

import 'package:camera2/camera2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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

  Future<TakePictureResult> takePicture({bool freezePreview = true}) async {
    assert(freezePreview != null);

    final id = DateTime.now().microsecondsSinceEpoch;
    await _channel.invokeMethod<Uint8List>('takePicture', {
      'id': id,
      'freezePreview': freezePreview,
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
          break;
        case 'error':
          final String error = call.arguments;
          pictureCompleter.completeError(Exception(error));
          break;
        default:
          pictureCompleter.completeError(UnsupportedError(call.method));
      }
    });
    return TakePictureResult._(pictureCompleter.future);
  }
}

typedef PlatformViewCreatedCallback = void Function(
  CameraPreviewController controller,
);

class Camera2Preview extends StatefulWidget {
  const Camera2Preview({
    Key key,
    this.onPlatformViewCreated,
  }) : super(key: key);

  final PlatformViewCreatedCallback onPlatformViewCreated;

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
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'cameraPreview',
        onPlatformViewCreated: (id) {
          final ctrl = CameraPreviewController._(id);
          widget.onPlatformViewCreated?.call(ctrl);
        },
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      throw UnimplementedError();
      return UiKitView();
    }

    return new Text(
        '$defaultTargetPlatform is not yet supported by this plugin');
  }
}
