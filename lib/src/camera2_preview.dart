import 'dart:async';
import 'dart:typed_data';

import 'package:camera2/camera2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    this.onPhotoCaptured,
    this.onPhotoRead,
  )   : assert(viewId != null),
        assert(onPhotoCaptured != null),
        assert(onPhotoRead != null),
        _channel = MethodChannel('dev.sonerik.camera2/preview_$viewId');

  final int viewId;
  final VoidCallback onPhotoCaptured;
  final VoidCallback onPhotoRead;
  final MethodChannel _channel;

  Future<TakePictureResult> takePicture({bool freezePreview = true}) async {
    assert(freezePreview != null);

    final id = DateTime.now().microsecondsSinceEpoch;
    await _channel.invokeMethod<Uint8List>('takePicture', {
      'id': id,
      'freezePreview': freezePreview,
    });
    onPhotoCaptured();
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
      onPhotoRead();
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
  final _key = GlobalKey();

  Uint8List _placeholderImage;

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
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            key: _key,
            child: _PlatformPreview(
              onPlatformViewCreated: widget.onPlatformViewCreated,
              onPhotoCaptured: _displayPlaceholder,
              onPhotoRead: _hidePlaceholder,
            ),
          ),
        ),
        if (_placeholderImage != null)
          Container(
            color: Colors.yellow,
          ),
        if (_placeholderImage != null)
          Positioned.fill(
            child: Image.memory(
              _placeholderImage,
              width: MediaQuery.of(context).size.width,
            ),
          ),
      ],
    );
  }

  Future<void> _displayPlaceholder() async {
    // debugPrint('_displayPlaceholder START: ${DateTime.now()}');
    // final RenderRepaintBoundary boundary =
    //     _key.currentContext.findRenderObject();
    // final image = await boundary.toImage();
    // final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    // // final byteData = await image.toByteData();
    // final bytes = Uint8List.fromList(byteData.buffer.asUint8List());
    // debugPrint('_displayPlaceholder END: ${DateTime.now()}');
    // _placeholderImage = bytes;
    // if (mounted) {
    //   setState(() {});
    // }
  }

  void _hidePlaceholder() {
    // _placeholderImage = null;
    // if (mounted) {
    //   setState(() {});
    // }
  }

  // Future<void> _capturePng() async {
  //   final RenderRepaintBoundary boundary =
  //       _key.currentContext.findRenderObject();
  //   ui.Image image = await boundary.toImage();
  //   ByteData byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  //   Uint8List pngBytes = byteData.buffer.asUint8List();
  //   print(pngBytes);
  // }
}

class _PlatformPreview extends StatelessWidget {
  const _PlatformPreview({
    Key key,
    @required this.onPlatformViewCreated,
    @required this.onPhotoCaptured,
    @required this.onPhotoRead,
  }) : super(key: key);

  final PlatformViewCreatedCallback onPlatformViewCreated;
  final VoidCallback onPhotoCaptured;
  final VoidCallback onPhotoRead;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'cameraPreview',
        onPlatformViewCreated: (id) {
          final ctrl =
              CameraPreviewController._(id, onPhotoCaptured, onPhotoRead);
          onPlatformViewCreated?.call(ctrl);
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
