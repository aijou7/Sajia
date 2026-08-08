import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../core/bluetooth_system.dart';
import '../../core/print_service.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';

class PrinterSettingsCard extends StatefulWidget {
  const PrinterSettingsCard({super.key});

  @override
  State<PrinterSettingsCard> createState() => _PrinterSettingsCardState();
}

class _PrinterSettingsCardState extends State<PrinterSettingsCard> {
  String? _savedName;
  String? _savedType;
  String _paperWidth = '58';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = PrintService();
    final name = await svc.getSavedPrinterName();
    final type = await svc.getSavedPrinterType();
    final paper = await svc.getPaperWidth();
    if (mounted) {
      setState(() {
        _savedName = name;
        _savedType = type;
        _paperWidth = paper;
        _loading = false;
      });
    }
  }

  Future<void> _selectBluetooth() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BluetoothPickerSheet(
        onSelected: (device) async {
          await PrintService().savePrinter(device);
          _load();
        },
      ),
    );
  }

  Future<void> _selectWifi() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WifiPrinterSheet(onSaved: _load),
    );
  }

  Future<void> _removePrinter() async {
    await PrintService().clearSavedPrinter();
    _load();
  }

  Future<void> _changePaperWidth(String width) async {
    await PrintService().setPaperWidth(width);
    setState(() => _paperWidth = width);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.subtleBorder),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          // Printer terpilih
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.print_outlined,
                  color: AppTheme.primary, size: 18),
            ),
            title: const Text('Printer',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: _loading
                ? const Text('Memuat...',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)))
                : Text(
                    _savedName != null
                        ? '$_savedName (${_savedType == 'wifi' ? 'WiFi' : 'Bluetooth'})'
                        : 'Belum ada printer dipilih',
                    style: TextStyle(
                      fontSize: 11,
                      color: _savedName != null
                          ? AppTheme.success
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
            trailing: _savedName != null
                ? IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.danger, size: 18),
                    onPressed: _removePrinter,
                    tooltip: 'Hapus printer',
                  )
                : null,
          ),

          // Tombol pilih printer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectBluetooth,
                    icon: const Icon(Icons.bluetooth, size: 16),
                    label:
                        const Text('Bluetooth', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectWifi,
                    icon: const Icon(Icons.wifi, size: 16),
                    label:
                        const Text('WiFi/LAN', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 56),

          // Lebar kertas
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Icon(Icons.straighten_outlined,
                  color: AppTheme.primary, size: 18),
            ),
            title: const Text('Lebar Kertas',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text(
              _paperWidth == '80' ? '80mm' : '58mm',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PaperChip(
                  label: '58mm',
                  selected: _paperWidth == '58',
                  onTap: () => _changePaperWidth('58'),
                ),
                const SizedBox(width: 8),
                _PaperChip(
                  label: '80mm',
                  selected: _paperWidth == '80',
                  onTap: () => _changePaperWidth('80'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Paper Width Chip ──────────────────────────────────────────
class _PaperChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PaperChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minWidth: 60, minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryLight : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.subtleBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppTheme.primary : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

// ── Bluetooth Picker Sheet ────────────────────────────────────
class BluetoothPickerSheet extends StatefulWidget {
  final Function(PrinterDevice) onSelected;

  const BluetoothPickerSheet({super.key, required this.onSelected});

  @override
  State<BluetoothPickerSheet> createState() => _BluetoothPickerSheetState();
}

class _BluetoothPickerSheetState extends State<BluetoothPickerSheet>
    with WidgetsBindingObserver {
  List<BluetoothInfo> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scan(openPanelIfDisabled: false);
  }

  Future<void> _scan({bool openPanelIfDisabled = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ready = await BluetoothSystem.ensureBluetoothReady(
        openPanelIfDisabled: openPanelIfDisabled,
      );
      final devices = ready
          ? await PrintService().scanBluetoothDevices()
          : <BluetoothInfo>[];
      if (mounted) {
        setState(() {
          _devices = devices;
          _error = ready ? null : 'Nyalakan Bluetooth untuk mencari perangkat';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Pastikan Bluetooth aktif di perangkat';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDeep.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: bottomSheetSafePadding(context),
        top: 8,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            Row(
              children: [
                const Text('Pilih Printer Bluetooth',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _scan,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pastikan printer sudah dinyalakan dan di-pair di Bluetooth perangkat.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Mencari perangkat Bluetooth...'),
                ]),
              ))
            else if (_error != null)
              Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const Icon(Icons.bluetooth_disabled,
                      size: 48, color: AppTheme.danger),
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF6B7280))),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _scan,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Coba Lagi'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await BluetoothSystem.openBluetoothPanel();
                        },
                        icon: const Icon(Icons.settings_bluetooth),
                        label: const Text('Nyalakan Bluetooth'),
                      ),
                    ],
                  ),
                ]),
              ))
            else if (_devices.isEmpty)
              Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.bluetooth_searching,
                      size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  const Text(
                    'Tidak ada perangkat ditemukan.\nPastikan printer sudah di-pair di Bluetooth settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan Ulang'),
                  ),
                ]),
              ))
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final device = _devices[i];
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.print_outlined,
                          color: Color(0xFF3B82F6), size: 20),
                    ),
                    title: Text(
                      device.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      device.macAdress,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                    trailing: const Icon(Icons.chevron_right,
                        color: Color(0xFFD1D5DB)),
                    onTap: () {
                      widget.onSelected(PrinterDevice(
                        name: device.name,
                        address: device.macAdress,
                        type: 'bluetooth',
                      ));
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── WiFi Printer Sheet ────────────────────────────────────────
class WifiPrinterSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const WifiPrinterSheet({super.key, required this.onSaved});

  @override
  State<WifiPrinterSheet> createState() => _WifiPrinterSheetState();
}

class _WifiPrinterSheetState extends State<WifiPrinterSheet> {
  final _ipCtrl = TextEditingController(text: '192.168.1.');
  final _portCtrl = TextEditingController(text: '9100');
  final _nameCtrl = TextEditingController(text: 'Printer WiFi');
  bool _saving = false;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ipCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await PrintService().saveWifiPrinter(
      ip: _ipCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 9100,
      name: _nameCtrl.text.trim().isEmpty
          ? 'Printer WiFi'
          : _nameCtrl.text.trim(),
    );
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDeep.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: bottomSheetSafePadding(context),
        top: 8,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const Text('Printer WiFi/LAN',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Pastikan printer dan tablet terhubung ke WiFi yang sama.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 20),
            _field('Nama Printer', _nameCtrl, 'Contoh: Printer Kasir'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _field('IP Address', _ipCtrl, '192.168.1.100',
                      type: TextInputType.number),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field('Port', _portCtrl, '9100',
                      type: TextInputType.number, selectAllOnFocus: true),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Simpan',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint,
      {TextInputType type = TextInputType.text,
      bool selectAllOnFocus = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151))),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          selectAllOnFocus: selectAllOnFocus,
          keyboardType: type,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderColor)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5)),
          ),
        ),
      ],
    );
  }
}
