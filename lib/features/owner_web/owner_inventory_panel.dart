import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_notice.dart';
import '../../core/numeric_input_formatter.dart';
import '../../domain/costing.dart';
import '../../domain/ingredient_inventory.dart';

String _money(num value) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(value);
String _number(num value) => NumberFormat('0.###', 'id_ID').format(value);
double _value(dynamic value) => double.tryParse(value.toString()) ?? 0;
String _date(dynamic value) => DateFormat('d MMM y, HH:mm', 'id_ID')
    .format(DateTime.parse(value.toString()).toLocal());
String _purpose(String? value) => switch (value) {
      'rnd' => 'R&D / Kalibrasi',
      'personal' => 'Pakai sendiri',
      'waste' => 'Terbuang',
      _ => 'Pemakaian'
    };
String inventoryError(Object error) {
  if (error is PostgrestException) {
    if (error.message.contains('CLOUD_REQUIRED')) {
      return 'Aktifkan atau perpanjang Cloud untuk mencatat bahan di cabang ini.';
    }
    if (const {'PGRST202', 'PGRST205', '42P01', '42703'}.contains(error.code)) {
      return 'Fitur ini membutuhkan migration bahan baku terbaru.';
    }
    if (error.code == '23505') {
      return 'Nama bahan sudah ada. Pilih bahan tersebut agar stoknya tetap satu.';
    }
    if (error.message.contains('CONFLICT')) {
      return 'Pencatatan sudah diterima sebelumnya. Muat ulang sebelum membuat perubahan.';
    }
    if (error.message.contains('UNIT')) {
      return 'Satuan bahan dan satuan pemakaian harus satu jenis.';
    }
    if (error.message.contains('ACCESS')) {
      return 'Sesi owner tidak memiliki akses ke cabang ini.';
    }
  }
  return 'Belum dapat menyimpan. Periksa koneksi lalu coba lagi; data tidak dicatat dua kali saat retry.';
}

class OwnerInventoryPanel extends StatefulWidget {
  const OwnerInventoryPanel(
      {super.key, required this.outletId, required this.onChanged});
  final String outletId;
  final VoidCallback onChanged;
  @override
  State<OwnerInventoryPanel> createState() => _OwnerInventoryPanelState();
}

class _InventoryData {
  const _InventoryData(this.ingredients, this.purchases, this.usage,
      this.movements, this.products);
  final List<Ingredient> ingredients;
  final List<Map<String, dynamic>> purchases, usage, movements, products;
}

class _OwnerInventoryPanelState extends State<OwnerInventoryPanel> {
  late Future<_InventoryData> _data;
  DateTimeRange? _range;
  String _period = 'all';
  String _tab = 'ingredients';
  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  @override
  void didUpdateWidget(covariant OwnerInventoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outletId != widget.outletId) _data = _load();
  }

  Future<List<Map<String, dynamic>>> _rows(String table,
      {String? dateColumn}) async {
    final result = <Map<String, dynamic>>[];
    final outletId = widget.outletId;
    final range = _range;
    for (var offset = 0;; offset += 1000) {
      dynamic query = Supabase.instance.client
          .from(table)
          .select()
          .eq('outlet_id', outletId);
      if (dateColumn != null && range != null) {
        final end =
            DateTime(range.end.year, range.end.month, range.end.day + 1);
        query = query
            .gte(dateColumn, range.start.toUtc().toIso8601String())
            .lt(dateColumn, end.toUtc().toIso8601String());
      }
      final page = await query.order('id').range(offset, offset + 999) as List;
      result.addAll(page.map((row) => Map<String, dynamic>.from(row as Map)));
      if (page.length < 1000) return result;
    }
  }

  Future<_InventoryData> _load() async {
    final rows = await Future.wait([
      _rows('ingredients'),
      _rows('ingredient_purchases', dateColumn: 'occurred_at'),
      _rows('internal_material_usage', dateColumn: 'occurred_at'),
      _rows('ingredient_movements', dateColumn: 'occurred_at'),
      _rows('products'),
    ]);
    for (final index in [1, 2, 3]) {
      rows[index].sort((a, b) =>
          b['occurred_at'].toString().compareTo(a['occurred_at'].toString()));
    }
    final ingredients = rows[0].map(Ingredient.fromJson).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _InventoryData(ingredients, rows[1], rows[2], rows[3], rows[4]);
  }

  void _reload() => setState(() {
        _data = _load();
      });
  Future<void> _edit(Widget dialog) async {
    final saved = await showDialog<bool>(
        context: context, barrierDismissible: false, builder: (_) => dialog);
    if (!mounted || saved != true) return;
    _reload();
    widget.onChanged();
    AppNotice.show(
        context, const SnackBar(content: Text('Pencatatan tersimpan.')));
  }

  Future<void> _periodChanged(String? value) async {
    if (value == null) return;
    DateTimeRange? range;
    final now = DateTime.now();
    if (value == 'month') {
      range = DateTimeRange(
          start: DateTime(now.year, now.month),
          end: DateTime(now.year, now.month, now.day));
    }
    if (value == 'custom') {
      range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: now,
          initialDateRange: _range);
      if (!mounted || range == null) return;
    }
    setState(() {
      _period = value;
      _range = range;
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_InventoryData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint(
                '[OwnerInventory] load failed: ${snapshot.error is PostgrestException ? (snapshot.error as PostgrestException).code : snapshot.error.runtimeType}');
            return Card(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inventoryError(snapshot.error!)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: _reload,
                              child: const Text('Coba lagi')),
                        ])));
          }
          if (!snapshot.hasData) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator()));
          }
          final data = snapshot.data!;
          final purchaseTotal = data.purchases
              .fold<double>(0, (sum, row) => sum + _value(row['total']));
          final usageTotal = data.usage
              .fold<double>(0, (sum, row) => sum + _value(row['total_cogs']));
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bahan baku & belanja',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                    'Belanja menambah persediaan. HPP penjualan dan pemakaian internal dicatat saat bahan digunakan.'),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _stat('Belanja · periode terpilih', _money(purchaseTotal)),
                  _stat('Pemakaian internal · HPP', _money(usageTotal)),
                  _stat('Jenis bahan', '${data.ingredients.length}'),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _period,
                        decoration:
                            const InputDecoration(labelText: 'Periode laporan'),
                        items: const [
                          DropdownMenuItem(
                              value: 'all', child: Text('Semua waktu')),
                          DropdownMenuItem(
                              value: 'month', child: Text('Bulan ini')),
                          DropdownMenuItem(
                              value: 'custom',
                              child: Text('Pilih rentang tanggal')),
                        ],
                        onChanged: _periodChanged)),
                if (_range != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          '${DateFormat('d MMM y', 'id_ID').format(_range!.start)} – ${DateFormat('d MMM y', 'id_ID').format(_range!.end)}')),
                const SizedBox(height: 18),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final entry in const {
                    'ingredients': 'Stok bahan',
                    'purchases': 'Laporan belanja',
                    'usage': 'Pemakaian internal',
                    'movements': 'Riwayat stok'
                  }.entries)
                    ChoiceChip(
                        label: Text(entry.value),
                        selected: _tab == entry.key,
                        onSelected: (_) => setState(() => _tab = entry.key)),
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton.icon(
                      onPressed: () =>
                          _edit(_IngredientDialog(outletId: widget.outletId)),
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah bahan')),
                  OutlinedButton.icon(
                      onPressed: data.ingredients.isEmpty
                          ? null
                          : () => _edit(_PurchaseDialog(
                              outletId: widget.outletId,
                              ingredients: data.ingredients)),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: const Text('Catat belanja')),
                  OutlinedButton.icon(
                      onPressed: data.products.isEmpty
                          ? null
                          : () => _edit(_UsageDialog(
                              outletId: widget.outletId,
                              products: data.products)),
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('Catat pemakaian')),
                  IconButton(
                      onPressed: _reload,
                      tooltip: 'Muat ulang',
                      icon: const Icon(Icons.refresh)),
                ]),
                const SizedBox(height: 16),
                if (_tab == 'ingredients') ...[
                  const Text(
                      'Stok saat ini · pilih bahan ini saat mengisi resep di tab Menu. Angka negatif berarti ada kekurangan stok yang perlu diperiksa.'),
                  const SizedBox(height: 10),
                  if (data.ingredients.isEmpty)
                    const _Empty(
                        'Tambah bahan pertama, lalu catat jumlah dan harga belanjanya.'),
                  for (final ingredient in data.ingredients)
                    Card(
                        child: ListTile(
                      title: Text(ingredient.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          'Harga rata-rata ${_money(ingredient.unitCost)} / ${ingredient.unit.shortLabel}'),
                      trailing: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                                '${_number(ingredient.quantity)} ${ingredient.unit.shortLabel}',
                                style: TextStyle(
                                    color: ingredient.quantity < 0
                                        ? Colors.red.shade700
                                        : null,
                                    fontWeight: FontWeight.w700)),
                            IconButton(
                                tooltip: 'Ubah nama bahan',
                                onPressed: () => _edit(_IngredientDialog(
                                    outletId: widget.outletId,
                                    initial: ingredient)),
                                icon: const Icon(Icons.edit_outlined)),
                          ]),
                    )),
                ],
                if (_tab == 'purchases') ...[
                  const Text(
                      'Belanja dicatat sebagai penambahan persediaan dan uang keluar. Tidak dikurangkan lagi sebagai biaya operasional.'),
                  const SizedBox(height: 10),
                  if (data.purchases.isEmpty)
                    const _Empty('Belum ada belanja pada periode ini.'),
                  for (final row in data.purchases)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${_date(row['occurred_at'])} · ${_money(_value(row['total']))}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  if (row['note'] != null)
                                    Text(row['note'].toString()),
                                  for (final item in row['items'] as List)
                                    Text(
                                        '${item['name']} · ${_number(_value(item['quantity']))} ${costingUnitFromStorage(item['unit']).shortLabel} · ${_money(_value(item['price']))}'),
                                ]))),
                ],
                if (_tab == 'usage') ...[
                  const Text(
                      'Tanpa pembayaran dan tidak menambah omzet. Nilai HPP masuk biaya pemakaian internal; bahan resep mengurangi stok.'),
                  const SizedBox(height: 10),
                  if (data.usage.isEmpty)
                    const _Empty(
                        'Belum ada pemakaian internal pada periode ini.'),
                  for (final row in data.usage)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${_purpose(row['purpose'])} · ${_money(_value(row['total_cogs']))}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  Text(_date(row['occurred_at'])),
                                  if (row['note'] != null)
                                    Text(row['note'].toString()),
                                  for (final item in row['items'] as List)
                                    Text(
                                        '${_number(_value(item['quantity']))} × ${item['name']} · HPP ${_money(_value(item['unit_cogs']))} / porsi'),
                                  if (row['has_untracked_materials'] == true)
                                    const Text(
                                        'Ada menu tanpa bahan terhubung. Nilai HPP tercatat, tetapi stok bahan manual belum dapat dikurangi.',
                                        style: TextStyle(
                                            color: Colors.deepOrange)),
                                ]))),
                ],
                if (_tab == 'movements') ...[
                  if (data.movements.isEmpty)
                    const _Empty('Belum ada pergerakan stok pada periode ini.'),
                  for (final row in data.movements)
                    Card(
                        child: ListTile(
                      title: Text(data.ingredients
                              .where((i) => i.id == row['ingredient_id'])
                              .map((i) => i.name)
                              .firstOrNull ??
                          'Bahan'),
                      subtitle: Text('${switch (row['source_type']) {
                        'purchase' => 'Belanja',
                        'sale' => 'Penjualan',
                        'void' => 'Pembatalan penjualan',
                        _ => 'Pemakaian internal'
                      }} · ${_date(row['occurred_at'])}'),
                      trailing: Text(
                          '${_value(row['quantity']) >= 0 ? '+' : ''}${_number(_value(row['quantity']))} ${data.ingredients.where((i) => i.id == row['ingredient_id']).map((i) => i.unit.shortLabel).firstOrNull ?? ''}'),
                    )),
                ],
              ]);
        },
      );
  Widget _stat(String title, String value) => SizedBox(
      width: 230,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    const SizedBox(height: 6),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800))
                  ]))));
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(padding: const EdgeInsets.all(24), child: Text(message)));
}

class _IngredientDialog extends StatefulWidget {
  const _IngredientDialog({required this.outletId, this.initial});
  final String outletId;
  final Ingredient? initial;
  @override
  State<_IngredientDialog> createState() => _IngredientDialogState();
}

class _IngredientDialogState extends State<_IngredientDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final String _id = widget.initial?.id ?? const Uuid().v4();
  late CostingUnit _unit = widget.initial?.unit ?? CostingUnit.gram;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Isi nama bahan.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('save_owner_ingredient', params: {
        'p_id': _id,
        'p_outlet_id': widget.outletId,
        'p_name': _name.text.trim(),
        'p_unit': _unit.name
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = inventoryError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
            widget.initial == null ? 'Tambah bahan baku' : 'Ubah bahan baku'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: const InputDecoration(
                      labelText: 'Nama bahan', hintText: 'Contoh: Susu UHT')),
              DropdownButtonFormField<CostingUnit>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Satuan stok'),
                  items: const [
                    DropdownMenuItem(
                        value: CostingUnit.gram, child: Text('Gram (g)')),
                    DropdownMenuItem(
                        value: CostingUnit.milliliter,
                        child: Text('Mililiter (ml)')),
                    DropdownMenuItem(
                        value: CostingUnit.piece, child: Text('Pcs / unit'))
                  ],
                  onChanged: _saving || widget.initial != null
                      ? null
                      : (value) => setState(() => _unit = value!)),
              const SizedBox(height: 12),
              const Text(
                  'Jumlah dan harga beli diisi lewat Catat belanja. Pembelian kg/liter otomatis dikonversi ke gram/ml.'),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
            ]))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan…' : 'Simpan'))
        ],
      ));
}

class _PurchaseLine {
  _PurchaseLine(Ingredient ingredient)
      : ingredientId = ingredient.id,
        unit = ingredient.unit;
  String ingredientId;
  CostingUnit unit;
  final quantity = TextEditingController();
  final price = TextEditingController();
  void dispose() {
    quantity.dispose();
    price.dispose();
  }
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({required this.outletId, required this.ingredients});
  final String outletId;
  final List<Ingredient> ingredients;
  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  final _id = const Uuid().v4();
  final _note = TextEditingController();
  late final _lines = [_PurchaseLine(widget.ingredients.first)];
  DateTime _occurredAt = DateTime.now();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final rows = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final line in _lines) {
      final quantity = double.tryParse(line.quantity.text);
      final price = double.tryParse(line.price.text);
      if (!seen.add(line.ingredientId) ||
          quantity == null ||
          !quantity.isFinite ||
          quantity <= 0 ||
          price == null ||
          !price.isFinite ||
          price < 0) {
        setState(() => _error =
            'Isi jumlah dan harga total setiap bahan. Gabungkan bahan yang sama dalam satu baris.');
        return;
      }
      rows.add({
        'ingredient_id': line.ingredientId,
        'quantity': quantity,
        'unit': line.unit.name,
        'price': price
      });
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('record_ingredient_purchase', params: {
        'p_id': _id,
        'p_outlet_id': widget.outletId,
        'p_items': rows,
        'p_occurred_at': _occurredAt.toUtc().toIso8601String(),
        'p_note': _note.text.trim().isEmpty ? null : _note.text.trim()
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = inventoryError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Catat belanja bahan'),
        content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final day = await showDatePicker(
                                  context: context,
                                  initialDate: _occurredAt,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now());
                              if (day != null && mounted) {
                                setState(() => _occurredAt = day);
                              }
                            },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                          DateFormat('d MMM y', 'id_ID').format(_occurredAt))),
                  for (final line in _lines)
                    Padding(
                        key: ObjectKey(line),
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(children: [
                          DropdownButtonFormField<String>(
                              initialValue: line.ingredientId,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: 'Bahan'),
                              items: [
                                for (final i in widget.ingredients)
                                  DropdownMenuItem(
                                      value: i.id, child: Text(i.name))
                              ],
                              onChanged: _saving
                                  ? null
                                  : (id) => setState(() {
                                        line.ingredientId = id!;
                                        line.unit = widget.ingredients
                                            .firstWhere((i) => i.id == id)
                                            .unit;
                                      })),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: _numberField(
                                    line.quantity, 'Jumlah beli', !_saving)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: DropdownButtonFormField<CostingUnit>(
                                    key: ValueKey(
                                        '${line.ingredientId}-${line.unit.name}'),
                                    initialValue: line.unit,
                                    decoration: const InputDecoration(
                                        labelText: 'Satuan'),
                                    items: [
                                      for (final unit in CostingUnit.values
                                          .where((u) =>
                                              u.family == line.unit.family))
                                        DropdownMenuItem(
                                            value: unit,
                                            child: Text(unit.shortLabel))
                                    ],
                                    onChanged: _saving
                                        ? null
                                        : (unit) =>
                                            setState(() => line.unit = unit!)))
                          ]),
                          const SizedBox(height: 8),
                          _numberField(line.price, 'Harga total bahan ini (Rp)',
                              !_saving),
                          if (_lines.length > 1)
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                    onPressed: _saving
                                        ? null
                                        : () => setState(() {
                                              _lines.remove(line);
                                              line.dispose();
                                            }),
                                    child: const Text('Hapus baris'))),
                        ])),
                  OutlinedButton.icon(
                      onPressed:
                          _saving || _lines.length >= widget.ingredients.length
                              ? null
                              : () => setState(() => _lines.add(_PurchaseLine(
                                  widget.ingredients.firstWhere((i) => !_lines
                                      .any((l) => l.ingredientId == i.id))))),
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah barang')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _note,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                          labelText: 'Catatan / toko / pemasok (opsional)')),
                  const SizedBox(height: 12),
                  const Text(
                      'Contoh: susu 2 liter, harga total Rp46.000. Stok bertambah 2.000 ml. Jangan input belanja ini lagi sebagai pengeluaran operasional.'),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                ]))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan…' : 'Simpan belanja'))
        ],
      ));
}

class _UsageDialog extends StatefulWidget {
  const _UsageDialog({required this.outletId, required this.products});
  final String outletId;
  final List<Map<String, dynamic>> products;
  @override
  State<_UsageDialog> createState() => _UsageDialogState();
}

class _UsageDialogState extends State<_UsageDialog> {
  final _id = const Uuid().v4();
  final _occurredAt = DateTime.now();
  final _quantity = TextEditingController(text: '1');
  final _note = TextEditingController();
  late String _productId = widget.products.first['id'].toString();
  String _purposeValue = 'rnd';
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final quantity = double.tryParse(_quantity.text);
    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      setState(() => _error = 'Isi jumlah pemakaian yang valid.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .rpc('record_internal_material_usage', params: {
        'p_id': _id,
        'p_outlet_id': widget.outletId,
        'p_purpose': _purposeValue,
        'p_items': [
          {'product_id': _productId, 'quantity': quantity}
        ],
        'p_occurred_at': _occurredAt.toUtc().toIso8601String(),
        'p_note': _note.text.trim().isEmpty ? null : _note.text.trim()
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = inventoryError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.products.firstWhere((p) => p['id'] == _productId);
    return PopScope(
        canPop: !_saving,
        child: AlertDialog(
            title: const Text('Pemakaian tanpa pembayaran'),
            content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: _productId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Menu'),
                      items: [
                        for (final p in widget.products)
                          DropdownMenuItem(
                              value: p['id'].toString(),
                              child: Text(p['name'].toString(),
                                  overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: _saving
                          ? null
                          : (id) => setState(() => _productId = id!)),
                  const SizedBox(height: 12),
                  _numberField(_quantity, 'Jumlah porsi', !_saving,
                      onChanged: (_) => setState(() {})),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                      initialValue: _purposeValue,
                      decoration: const InputDecoration(labelText: 'Keperluan'),
                      items: [
                        for (final p in ['rnd', 'personal', 'waste'])
                          DropdownMenuItem(value: p, child: Text(_purpose(p)))
                      ],
                      onChanged: _saving
                          ? null
                          : (p) => setState(() => _purposeValue = p!)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _note,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                          labelText: 'Catatan (opsional)')),
                  const SizedBox(height: 12),
                  Text(
                      'Perkiraan HPP ${_money(_value(product['cogs']) * _value(_quantity.text))}. Nilai final mengikuti resep tersimpan. Tidak ada pembayaran atau omzet.'),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                ]))),
            actions: [
              TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Menyimpan…' : 'Catat pemakaian'))
            ]));
  }
}

Widget _numberField(
        TextEditingController controller, String label, bool enabled,
        {ValueChanged<String>? onChanged}) =>
    TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [
          NormalizedNumberInputFormatter(allowDecimal: true)
        ],
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged);
