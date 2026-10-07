import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_mobile/domain/costing.dart';
import 'package:pos_mobile/core/theme.dart';
import 'package:pos_mobile/core/app_notice.dart';
import 'package:pos_mobile/domain/ingredient_inventory.dart';
import 'package:pos_mobile/features/menu/hpp_calculator.dart';
import 'package:pos_mobile/features/owner_web/owner_inventory_panel.dart';
import 'package:pos_mobile/features/owner_web/owner_operations_page.dart';

bool _operationsMode = false;
bool _failLoad = false;
List<Map<String, dynamic>> _menuRows = [];
final _rpcCalls = <Map<String, dynamic>>[];
String? _nextRpcError;
Completer<void>? _rpcWait;

final _tables = <String, List<Map<String, dynamic>>>{
  'ingredients': [
    {
      'id': 'beans',
      'name': 'Beans Arabica Robusta',
      'unit': 'gram',
      'quantity': 1000,
      'unit_cost': 190,
      'updated_at': '2026-10-07T01:00:00.123456Z',
    }
  ],
  'ingredient_purchases': [
    {
      'id': 'buy',
      'occurred_at': '2026-10-07T01:00:00Z',
      'total': 190000,
      'items': [
        {'name': 'Beans', 'quantity': 1, 'unit': 'kilogram', 'price': 190000}
      ]
    }
  ],
  'internal_material_usage': [],
  'ingredient_movements': [],
  'ingredient_depletions': [],
  'products': [
    {'id': 'coffee', 'name': 'Kopi Susu', 'cogs': '5000'}
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('id_ID');
    final fonts = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await Supabase.initialize(
        url: 'https://inventory-test.supabase.co',
        publishableKey: 'test-key',
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false, detectSessionInUri: false),
        httpClient: MockClient((request) async {
          final table = request.url.pathSegments.last;
          if (request.url.path.contains('/rpc/')) {
            _rpcCalls.add({
              'rpc': table,
              ...jsonDecode(request.body) as Map<String, dynamic>
            });
            if (_rpcWait != null) await _rpcWait!.future;
            final error = _nextRpcError;
            _nextRpcError = null;
            if (error != null) {
              return http.Response(
                  jsonEncode({'code': 'P0001', 'message': error}), 400,
                  request: request,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response('true', 200,
                request: request,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(
              jsonEncode(_failLoad
                  ? {'code': 'SERVER_ERROR', 'message': 'test failure'}
                  : _operationsMode
                      ? table == 'products'
                          ? _menuRows
                          : []
                      : _tables[table] ?? []),
              _failLoad ? 500 : 200,
              request: request,
              headers: {'content-type': 'application/json'});
        }));
  });
  setUp(() {
    _operationsMode = false;
    _failLoad = false;
    _rpcCalls.clear();
    _menuRows = [];
    _nextRpcError = null;
    _rpcWait = null;
    _tables['ingredients']!.single['quantity'] = 1000;
  });
  tearDownAll(() async => Supabase.instance.dispose());
  tearDown(AppNotice.dismiss);
  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('inventory controls and reports render at $size',
        (tester) async {
      tester.view.resetPhysicalSize();
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final capture = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
              key: capture,
              child: Scaffold(
                  body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: OwnerInventoryPanel(
                          outletId: 'a', onChanged: () {}))))));
      await tester.pumpAndSettle();
      expect(find.text('Beans Arabica Robusta'), findsOneWidget);
      if (const bool.fromEnvironment('KASATA_VISUAL_REVIEW')) {
        await tester.runAsync(() async {
          final boundary = capture.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/visual-review').create(recursive: true);
          await File('build/visual-review/inventory-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Laporan belanja'));
      await tester.tap(find.text('Laporan belanja'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Beans ·'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Tambah bahan'));
      await tester.tap(find.text('Tambah bahan'));
      await tester.pumpAndSettle();
      expect(find.text('Nama bahan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      AppNotice.dismiss();
      await tester.ensureVisible(find.text('Catat belanja'));
      await tester.tap(find.text('Catat belanja'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '1000');
      await tester.enterText(find.byType(TextField).at(1), '190000');
      await tester.ensureVisible(find.text('Simpan belanja'));
      await tester.tap(find.text('Simpan belanja'));
      await tester.pumpAndSettle();
      expect(_rpcCalls.single['rpc'], 'record_ingredient_purchase');
      expect((_rpcCalls.single['p_items'] as List).single['quantity'], 1000);
      await tester.ensureVisible(find.text('Catat pemakaian'));
      await tester.tap(find.text('Catat pemakaian'));
      await tester.pumpAndSettle();
      expect(find.text('Pemakaian tanpa pembayaran'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      AppNotice.dismiss();
    });
  }
  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
        'previous sale and personal depletion require confirmation at $size',
        (tester) async {
      final capture = GlobalKey();
      await _pumpInventory(tester, size, capture: capture);
      await tester
          .ensureVisible(find.widgetWithText(TextButton, 'Bahan habis'));
      await tester.tap(find.widgetWithText(TextButton, 'Bahan habis'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Konfirmasi habis'))
              .onPressed,
          isNull);
      await _chooseDialogPurpose(tester, 'Pakai sendiri');
      expect(find.textContaining('Beban operasional bertambah Rp 190.000'),
          findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Konfirmasi habis'))
              .onPressed,
          isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _capture(tester, capture, 'depletion-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(_rpcCalls, isEmpty);
      await tester
          .ensureVisible(find.widgetWithText(OutlinedButton, 'Catat pemakaian'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Catat pemakaian'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '12');
      await _chooseDialogPurpose(tester, 'Penjualan sebelumnya');
      final save =
          find.widgetWithText(FilledButton, 'Catat penjualan sebelumnya');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.ensureVisible(find.textContaining('Tanggal penjualan:'));
      await tester.tap(find.textContaining('Tanggal penjualan:'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _capture(tester, capture, 'previous-sale-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(_rpcCalls.single['rpc'], 'record_previous_sale_material_usage');
      expect((_rpcCalls.single['p_items'] as List).single['quantity'], 12);
      expect(_rpcCalls.single['p_untracked_confirmed'], true);
      expect(_rpcCalls.single.containsKey('p_purpose'), false);
      expect(find.byType(AlertDialog), findsNothing);
      AppNotice.dismiss();
    });
  }
  testWidgets(
      'depletion retry keeps exact request and blocks double submission',
      (tester) async {
    await _pumpInventory(tester, const Size(1280, 900));
    await tester.tap(find.widgetWithText(TextButton, 'Bahan habis'));
    await tester.pumpAndSettle();
    await _chooseDialogPurpose(tester, 'Terbuang / selisih stok');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.enterText(find.byType(TextField), 'Rusak');
    await tester.pumpAndSettle();
    _nextRpcError = 'connection uncertain';
    _rpcWait = Completer<void>();
    await tester.tap(find.text('Konfirmasi habis'));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Menyimpan…'))
            .onPressed,
        isNull);
    await tester.pump();
    expect(_rpcCalls.length, 1);
    _rpcWait!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(find.textContaining('Belum dapat menyimpan'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(_rpcCalls.length, 2);
    expect(_rpcCalls[1], _rpcCalls[0]);
    expect(
        _rpcCalls[0]['p_expected_updated_at'], '2026-10-07T01:00:00.123456Z');
    expect(find.byType(AlertDialog), findsNothing);
    AppNotice.dismiss();
  });
  testWidgets('stale depletion reports reload and never claims saved',
      (tester) async {
    await _pumpInventory(tester, const Size(1280, 900));
    await tester.tap(find.widgetWithText(TextButton, 'Bahan habis'));
    await tester.pumpAndSettle();
    await _chooseDialogPurpose(tester, 'Penjualan sebelum tracking');
    expect(find.textContaining('tanpa beban operasional tambahan'),
        findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    _nextRpcError = 'INGREDIENT_STOCK_CHANGED_RELOAD';
    await tester.tap(find.text('Konfirmasi habis'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stok atau harga bahan sudah berubah'),
        findsOneWidget);
    expect(find.text('Pencatatan tersimpan.'), findsNothing);
    expect(_rpcCalls.single['p_purpose'], 'pre_tracking_sales');
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
  });
  for (final quantity in [0, -20]) {
    testWidgets('depletion disabled for stock $quantity', (tester) async {
      _tables['ingredients']!.single['quantity'] = quantity;
      await _pumpInventory(tester, const Size(1280, 900));
      expect(
          tester
              .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Bahan habis'))
              .onPressed,
          isNull);
    });
  }
  testWidgets('previous sale retry keeps stable recipe correction request',
      (tester) async {
    await _pumpInventory(tester, const Size(1280, 900));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Catat pemakaian'));
    await tester.pumpAndSettle();
    await _chooseDialogPurpose(tester, 'Penjualan sebelumnya');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    _nextRpcError = 'LINKED_RECIPE_REQUIRED';
    await tester.tap(find.text('Catat penjualan sebelumnya'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Hubungkan bahan baku di resep'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled, false);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(_rpcCalls[1], _rpcCalls[0]);
    AppNotice.dismiss();
  });
  testWidgets('menu refresh retains data, skips dialogs and cancels timer',
      (tester) async {
    _operationsMode = true;
    _menuRows = [
      {'id': 'coffee', 'name': 'Kopi Susu', 'price': '20000'}
    ];
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
            body: OwnerOperationsPage(outlets: [
          OwnerOutletOption(id: 'a', name: 'Outlet A', isCloud: true)
        ]))));
    await tester.pumpAndSettle();
    expect(find.text('Kopi Susu'), findsOneWidget);
    _menuRows = [
      ..._menuRows,
      {'id': 'new', 'name': 'Menu dari tablet', 'price': '18000'}
    ];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Menu dari tablet'), findsOneWidget);
    _failLoad = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Menu dari tablet'), findsOneWidget);
    expect(find.textContaining('Penyegaran otomatis belum berhasil'),
        findsOneWidget);
    _failLoad = false;
    await tester.ensureVisible(find.text('Tambah kategori'));
    await tester.tap(find.text('Tambah kategori'));
    await tester.pumpAndSettle();
    _menuRows = [
      ..._menuRows,
      {'id': 'later', 'name': 'Tunda saat mengedit'}
    ];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Tunda saat mengedit'), findsNothing);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Tunda saat mengedit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('recipe picks stored ingredient and needs only portion quantity',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: HppCalculatorSheet(
                outletId: 'a',
                productId: 'coffee',
                initial: [],
                ingredients: [
          Ingredient(
              id: 'beans',
              name: 'Beans',
              unit: CostingUnit.gram,
              quantity: 1000,
              unitCost: 190)
        ]))));
    await tester.tap(find.byTooltip('Tambah bahan'));
    await tester.pumpAndSettle();
    expect(find.text('Kemasan yang dibeli'), findsNothing);
    expect(find.text('Bahan baku tersimpan'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '18');
    await tester.tap(find.text('Simpan bahan'));
    await tester.pumpAndSettle();
    expect(find.text('Beans'), findsOneWidget);
    expect(find.text('Rp 3420'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow dashboard menu deletion requires confirmation',
      (tester) async {
    _operationsMode = true;
    _menuRows = [
      {'id': 'coffee', 'name': 'Kopi Susu Gula Aren', 'price': '20000'}
    ];
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
            body: OwnerOperationsPage(outlets: [
          OwnerOutletOption(id: 'a', name: 'Outlet A', isCloud: true)
        ]))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Hapus menu'));
    await tester.tap(find.byTooltip('Hapus menu'));
    await tester.pumpAndSettle();
    expect(_rpcCalls, isEmpty);
    expect(find.text('Hapus menu?'), findsOneWidget);
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(_rpcCalls.single['rpc'], 'delete_owner_menu_entity');
    expect(_rpcCalls.single['p_kind'], 'product');
    expect(_rpcCalls.single['p_outlet_id'], 'a');
    expect(_rpcCalls.single['p_id'], 'coffee');
    expect(tester.takeException(), isNull);
    AppNotice.dismiss();
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _pumpInventory(WidgetTester tester, Size size,
    {GlobalKey? capture}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(RepaintBoundary(
      key: capture,
      child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child:
                      OwnerInventoryPanel(outletId: 'a', onChanged: () {}))))));
  await tester.pumpAndSettle();
}

Future<void> _chooseDialogPurpose(WidgetTester tester, String label) async {
  final picker = find
      .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButtonFormField<String>))
      .last;
  await tester.ensureVisible(picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _capture(
    WidgetTester tester, GlobalKey capture, String name) async {
  if (!const bool.fromEnvironment('KASATA_VISUAL_REVIEW')) return;
  await tester.runAsync(() async {
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/visual-review').create(recursive: true);
    await File('build/visual-review/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
