import 'dart:io';
import 'dart:typed_data';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────

class PrinterDevice {
  final String name;
  final String address;
  final String type; // 'bluetooth' | 'wifi'

  const PrinterDevice({
    required this.name,
    required this.address,
    required this.type,
  });

  bool get isBluetooth => type == 'bluetooth';
  bool get isWifi => type == 'wifi';
}

class ReceiptData {
  final String outletName;
  final String? outletAddress;
  final String? outletPhone;
  final String? receiptHeader;
  final String? receiptFooter;
  final String orderNumber;
  final String? tableLabel;
  final String cashierName;
  final String paymentMethod;
  final List<ReceiptItem> items;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double serviceCharge;
  final double total;
  final double paidAmount;
  final double changeAmount;
  final DateTime paidAt;

  const ReceiptData({
    required this.outletName,
    this.outletAddress,
    this.outletPhone,
    this.receiptHeader,
    this.receiptFooter,
    required this.orderNumber,
    this.tableLabel,
    required this.cashierName,
    required this.paymentMethod,
    required this.items,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.serviceCharge,
    required this.total,
    required this.paidAmount,
    required this.changeAmount,
    required this.paidAt,
  });
}

class ReceiptItem {
  final String name;
  final String? variantSummary;
  final double quantity;
  final double unitPrice;
  final double subtotal;

  const ReceiptItem({
    required this.name,
    this.variantSummary,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });
}

// ─────────────────────────────────────────────
// PRINT SERVICE
// ─────────────────────────────────────────────

class PrintService {
  static final PrintService _instance = PrintService._internal();
  factory PrintService() => _instance;
  PrintService._internal();

  static const _keyPrinterAddress = 'printer_address';
  static const _keyPrinterName = 'printer_name';
  static const _keyPrinterType = 'printer_type';
  static const _keyPaperWidth = 'paper_width';
  static const _keyWifiIp = 'printer_wifi_ip';
  static const _keyWifiPort = 'printer_wifi_port';

  // ── Preferences ──────────────────────────────

  Future<String> getPaperWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPaperWidth) ?? '58';
  }

  Future<void> setPaperWidth(String width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPaperWidth, width);
  }

  Future<String?> getSavedPrinterAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPrinterAddress);
  }

  Future<String?> getSavedPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPrinterName);
  }

  Future<String?> getSavedPrinterType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPrinterType);
  }

  Future<String?> getSavedWifiIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWifiIp);
  }

  Future<int> getSavedWifiPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyWifiPort) ?? 9100;
  }

  Future<void> savePrinter(PrinterDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPrinterAddress, device.address);
    await prefs.setString(_keyPrinterName, device.name);
    await prefs.setString(_keyPrinterType, device.type);
  }

  Future<void> saveWifiPrinter({
    required String ip,
    required int port,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWifiIp, ip);
    await prefs.setInt(_keyWifiPort, port);
    await prefs.setString(_keyPrinterName, name);
    await prefs.setString(_keyPrinterType, 'wifi');
    await prefs.setString(_keyPrinterAddress, ip);
  }

  Future<void> clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPrinterAddress);
    await prefs.remove(_keyPrinterName);
    await prefs.remove(_keyPrinterType);
    await prefs.remove(_keyWifiIp);
    await prefs.remove(_keyWifiPort);
  }

  // ── Bluetooth ────────────────────────────────

  Future<List<BluetoothInfo>> scanBluetoothDevices() async {
    try {
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) return [];
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  Future<bool> connectBluetooth(String address) async {
    try {
      return await PrintBluetoothThermal.connect(macPrinterAddress: address);
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnectBluetooth() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
  }

  Future<bool> get isBluetoothConnected async =>
      await PrintBluetoothThermal.connectionStatus;

  // ── Print ─────────────────────────────────────

  Future<PrintResult> printReceipt(ReceiptData data) async {
    final type = await getSavedPrinterType();
    final address = await getSavedPrinterAddress();

    if (address == null || type == null) {
      return PrintResult.noPrinterSelected;
    }

    if (type == 'bluetooth') {
      return await _printBluetooth(data, address);
    } else if (type == 'wifi') {
      return await _printWifi(data);
    }

    return PrintResult.error;
  }

  Future<PrintResult> _printBluetooth(ReceiptData data, String address) async {
    try {
      final connected = await isBluetoothConnected;
      if (!connected) {
        final ok = await connectBluetooth(address);
        if (!ok) return PrintResult.connectionFailed;
      }

      final bytes = await _buildReceipt(data);
      final result =
          await PrintBluetoothThermal.writeBytes(Uint8List.fromList(bytes));
      return result ? PrintResult.success : PrintResult.error;
    } catch (_) {
      return PrintResult.error;
    }
  }

  Future<PrintResult> _printWifi(ReceiptData data) async {
    try {
      final ip = await getSavedWifiIp();
      final port = await getSavedWifiPort();
      if (ip == null) return PrintResult.noPrinterSelected;

      final bytes = await _buildReceipt(data);
      final socket =
          await RawSocket.connect(ip, port).timeout(const Duration(seconds: 5));
      socket.write(Uint8List.fromList(bytes));
      await Future.delayed(const Duration(milliseconds: 500));
      socket.close();

      return PrintResult.success;
    } catch (_) {
      return PrintResult.connectionFailed;
    }
  }

  // ── ESC/POS Builder ───────────────────────────

  Future<List<int>> _buildReceipt(ReceiptData data) async {
    final paperWidth = await getPaperWidth();
    final paper = paperWidth == '80' ? PaperSize.mm80 : PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    var bytes = <int>[];
    final cols = paperWidth == '80' ? 48 : 32;

    bytes += generator.setGlobalCodeTable('PC865');
    bytes += generator.emptyLines(1);
    bytes += generator.text(data.outletName,
        styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2));

    if (data.outletAddress?.isNotEmpty == true) {
      bytes += generator.text(data.outletAddress!,
          styles: const PosStyles(align: PosAlign.center));
    }
    if (data.outletPhone?.isNotEmpty == true) {
      bytes += generator.text('Telp: ${data.outletPhone}',
          styles: const PosStyles(align: PosAlign.center));
    }
    if (data.receiptHeader?.isNotEmpty == true) {
      bytes += generator.emptyLines(1);
      for (final line in data.receiptHeader!.split('\n')) {
        bytes += generator.text(line,
            styles: const PosStyles(align: PosAlign.center));
      }
    }

    bytes += generator.hr(ch: '-', len: cols);

    bytes += generator.row([
      PosColumn(text: 'No', width: 3),
      PosColumn(
          text: ': #${data.orderNumber}',
          width: 9,
          styles: const PosStyles(bold: true)),
    ]);
    bytes += generator.row([
      PosColumn(text: 'Tanggal', width: 3),
      PosColumn(text: ': ${_formatDate(data.paidAt)}', width: 9),
    ]);
    bytes += generator.row([
      PosColumn(text: 'Waktu', width: 3),
      PosColumn(text: ': ${_formatTime(data.paidAt)}', width: 9),
    ]);
    bytes += generator.row([
      PosColumn(text: 'Kasir', width: 3),
      PosColumn(text: ': ${data.cashierName}', width: 9),
    ]);
    if (data.tableLabel?.isNotEmpty == true) {
      bytes += generator.row([
        PosColumn(text: 'Meja', width: 3),
        PosColumn(text: ': ${data.tableLabel}', width: 9),
      ]);
    }
    bytes += generator.row([
      PosColumn(text: 'Bayar', width: 3),
      PosColumn(text: ': ${_methodLabel(data.paymentMethod)}', width: 9),
    ]);

    bytes += generator.hr(ch: '-', len: cols);

    for (final item in data.items) {
      bytes += generator.text(item.name, styles: const PosStyles(bold: true));
      if (item.variantSummary?.isNotEmpty == true) {
        bytes += generator.text('  ${item.variantSummary}',
            styles: const PosStyles(fontType: PosFontType.fontB));
      }
      bytes += generator.row([
        PosColumn(
            text:
                '  ${item.quantity.toInt()}x ${_formatRupiah(item.unitPrice)}',
            width: 8),
        PosColumn(
            text: _formatRupiah(item.subtotal),
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr(ch: '-', len: cols);

    bytes += generator.row([
      PosColumn(text: 'Subtotal', width: 6),
      PosColumn(
          text: _formatRupiah(data.subtotal),
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    if (data.discountAmount > 0) {
      bytes += generator.row([
        PosColumn(text: 'Diskon', width: 6),
        PosColumn(
            text: '-${_formatRupiah(data.discountAmount)}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    if (data.taxAmount > 0) {
      bytes += generator.row([
        PosColumn(text: 'Pajak', width: 6),
        PosColumn(
            text: _formatRupiah(data.taxAmount),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    if (data.serviceCharge > 0) {
      bytes += generator.row([
        PosColumn(text: 'Service', width: 6),
        PosColumn(
            text: _formatRupiah(data.serviceCharge),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr(ch: '=', len: cols);
    bytes += generator.row([
      PosColumn(
          text: 'TOTAL',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(
          text: _formatRupiah(data.total),
          width: 6,
          styles: const PosStyles(
              bold: true, align: PosAlign.right, height: PosTextSize.size2)),
    ]);
    bytes += generator.hr(ch: '-', len: cols);

    if (data.paymentMethod == 'cash') {
      bytes += generator.row([
        PosColumn(text: 'Bayar', width: 6),
        PosColumn(
            text: _formatRupiah(data.paidAmount),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(
            text: 'Kembali', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(
            text: _formatRupiah(data.changeAmount),
            width: 6,
            styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
    }

    bytes += generator.emptyLines(1);

    if (data.receiptFooter?.isNotEmpty == true) {
      for (final line in data.receiptFooter!.split('\n')) {
        bytes += generator.text(line,
            styles: const PosStyles(align: PosAlign.center));
      }
    } else {
      bytes += generator.text('Terima kasih!',
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }

    bytes += generator.emptyLines(3);
    bytes += generator.cut();

    return bytes;
  }

  // ── Helpers ───────────────────────────────────

  String _formatRupiah(double amount) {
    final str = amount.toInt().toString();
    final reversed = str.split('').reversed.toList();
    final buffer = <String>[];
    for (int i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.add('.');
      buffer.add(reversed[i]);
    }
    return 'Rp${buffer.reversed.join('')}';
  }

  String _formatDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  String _methodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Tunai';
      case 'qris':
        return 'QRIS';
      default:
        return method.toUpperCase();
    }
  }
}

// ─────────────────────────────────────────────
// RESULT
// ─────────────────────────────────────────────

enum PrintResult {
  success,
  noPrinterSelected,
  connectionFailed,
  usbNotSupported,
  error,
}

extension PrintResultMessage on PrintResult {
  String get message {
    switch (this) {
      case PrintResult.success:
        return 'Nota berhasil dicetak';
      case PrintResult.noPrinterSelected:
        return 'Belum ada printer dipilih. Atur di Pengaturan → Printer';
      case PrintResult.connectionFailed:
        return 'Gagal terhubung ke printer. Pastikan Bluetooth aktif dan printer menyala';
      case PrintResult.usbNotSupported:
        return 'USB printer belum didukung di versi ini';
      case PrintResult.error:
        return 'Gagal mencetak. Coba lagi';
    }
  }

  bool get isSuccess => this == PrintResult.success;
}
