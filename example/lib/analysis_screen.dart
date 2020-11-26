import 'dart:async';
import 'dart:typed_data';

import 'package:camera2/camera2.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:permission_handler/permission_handler.dart';

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({Key key}) : super(key: key);

  static const path = '/analysis_screen';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    Key key,
  }) : super(key: key);

  @override
  __BodyState createState() => __BodyState();
}

class __BodyState extends State<_Body> {
  CameraPreviewController _ctrl;

  var _hasPermission = false;

  final _convertedAnalysisImageBytes = StreamController<Uint8List>();

  static const _centerCropAspectRatio = 16.0 / 10.0;
  static const _centerCropWidthPercent = 0.8;

  @override
  void initState() {
    super.initState();
    _runAnalysisSimulation();
  }

  @override
  void dispose() {
    _convertedAnalysisImageBytes.close();
    super.dispose();
  }

  Future<void> _runAnalysisSimulation() async {
    final permissionStatus = await Permission.camera.request();
    if (permissionStatus == PermissionStatus.granted) {
      _hasPermission = true;
      if (mounted) {
        setState(() {});
      }
    }

    while (mounted) {
      if (_ctrl == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      final imageBytes = await _ctrl.requestImageForAnalysis();
      if (imageBytes != null) {
        final img = image.Image(224, 224);
        final pixelsAmount = imageBytes.lengthInBytes ~/ 3;

        var i = 0;
        var j = 0;
        while (j < pixelsAmount) {
          img.setPixel(
            j % 224,
            j ~/ 224,
            Color.fromARGB(
              255,
              imageBytes[i],
              imageBytes[i + 1],
              imageBytes[i + 2],
            ).value,
          );
          i += 3;
          j++;
        }
        if (!_convertedAnalysisImageBytes.isClosed) {
          _convertedAnalysisImageBytes.add(
            Uint8List.fromList(image.encodePng(img)),
          );
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 14));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Analysis image'),
          Container(
            height: 200,
            alignment: Alignment.topCenter,
            child: StreamBuilder<Uint8List>(
              stream: _convertedAnalysisImageBytes.stream,
              builder: (context, snapshot) => snapshot.hasData
                  ? Image.memory(
                      snapshot.data,
                      gaplessPlayback: true,
                      isAntiAlias: true,
                      fit: BoxFit.contain,
                    )
                  : Container(),
            ),
          ),
          const Text('Camera preview'),
          Expanded(
            child: _hasPermission ? _buildPreview() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      children: [
        Positioned.fill(
          child: Camera2Preview(
            analysisOptions: const Camera2AnalysisOptions(
              imageSize:
                  Size(224, 224), // ignore: avoid_redundant_argument_values
              colorOrder:
                  ColorOrder.rgb, // ignore: avoid_redundant_argument_values
              normalization: Normalization.ubyte,
              centerCropWidthPercent: _centerCropWidthPercent,
              centerCropAspectRatio: _centerCropAspectRatio,
            ),
            onPlatformViewCreated: (ctrl) => _ctrl = ctrl,
          ),
        ),
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * _centerCropWidthPercent,
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
    );
  }
}
