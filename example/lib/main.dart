import 'dart:typed_data';

import 'package:camera2/camera2.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  const App({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _hasCameraPermission = false;

  CameraPreviewController _ctrl;
  bool _tookPicture = false;

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
              child: Text('PHOTO'),
            ),
          ),
          Positioned(
            bottom: 128,
            left: 0,
            right: 0,
            child: RaisedButton(
              onPressed: () {},
              child: Text('TEST'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _takePicture() async {
    setState(() => _tookPicture = false);
    final result = await _ctrl.takePicture();
    setState(() => _tookPicture = true);
    if (result != null) {
      final imageBytes = await result.picture;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => PreviewScreen(photoBytes: imageBytes),
      ));
    }
    setState(() => _tookPicture = false);
  }
}

class PreviewScreen extends StatelessWidget {
  const PreviewScreen({
    Key key,
    @required this.photoBytes,
  }) : super(key: key);

  final Uint8List photoBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo'),
      ),
      body: GestureDetector(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => CameraScreen(),
          ));
        },
        child: Image.memory(photoBytes),
      ),
    );
  }
}
