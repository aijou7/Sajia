import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/numeric_input_formatter.dart';
import '../../core/theme.dart';
import '../../domain/costing.dart';

Future<List<CostingComponent>?> showHppCalculator({
  required BuildContext context,
  required String outletId,
  required String productId,
  required List<CostingComponent> initial,
}) {
  return showModalBottomSheet<List<CostingComponent>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HppCalculatorSheet(
      outletId: outletId,
      productId: productId,
      initial: initial,
    ),
  );
}

class HppCalculatorSheet extends StatefulWidget {
  const HppCalculatorSheet({
    super.key,
    required this.outletId,
    required this.productId,
    required this.initial,
  });

  final String outletId;
  final String productId;
  final List<CostingComponent> initial;

  @override
  State<HppCalculatorSheet> createState() => _HppCalculatorSheetState();
}

class _HppCalculatorSheetState extends State<HppCalculatorSheet> {
  late List<CostingComponent> _components;

  @override
  void initState() {
    super.initState();
    _components = List<CostingComponent>.from(widget.initial);
  }

  double get _total => totalCosting(_components);

  Future<void> _edit([int? index]) async {
    final current = index == null ? null : _components[index];
    final result = await showDialog<CostingComponent>(
      context: context,
      builder: (_) => _CostingLineDialog(
        outletId: widget.outletId,
        productId: widget.productId,
        initial: current,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _components.add(result);
      } else {
        _components[index] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 760),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kalkulator HPP',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Masukkan ukuran beli dan takaran resep per porsi.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tambah bahan',
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: AppTheme.primary,
                ),
              ],
            ),
          ),
          Flexible(
            child: _components.isEmpty
                ? const SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: _EmptyCostingState(),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    shrinkWrap: true,
                    itemCount: _components.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final component = _components[index];
                      return _CostingLineCard(
                        component: component,
                        onEdit: () => _edit(index),
                        onDelete: () => setState(() => _components.removeAt(index)),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: AppTheme.subtleBorder)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'HPP per porsi',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _money(_total),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _components),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Pakai sebagai HPP menu'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCostingState extends StatelessWidget {
  const _EmptyCostingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.subtleBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.calculate_outlined, size: 34, color: AppTheme.primary),
          const SizedBox(height: 10),
          const Text(
            'Belum ada bahan resep',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const Text(
            'Contoh: beli beans 1 kg Rp190.000, lalu pakai 18 gram per porsi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              final state = context.findAncestorStateOfType<_HppCalculatorSheetState>();
              state?._edit();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tambah bahan pertama'),
          ),
        ],
      ),
    );
  }
}

class _CostingLineCard extends StatelessWidget {
  const _CostingLineCard({
    required this.component,
    required this.onEdit,
    required this.onDelete,
  });

  final CostingComponent component;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final invalid = !component.hasCompatibleUnits;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: invalid ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: invalid ? AppTheme.warning : AppTheme.subtleBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(component.materialName, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${_number(component.recipeQuantity)} ${component.recipeUnit.shortLabel} / porsi · '
                  'beli ${_number(component.packageQuantity)} ${component.packageUnit.shortLabel} seharga ${_money(component.packagePrice)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.35),
                ),
                if (invalid)
                  const Text(
                    'Satuan beli dan resep harus sama jenisnya.',
                    style: TextStyle(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Text(
            _money(component.portionCost),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit bahan')),
              PopupMenuItem(value: 'delete', child: Text('Hapus bahan')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CostingLineDialog extends StatefulWidget {
  const _CostingLineDialog({
    required this.outletId,
    required this.productId,
    this.initial,
  });

  final String outletId;
  final String productId;
  final CostingComponent? initial;

  @override
  State<_CostingLineDialog> createState() => _CostingLineDialogState();
}

class _CostingLineDialogState extends State<_CostingLineDialog> {
  late final TextEditingController _name;
  late final TextEditingController _packageQuantity;
  late final TextEditingController _packagePrice;
  late final TextEditingController _recipeQuantity;
  late CostingUnit _packageUnit;
  late CostingUnit _recipeUnit;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.materialName ?? '');
    _packageQuantity = TextEditingController(
      text: initial == null ? '' : _number(initial.packageQuantity),
    );
    _packagePrice = TextEditingController(
      text: initial == null ? '' : _number(initial.packagePrice),
    );
    _recipeQuantity = TextEditingController(
      text: initial == null ? '' : _number(initial.recipeQuantity),
    );
    _packageUnit = initial?.packageUnit ?? CostingUnit.gram;
    _recipeUnit = initial?.recipeUnit ?? CostingUnit.gram;
  }

  @override
  void dispose() {
    _name.dispose();
    _packageQuantity.dispose();
    _packagePrice.dispose();
    _recipeQuantity.dispose();
    super.dispose();
  }

  void _submit() {
    final packageQuantity = _parse(_packageQuantity.text);
    final packagePrice = _parse(_packagePrice.text);
    final recipeQuantity = _parse(_recipeQuantity.text);
    if (_name.text.trim().isEmpty ||
        packageQuantity == null ||
        packageQuantity <= 0 ||
        packagePrice == null ||
        packagePrice < 0 ||
        recipeQuantity == null ||
        recipeQuantity <= 0) {
      setState(() => _error = 'Lengkapi nama, ukuran beli, harga, dan takaran resep.');
      return;
    }
    if (_packageUnit.family != _recipeUnit.family) {
      setState(() => _error = 'Satuan beli dan satuan resep harus satu jenis.');
      return;
    }
    Navigator.pop(
      context,
      CostingComponent(
        id: widget.initial?.id ?? const Uuid().v4(),
        outletId: widget.outletId,
        productId: widget.productId,
        materialName: _name.text.trim(),
        packageQuantity: packageQuantity,
        packageUnit: _packageUnit,
        packagePrice: packagePrice,
        recipeQuantity: recipeQuantity,
        recipeUnit: _recipeUnit,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Tambah bahan resep' : 'Edit bahan resep'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nama bahan', hintText: 'Contoh: Beans'),
            ),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Kemasan yang dibeli', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            Row(
              children: [
                Expanded(child: _numberField(_packageQuantity, 'Jumlah')),
                const SizedBox(width: 8),
                Expanded(child: _unitField(_packageUnit, (value) => setState(() => _packageUnit = value))),
              ],
            ),
            TextField(
              controller: _packagePrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [NormalizedNumberInputFormatter(allowDecimal: true)],
              decoration: const InputDecoration(labelText: 'Harga kemasan (Rp)', prefixText: 'Rp '),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Takaran untuk 1 porsi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            Row(
              children: [
                Expanded(child: _numberField(_recipeQuantity, 'Jumlah')),
                const SizedBox(width: 8),
                Expanded(child: _unitField(_recipeUnit, (value) => setState(() => _recipeUnit = value))),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _submit, child: const Text('Simpan bahan')),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [NormalizedNumberInputFormatter(allowDecimal: true)],
        decoration: InputDecoration(labelText: label),
      );

  Widget _unitField(CostingUnit value, ValueChanged<CostingUnit> onChanged) => DropdownButtonFormField<CostingUnit>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Satuan'),
        items: CostingUnit.values
            .map((unit) => DropdownMenuItem(value: unit, child: Text(unit.shortLabel)))
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      );
}

double? _parse(String value) => double.tryParse(value.trim().replaceAll(',', '.'));

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

String _money(double value) => 'Rp ${value.round().toString()}';
