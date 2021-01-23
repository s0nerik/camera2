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
  static const _biggerCenterCropAspectRatio = 16.0 / 10.0;
  static const _biggerCenterCropWidthPercent = 1.0;

  static const _smallerCenterCropAspectRatio = 16.0 / 10.0;
  static const _smallerCenterCropWidthPercent = 0.8;

  static const _analysisOptions = <String, Camera2AnalysisOptions>{
    'bigger': Camera2AnalysisOptions(
      imageSize: Size(192, 192), // ignore: avoid_redundant_argument_values
      colorOrder: ColorOrder.rgb, // ignore: avoid_redundant_argument_values
      normalization: Normalization.ubyte,
      centerCropWidthPercent: _biggerCenterCropWidthPercent,
      centerCropAspectRatio: _biggerCenterCropAspectRatio,
    ),
    'smaller': Camera2AnalysisOptions(
      imageSize: Size(224, 224), // ignore: avoid_redundant_argument_values
      colorOrder: ColorOrder.rgb, // ignore: avoid_redundant_argument_values
      normalization: Normalization.ubyte,
      centerCropWidthPercent: _smallerCenterCropWidthPercent,
      centerCropAspectRatio: _smallerCenterCropAspectRatio,
    ),
  };

  CameraPreviewController _ctrl;

  var _hasPermission = false;

  final _biggerPreviewImage = image.Image(
    _analysisOptions['bigger'].imageSize.width.toInt(),
    _analysisOptions['bigger'].imageSize.height.toInt(),
  );
  final _biggerConvertedAnalysisImageBytes = StreamController<Uint8List>();

  final _smallerPreviewImage = image.Image(
    _analysisOptions['smaller'].imageSize.width.toInt(),
    _analysisOptions['smaller'].imageSize.height.toInt(),
  );
  final _smallerConvertedAnalysisImageBytes = StreamController<Uint8List>();

  @override
  void initState() {
    super.initState();
    _runAnalysisSimulation();
  }

  @override
  void dispose() {
    _biggerConvertedAnalysisImageBytes.close();
    _smallerConvertedAnalysisImageBytes.close();
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

      final smallerBytes =
          await _ctrl.requestImageForAnalysis(analysisOptionsId: 'smaller');
      final biggerBytes =
          await _ctrl.requestImageForAnalysis(analysisOptionsId: 'bigger');
      _writePreviewImage(
        smallerBytes,
        _smallerPreviewImage,
        _smallerConvertedAnalysisImageBytes,
      );
      _writePreviewImage(
        biggerBytes,
        _biggerPreviewImage,
        _biggerConvertedAnalysisImageBytes,
      );

      await Future<void>.delayed(const Duration(milliseconds: 16));
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
          Row(
            children: [
              Container(
                height: _analysisOptions['bigger'].imageSize.height,
                alignment: Alignment.topLeft,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red),
                ),
                child: StreamBuilder<Uint8List>(
                  stream: _biggerConvertedAnalysisImageBytes.stream,
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
              const Spacer(),
              Container(
                height: _analysisOptions['smaller'].imageSize.height,
                alignment: Alignment.topRight,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green),
                ),
                child: StreamBuilder<Uint8List>(
                  stream: _smallerConvertedAnalysisImageBytes.stream,
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
            ],
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
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Camera2Preview(
            analysisOptions: _analysisOptions,
            onPlatformViewCreated: (ctrl) => _ctrl = ctrl,
          ),
        ),
        SizedBox(
          width:
              MediaQuery.of(context).size.width * _biggerCenterCropWidthPercent,
          child: AspectRatio(
            aspectRatio: _biggerCenterCropAspectRatio,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red),
              ),
            ),
          ),
        ),
        SizedBox(
          width: MediaQuery.of(context).size.width *
              _smallerCenterCropWidthPercent,
          child: AspectRatio(
            aspectRatio: _smallerCenterCropAspectRatio,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void _writePreviewImage(
  Uint8List imageBytes,
  image.Image img,
  StreamController<Uint8List> convertedImgStreamCtrl,
) {
  if (imageBytes != null) {
    // for (var y = 0; y < img.height; y++) {
    //   for (var x = 0; x < img.width; x++) {
    //     final i = y * img.width + x;
    //     img.setPixelRgba(
    //       x,
    //       y,
    //       imageBytes[i],
    //       imageBytes[i + 1],
    //       imageBytes[i + 2],
    //     );
    //   }
    // }

    final pixelsAmount = imageBytes.lengthInBytes ~/ 3;
    var i = 0;
    var j = 0;
    while (j < pixelsAmount) {
      img.setPixelSafe(
        j % img.width,
        j ~/ img.height,
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
    if (!convertedImgStreamCtrl.isClosed) {
      convertedImgStreamCtrl.add(
        Uint8List.fromList(image.encodePng(img)),
      );
    }
  }
}
