import 'package:flutter/services.dart';

// ignore: avoid_classes_with_only_static_members
class Camera2 {
  static const _channel = MethodChannel('dev.sonerik.camera2');

  static Future<bool> get hasCameraPermission async =>
      _channel.invokeMethod<bool>('hasCameraPermission');
}
