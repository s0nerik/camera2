import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera2/camera2.dart';
import 'package:camera2_example/analysis_screen.dart';
import 'package:flutter/material.dart';
import 'package:pedantic/pedantic.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: StartScreen(),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test app'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaisedButton(
            onPressed: () {
              Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (context) => const CameraScreen(),
              ));
            },
            child: const Text('Photo'),
          ),
          RaisedButton(
            onPressed: () {
              Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (context) => const AnalysisScreen(),
              ));
            },
            child: const Text('Image analysis'),
          ),
        ],
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    Key key,
  }) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  var _hasCameraPermission = false;
  var _flashType = FlashType.auto;

  CameraPreviewController _ctrl;
  bool _tookPicture = false;

  static const _centerCropAspectRatio = 16 / 9;
  static const _centerCropWidthPercent = 0.8;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      _hasCameraPermission = status == PermissionStatus.granted;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin example app'),
      ),
      body: Stack(
        children: [
          if (_hasCameraPermission)
            Camera2Preview(
              preferredPhotoSize: const Size(720, 1280),
              onPlatformViewCreated: (ctrl) => _ctrl = ctrl,
            ),
          Positioned(
            right: 0,
            top: 0,
            width: 56,
            height: 56,
            child: Container(
              color: _tookPicture ? Colors.green : Colors.grey,
            ),
          ),
          Positioned(
            bottom: 64,
            left: 0,
            right: 0,
            child: RaisedButton(
              onPressed: _takePicture,
              child: const Text('PHOTO'),
            ),
          ),
          Positioned(
            bottom: 128,
            left: 0,
            right: 0,
            child: RaisedButton(
              onPressed: () {},
              child: const Text('TEST'),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: RaisedButton(
              onPressed: () {
                setState(() {
                  if (_flashType == FlashType.auto) {
                    _flashType = FlashType.off;
                  } else if (_flashType == FlashType.off) {
                    _flashType = FlashType.on;
                  } else if (_flashType == FlashType.on) {
                    _flashType = FlashType.auto;
                  }
                });
              },
              child: Text('$_flashType'),
            ),
          ),
          Center(
            child: SizedBox(
              width:
                  MediaQuery.of(context).size.width * _centerCropWidthPercent,
              child: AspectRatio(
                aspectRatio: _centerCropAspectRatio,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _takePicture() async {
    setState(() => _tookPicture = false);
    final result = await _ctrl.takePicture(
      centerCropAspectRatio: _centerCropAspectRatio,
      centerCropWidthPercent: _centerCropWidthPercent,
      flash: _flashType,
      croppedJpegQuality: 100,
    );
    setState(() => _tookPicture = true);
    if (result != null) {
      unawaited(
        Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (context) => PreviewScreen(photoBytes: result.picture),
        )),
      );
    }
    setState(() => _tookPicture = false);
  }
}

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    Key key,
    @required this.photoBytes,
  }) : super(key: key);

  final Future<Uint8List> photoBytes;

  @override
  _PreviewScreenState createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String _resolution = '';

  @override
  void initState() {
    super.initState();
    _getResolution(widget.photoBytes);
  }

  Future<void> _getResolution(Future<Uint8List> bytesFuture) async {
    final bytes = await bytesFuture;
    final image = Image.memory(bytes);
    final completer = Completer<ui.Image>();
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        completer.complete(info.image);
      }),
    );
    final img = await completer.future;
    _resolution = '${img.width}x${img.height}';
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo'),
      ),
      body: GestureDetector(
        onTap: () {
          Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (context) => const CameraScreen(),
          ));
        },
        child: FutureBuilder<Uint8List>(
            future: widget.photoBytes,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Container();
              }
              return Column(
                children: [
                  Text(_resolution),
                  Image(
                    image: MemoryImage(snapshot.data),
                    gaplessPlayback: true,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              );
            }),
      ),
    );
  }
}
