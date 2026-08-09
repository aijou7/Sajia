import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/backup_service.dart';
import 'package:pos_mobile/data/local/app_database.dart';

void main() {
  test('manual restore keeps transaction and operational history', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.into(database.outlets).insert(
          OutletsCompanion.insert(
            id: 'outlet-1',
            name: 'Outlet Lama',
            licenseKey: 'FREE',
          ),
        );

    final now = DateTime.utc(2026, 8, 9, 3);
    final content = jsonEncode({
      'version': 2,
      'outlet_id': 'outlet-1',
      'outlet': {
        'name': 'Outlet Pulih',
        'address': 'Jl. Restore',
        'phone': null,
        'receipt_header': null,
        'receipt_footer': null,
        'tax_percent': '0',
        'service_charge_percent': '0',
      },
      'categories': <Object>[],
      'products': <Object>[],
      'product_variants': <Object>[],
      'users': <Object>[],
      'user_outlet_accesses': <Object>[],
      'tables': <Object>[],
      'orders': [
        {
          'id': 'order-1',
          'outlet_id': 'outlet-1',
          'order_number': 'TRX-001',
          'type': 'takeaway',
          'status': 'paid',
          'cashier_id': 'owner-1',
          'cashier_name': 'Owner',
          'subtotal': '15000',
          'total': '15000',
          'payment_method': 'cash',
          'paid_amount': '20000',
          'change_amount': '5000',
          'paid_at': now.toIso8601String(),
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
      ],
      'order_items': [
        {
          'id': 'item-1',
          'order_id': 'order-1',
          'product_id': 'product-deleted',
          'product_name': 'Produk Historis',
          'unit_price': '15000',
          'unit_cogs': '5000',
          'quantity': '1',
          'discount': '0',
          'subtotal': '15000',
          'status': 'served',
          'created_at': now.toIso8601String(),
        },
      ],
      'sessions': [
        {
          'id': 'session-1',
          'outlet_id': 'outlet-1',
          'cashier_id': 'owner-1',
          'cashier_name': 'Owner',
          'opening_cash': '100000',
          'closing_cash': '115000',
          'total_cash_sales': '15000',
          'total_qris_sales': '0',
          'total_orders': 1,
          'total_voids': 0,
          'opened_at': now.toIso8601String(),
          'closed_at': now.add(const Duration(hours: 8)).toIso8601String(),
        },
      ],
      'expenses': [
        {
          'id': 'expense-1',
          'outlet_id': 'outlet-1',
          'category': 'Operasional',
          'description': 'Gas',
          'amount': '30000',
          'occurred_at': now.toIso8601String(),
          'created_at': now.toIso8601String(),
        },
      ],
    });

    final result = await BackupService().restoreBackup(
      database,
      fileContent: content,
    );

    expect(result, BackupResult.success);
    expect((await database.select(database.outlets).getSingle()).name,
        'Outlet Pulih');
    expect(await database.select(database.orders).get(), hasLength(1));
    expect(await database.select(database.orderItems).get(), hasLength(1));
    expect(await database.select(database.sessions).get(), hasLength(1));
    expect(await database.select(database.expenses).get(), hasLength(1));
  });
}
