import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/providers.dart';
import 'package:pos_mobile/domain/entities/entities.dart';

void main() {
  test('cart quantity changes are observable and use current state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(cartProvider.notifier);
    notifier.addItem(
      const CartItem(
        productId: 'menu-1',
        productName: 'Nasi Goreng',
        unitPrice: 20000,
      ),
    );

    expect(container.read(cartProvider).items.single.quantity, 1);

    notifier.incrementQty(0);
    expect(container.read(cartProvider).items.single.quantity, 2);

    notifier.decrementQty(0);
    expect(container.read(cartProvider).items.single.quantity, 1);

    notifier.decrementQty(0);
    expect(container.read(cartProvider).items, isEmpty);
  });

  test('cart item equality includes quantity', () {
    const one = CartItem(
      productId: 'menu-1',
      productName: 'Nasi Goreng',
      unitPrice: 20000,
      quantity: 1,
    );
    const two = CartItem(
      productId: 'menu-1',
      productName: 'Nasi Goreng',
      unitPrice: 20000,
      quantity: 2,
    );

    expect(one, isNot(equals(two)));
    expect(const Cart(items: [one]), isNot(equals(const Cart(items: [two]))));
  });

  test('stock tracked cart item cannot exceed available stock', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(cartProvider.notifier);
    notifier.addItem(
      const CartItem(
        productId: 'menu-stock-1',
        productName: 'Ayam Geprek',
        unitPrice: 18000,
        trackStock: true,
        availableStock: 2,
      ),
    );

    notifier.incrementQty(0);
    notifier.incrementQty(0);
    notifier.addItem(
      const CartItem(
        productId: 'menu-stock-1',
        productName: 'Ayam Geprek',
        unitPrice: 18000,
        trackStock: true,
        availableStock: 2,
      ),
    );

    expect(container.read(cartProvider).items.single.quantity, 2);
  });
}
