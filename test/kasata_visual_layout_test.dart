import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_mobile/core/providers.dart';
import 'package:pos_mobile/core/theme.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/data/sync/sync_service.dart';
import 'package:pos_mobile/domain/entities/entities.dart';
import 'package:pos_mobile/features/shared/main_scaffold.dart';

class _Owner extends CurrentUserNotifier {
  @override
  AppUser build() => const AppUser(
      id: 'owner', name: 'Dina', role: 'owner', outletId: 'cafe');
}

class _SampleCart extends CartNotifier {
  @override
  Cart build() => const Cart(
        tableId: 'table-1',
        tableLabel: 'Meja teras depan 01',
        items: [
          CartItem(productId: 'coffee', productName: 'Kopi Susu Gula Aren',
              unitPrice: 20000, quantity: 2),
        ],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    final fonts = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
      fonts.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await fonts.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  for (final scenario in [
    (name: 'phone', size: const Size(390, 844), scale: 1.0),
    (name: 'small-tablet', size: const Size(800, 600), scale: 1.0),
    (name: 'tablet', size: const Size(1280, 800), scale: 1.0),
    (name: 'large-text', size: const Size(390, 844), scale: 1.3),
  ]) {
    testWidgets('cashier fits ${scenario.name} and filtering stays usable', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captureKey = GlobalKey();
      final now = DateTime(2026, 9, 28);
      final products = ['Kopi Susu Gula Aren', 'Americano', 'Croissant Butter', 'Matcha Latte']
          .indexed.map((entry) => Product(
                id: 'menu-${entry.$1}', outletId: 'cafe', categoryId: 'drinks',
                name: entry.$2, price: '20000', cogs: '7000',
                isAvailable: true, trackStock: true, stock: '20',
                lowStockAlert: '5', sortOrder: entry.$1, updatedAt: now, isSynced: true,
              )).toList();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(_Owner.new),
          cartProvider.overrideWith(_SampleCart.new),
          currentOutletProvider.overrideWith((ref) async => Outlet(
              id: 'cafe', name: 'Kedai Senja', taxPercent: '0',
              serviceChargePercent: '0', licenseKey: 'FREE', createdAt: now)),
          availableProductsProvider.overrideWith((ref) => Stream.value(products)),
          categoriesProvider.overrideWith((ref) => Stream.value([
                Category(id: 'drinks', outletId: 'cafe', name: 'Minuman',
                    sortOrder: 0, colorHex: '#F9D857', isActive: true,
                    updatedAt: now, isSynced: true),
              ])),
          scheduledPromotionsProvider.overrideWith((ref) => Stream.value([])),
          tablesProvider.overrideWith((ref) => Stream.value([])),
          promotionClockProvider.overrideWith((ref) => Stream.value(now)),
          syncStatusProvider.overrideWith((ref) => Stream.value(const SyncStatus())),
        ],
        child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scenario.scale)),
              child: child!,
            ),
            home: const MainScaffold(currentIndex: 0),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Kasata'), findsOneWidget);
      if (const bool.fromEnvironment('KASATA_VISUAL_REVIEW')) {
        await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/visual-review').create(recursive: true);
          await File('build/visual-review/${scenario.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('Minuman'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Americano');
      await tester.pumpAndSettle();
      expect(find.text('Americano', skipOffstage: true).evaluate()
          .where((element) => element.widget is Text), hasLength(1));
      expect(find.text('Matcha Latte'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
