import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/notification_service.dart';
import '../../core/numeric_input_formatter.dart';
import '../../core/print_service.dart';
import '../../data/local/app_database.dart';
import '../../data/local/daos/product_dao.dart';
import 'package:drift/drift.dart' show Value;

class PaymentSheet extends ConsumerStatefulWidget {
  const PaymentSheet({super.key});

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  String _method = 'cash';
  double _paidAmount = 0;
  bool _isProcessing = false;
  String? _validationMessage;
  final _paidController = TextEditingController();

  @override
  void dispose() {
    _paidController.dispose();
    super.dispose();
  }

  double get _total {
    final cart = ref.read(cartProvider);
    return cart.total(_taxPercent, _servicePercent);
  }

  double get _taxPercent {
    final outlet = ref.read(currentOutletProvider).value;
    return double.tryParse(outlet?.taxPercent ?? '0') ?? 0;
  }

  double get _servicePercent {
    final outlet = ref.read(currentOutletProvider).value;
    return double.tryParse(outlet?.serviceChargePercent ?? '0') ?? 0;
  }

  double get _change => (_paidAmount - _total).clamp(0, double.infinity);

  List<double> get _quickAmounts {
    final t = _total;
    final rounded = (t / 1000).ceil() * 1000;
    return [
      rounded,
      rounded + 5000,
      rounded + 10000,
      rounded + 20000,
    ].where((a) => a >= t).take(4).map((e) => e.toDouble()).toList();
  }

  bool _isValidPercentage(double? value) =>
      value != null && value.isFinite && value >= 0 && value <= 100;

  Future<void> _processPayment() async {
    final outlet = ref.read(currentOutletProvider).value;
    if (outlet == null) {
      setState(() {
        _validationMessage =
            'Pengaturan pajak dan service outlet belum selesai dimuat. '
            'Tunggu sebentar lalu coba lagi.';
      });
      return;
    }

    final taxPercent = double.tryParse(outlet.taxPercent);
    final servicePercent = double.tryParse(outlet.serviceChargePercent);
    if (!_isValidPercentage(taxPercent) ||
        !_isValidPercentage(servicePercent)) {
      setState(() {
        _validationMessage =
            'Pengaturan pajak atau service outlet tidak valid. '
            'Periksa Pengaturan Struk sebelum menerima pembayaran.';
      });
      return;
    }
    final appliedTaxPercent = taxPercent!;
    final appliedServicePercent = servicePercent!;

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      setState(() {
        _validationMessage =
            'Sesi kasir sudah berakhir. Masuk kembali sebelum pembayaran.';
      });
      return;
    }

    final initialCart = ref.read(cartProvider);
    if (initialCart.items.isEmpty ||
        initialCart.items.any(
          (item) => !item.quantity.isFinite || item.quantity <= 0,
        )) {
      setState(() {
        _validationMessage = 'Keranjang belum memiliki item yang valid.';
      });
      return;
    }

    final checkoutTotal =
        initialCart.total(appliedTaxPercent, appliedServicePercent);
    if (_method == 'cash' && _paidAmount < checkoutTotal) {
      setState(() {
        _validationMessage =
            'Uang bayar kurang ${(checkoutTotal - _paidAmount).toRupiah}.';
      });
      return;
    }

    setState(() {
      _validationMessage = null;
      _isProcessing = true;
    });

    var paymentCommitted = false;
    try {
      final cart = initialCart;
      final db = ref.read(databaseProvider);
      final user = currentUser;
      final outletId = ref.read(currentOutletIdProvider);
      const uuid = Uuid();

      final today = DateTime.now();
      final orderId = uuid.v4();
      final orderNum = IdGen.orderNumber(today.millisecond % 9999 + 1);

      final subtotal = cart.subtotal;
      final discountAmt = cart.discountValue;
      final taxAmt = cart.taxAmount(appliedTaxPercent);
      final serviceAmt = cart.serviceChargeAmount(appliedServicePercent);
      final total = cart.total(appliedTaxPercent, appliedServicePercent);
      final paidAmt = _method == 'cash' ? _paidAmount : total;
      final changeAmt = _method == 'cash'
          ? (_paidAmount - total).clamp(0.0, double.infinity).toDouble()
          : 0.0;
      final paidAt = DateTime.now();

      final itemLabels = cart.items
          .map((i) => '${i.quantity.toInt()}x ${i.productName}')
          .toList();

      // Order, item, stock, table, and the pending server stock movement must
      // commit together. A failure at any point rolls everything back so the
      // cashier can safely retry without creating a duplicate paid order.
      await db.transaction(() async {
        await db.orderDao.createOrder(OrdersCompanion.insert(
          id: orderId,
          outletId: outletId,
          orderNumber: orderNum,
          type: cart.orderType,
          status: 'paid',
          tableId: Value(cart.tableId),
          tableLabel: Value(cart.tableLabel),
          cashierId: user.id,
          cashierName: user.name,
          customerName: Value(cart.customerName),
          notes: Value(cart.notes),
          subtotal: Value(subtotal.toString()),
          discountAmount: Value(discountAmt.toString()),
          discountPercent: Value(cart.discountPercent.toString()),
          taxAmount: Value(taxAmt.toString()),
          serviceCharge: Value(serviceAmt.toString()),
          total: Value(total.toString()),
          paymentMethod: Value(_method),
          paidAmount: Value(paidAmt.toString()),
          changeAmount: Value(changeAmt.toString()),
          paidAt: Value(paidAt),
          isSynced: const Value(false),
        ));

        final quantitiesByProduct = <String, double>{};
        for (final item in cart.items) {
          await db.orderDao.addOrderItem(OrderItemsCompanion.insert(
            id: uuid.v4(),
            orderId: orderId,
            productId: item.productId,
            productName: item.productName,
            variantSummary: Value(item.variantSummary),
            unitPrice: item.unitPrice.toString(),
            unitCogs: Value(item.unitCogs.toString()),
            categoryId: Value(item.categoryId),
            categoryName: Value(item.categoryName),
            quantity: item.quantity.toString(),
            discount: Value(item.discount.toString()),
            subtotal: item.subtotal.toString(),
            notes: Value(item.notes),
          ));
          quantitiesByProduct.update(
            item.productId,
            (current) => current + item.quantity,
            ifAbsent: () => item.quantity,
          );
        }

        final stockItems = <Map<String, dynamic>>[];
        for (final entry in quantitiesByProduct.entries) {
          final wasTracked = await db.productDao.decrementStock(
            entry.key,
            entry.value,
          );
          if (wasTracked) {
            stockItems.add({
              'product_id': entry.key,
              'quantity': entry.value,
            });
          }
        }
        if (stockItems.isNotEmpty) {
          await db.syncDao.enqueue(
            tableName: 'stock_sales',
            recordId: orderId,
            operation: 'apply',
            payload: {
              'outlet_id': outletId,
              'order_id': orderId,
              'items': stockItems,
            },
          );
        }

        if (cart.tableId != null) {
          await (db.update(db.restaurantTables)
                ..where((table) => table.id.equals(cart.tableId!)))
              .write(
            RestaurantTablesCompanion(
              status: const Value('available'),
              currentOrderId: const Value(null),
              updatedAt: Value(DateTime.now()),
              isSynced: const Value(false),
            ),
          );
        }
      });
      paymentCommitted = true;

      // A local Android notification is auxiliary. It must never turn a
      // successfully committed sale into a visible payment failure.
      try {
        await NotificationService.sendKitchenOrder(
          orderNumber: orderNum,
          items: itemLabels,
        );
      } catch (_) {
        // The order remains valid and can still be printed/viewed in history.
      }

      // Ambil data outlet untuk receipt
      final outlet = await (db.select(db.outlets)
            ..where((o) => o.id.equals(outletId)))
          .getSingleOrNull();

      // Build receipt data
      final receiptData = ReceiptData(
        outletName: outlet?.name ?? AppBrand.name,
        outletAddress: outlet?.address,
        outletPhone: outlet?.phone,
        receiptHeader: outlet?.receiptHeader,
        receiptFooter: outlet?.receiptFooter,
        orderNumber: orderNum,
        tableLabel: cart.tableLabel,
        cashierName: user.name,
        paymentMethod: _method,
        items: cart.items
            .map((i) => ReceiptItem(
                  name: i.productName,
                  variantSummary: i.variantSummary,
                  quantity: i.quantity,
                  unitPrice: i.unitPrice,
                  subtotal: i.subtotal,
                ))
            .toList(),
        subtotal: subtotal,
        discountAmount: discountAmt,
        discountPercent: cart.discountPercent,
        taxAmount: taxAmt,
        serviceCharge: serviceAmt,
        total: total,
        paidAmount: paidAmt,
        changeAmount: changeAmt,
        paidAt: paidAt,
      );

      ref.read(cartProvider.notifier).clear();

      if (!mounted) return;
      Navigator.of(context).pop();
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted) return;
      _showSuccessDialog(total, changeAmt, orderNum, itemLabels, receiptData);
    } on StockValidationException catch (error) {
      if (!mounted) return;
      var productName = error.productId;
      for (final item in ref.read(cartProvider).items) {
        if (item.productId == error.productId) {
          productName = item.productName;
          break;
        }
      }
      setState(() {
        _validationMessage = error.productMissing
            ? '$productName sudah tidak tersedia.'
            : 'Stok $productName tersisa '
                '${_formatQuantity(error.available ?? 0)}, sedangkan pesanan '
                '${_formatQuantity(error.requested)}.';
      });
    } catch (e) {
      if (!mounted) return;
      if (paymentCommitted) {
        ref.read(cartProvider.notifier).clear();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pembayaran sudah tersimpan. Struk dapat dibuka dari Riwayat.',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
        return;
      }
      setState(() {
        _validationMessage = 'Pembayaran gagal disimpan. Coba lagi.';
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _formatQuantity(double value) {
    return value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Future<void> _doPrint(ReceiptData data, BuildContext dialogCtx) async {
    Navigator.pop(dialogCtx);

    if (!mounted) return;

    // Tampilkan loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Menghubungkan ke printer...'),
          ],
        ),
      ),
    );

    // Coba print dengan retry maksimal 2x
    PrintResult result = PrintResult.error;
    int attempts = 0;

    while (attempts < 2) {
      result = await PrintService().printReceipt(data);
      if (result.isSuccess) break;

      attempts++;
      if (attempts < 2) {
        // Disconnect dulu sebelum retry
        await PrintService().disconnectBluetooth();
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (!mounted) return;
    Navigator.pop(context); // tutup loading

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nota berhasil dicetak'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      // Gagal setelah retry — tawarin print ulang
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Gagal Mencetak'),
          content: Text(result.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _doPrint(data, ctx); // retry manual
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.action,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showSuccessDialog(double total, double change, String orderNum,
      List<String> items, ReceiptData receiptData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F9F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppTheme.success, size: 48),
            ),
            const SizedBox(height: 16),
            const Text('Pembayaran Berhasil!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(total.toRupiah,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary)),
            if (change > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      child: Text(
                        'Rp',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Kembalian: ${change.toRupiah}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFD97706))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Ringkasan nota
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #$orderNum',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280))),
                  const SizedBox(height: 4),
                  ...items.map((item) => Text('- $item',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF374151)))),
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          // Tombol Print Nota
          OutlinedButton.icon(
            onPressed: () => _doPrint(receiptData, ctx),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print Nota'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(130, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          // Tombol Selesai
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.action,
              minimumSize: const Size(130, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final outlet = ref.watch(currentOutletProvider).value;
    final parsedTax =
        outlet == null ? null : double.tryParse(outlet.taxPercent);
    final parsedService =
        outlet == null ? null : double.tryParse(outlet.serviceChargePercent);
    final pricingReady = outlet != null &&
        _isValidPercentage(parsedTax) &&
        _isValidPercentage(parsedService);
    final taxPercent = parsedTax ?? 0;
    final servicePercent = parsedService ?? 0;
    final total = cart.total(taxPercent, servicePercent);
    final submitDisabled = _isProcessing || !pricingReady;

    return Container(
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
        bottom: bottomSheetSafePadding(context, extra: 0),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Pembayaran',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.20),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total tagihan',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.74))),
                    const SizedBox(height: 6),
                    Text(total.toRupiah,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!pricingReady) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.hourglass_top_rounded,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Menunggu pengaturan pajak dan service outlet. '
                          'Pembayaran belum dapat dikonfirmasi.',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('Metode Pembayaran',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
              const SizedBox(height: 10),
              Row(
                children: [
                  _MethodCard(
                    icon: Icons.payments_outlined,
                    label: 'Tunai',
                    selected: _method == 'cash',
                    onTap: () => setState(() {
                      _method = 'cash';
                      _validationMessage = null;
                    }),
                  ),
                  const SizedBox(width: 10),
                  _MethodCard(
                    icon: Icons.qr_code_rounded,
                    label: 'QRIS Manual',
                    selected: _method == 'qris',
                    onTap: () => setState(() {
                      _method = 'qris';
                      _paidAmount = total;
                      _validationMessage = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_method == 'cash') ...[
                const Text('Uang Bayar',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280))),
                const SizedBox(height: 8),
                TextField(
                  controller: _paidController,
                  selectAllOnFocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    const NormalizedNumberInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    hintText: '0',
                    filled: true,
                    fillColor: const Color(0xFFFAFCFE),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppTheme.subtleBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppTheme.subtleBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _paidAmount = double.tryParse(v) ?? 0;
                      _validationMessage = null;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: _quickAmounts.map((amt) {
                    return GestureDetector(
                      onTap: () {
                        _paidController.text = amt.toInt().toString();
                        setState(() {
                          _paidAmount = amt;
                          _validationMessage = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          amt.toRupiahCompact,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_paidAmount >= total && _paidAmount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 22,
                          child: Text(
                            'Rp',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.success,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Kembalian: ${_change.toRupiah}',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
              if (_method == 'qris') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.info, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Gunakan QRIS statis milik outlet. Pembayaran ini '
                          'tidak diverifikasi otomatis. Konfirmasi hanya '
                          'setelah saldo benar-benar diterima.',
                          style: TextStyle(fontSize: 12, color: AppTheme.info),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (_validationMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppTheme.danger,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _validationMessage!,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                key: const ValueKey('payment-submit'),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: submitDisabled ? null : AppTheme.payGradient,
                  color: submitDisabled ? Colors.grey[300] : null,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: submitDisabled
                      ? null
                      : [
                          BoxShadow(
                            color: AppTheme.success.withValues(alpha: 0.24),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: submitDisabled ? null : _processPayment,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _method == 'qris'
                                    ? 'Saya Sudah Menerima Pembayaran'
                                    : 'Bayar ${total.toRupiah}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AppTheme.primaryLight
                  : const Color(0xFFFAFCFE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    widget.selected ? AppTheme.primary : AppTheme.subtleBorder,
                width: widget.selected ? 1.5 : 1,
              ),
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.13),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(widget.icon,
                    color: widget.selected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    size: 28),
                const SizedBox(height: 5),
                Text(widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          widget.selected ? FontWeight.w800 : FontWeight.w600,
                      color: widget.selected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
