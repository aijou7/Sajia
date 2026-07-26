import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class BluetoothSystem {
  static const MethodChannel _channel = MethodChannel('sajia/system');

  static Future<void> requestBluetoothPermissions() async {
    if (!Platform.isAndroid) return;

    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
  }

  static Future<bool> ensureBluetoothReady(
      {bool openPanelIfDisabled = true}) async {
    await requestBluetoothPermissions();

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (enabled) return true;

    if (!openPanelIfDisabled) return false;

    await openBluetoothPanel();
    await Future.delayed(const Duration(milliseconds: 500));
    return PrintBluetoothThermal.bluetoothEnabled;
  }

  static Future<void> openBluetoothPanel() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod<void>('openBluetoothPanel');
    } on PlatformException {
      await openAppSettings();
    }
  }

  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.notification.request();
    return status.isGranted || status.isLimited;
  }
}
