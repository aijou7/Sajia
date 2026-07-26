import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static const _keyKitchenNotif = 'kitchen_notif';
  static const _keyKitchenDeviceName = 'kitchen_device_name';
  static const _keyKitchenDeviceAddress = 'kitchen_device_address';

  static Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('ic_stat_sajia');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final plugin = _plugin as dynamic;
    try {
      await plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (NotificationResponse details) {},
      );
    } on NoSuchMethodError {
      await plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (NotificationResponse details) {},
      );
    }
    _initialized = true;
  }

  static Future<bool> isKitchenNotifEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyKitchenNotif) ?? false;
  }

  static Future<void> setKitchenNotif(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKitchenNotif, value);
  }

  static Future<String?> getKitchenDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyKitchenDeviceName);
  }

  static Future<String?> getKitchenDeviceAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyKitchenDeviceAddress);
  }

  static Future<void> setKitchenDevice({
    required String name,
    required String address,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyKitchenDeviceName, name);
    await prefs.setString(_keyKitchenDeviceAddress, address);
  }

  static Future<void> clearKitchenDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyKitchenDeviceName);
    await prefs.remove(_keyKitchenDeviceAddress);
  }

  static Future<void> sendKitchenOrder({
    required String orderNumber,
    required List<String> items,
  }) async {
    try {
      final enabled = await isKitchenNotifEnabled();
      if (!enabled) return;

      await init();

      const androidDetails = AndroidNotificationDetails(
        'kitchen_channel',
        'Notifikasi Dapur',
        channelDescription: 'Notifikasi order masuk ke dapur',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        icon: 'ic_stat_sajia',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final id = DateTime.now().millisecondsSinceEpoch % 100000;
      final plugin = _plugin as dynamic;
      try {
        await plugin.show(
          id: id,
          title: 'Order Masuk - $orderNumber',
          body: items.join(', '),
          notificationDetails: details,
          payload: orderNumber,
        );
      } on NoSuchMethodError {
        await plugin.show(
          id,
          'Order Masuk - $orderNumber',
          items.join(', '),
          details,
          payload: orderNumber,
        );
      }

      await _sendKitchenDevice(orderNumber: orderNumber, items: items);
    } catch (_) {
      // Transaksi tidak boleh gagal hanya karena notifikasi lokal/dapur gagal.
    }
  }

  static Future<void> _sendKitchenDevice({
    required String orderNumber,
    required List<String> items,
  }) async {
    final address = await getKitchenDeviceAddress();
    if (address == null || address.isEmpty) return;

    try {
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) return;

      var connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: address,
        );
      }
      if (!connected) return;

      final text = StringBuffer()
        ..writeln('ORDER DAPUR')
        ..writeln(orderNumber)
        ..writeln('----------------')
        ..writeln(items.join('\n'))
        ..writeln('----------------')
        ..writeln();

      await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: 2, text: text.toString()),
      );
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
  }
}
