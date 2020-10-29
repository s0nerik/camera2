import 'package:flutter/services.dart';

class Camera2 {
  static const MethodChannel _channel =
      const MethodChannel('dev.sonerik.camera2');

  static Future<bool> get hasCameraPermission async =>
      _channel.invokeMethod<bool>('hasCameraPermission');
}
