import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_mobile/core/providers.dart';
import 'package:pos_mobile/domain/entities/entities.dart';

void main() {
  const item = CartItem(
    productId: 'product-1',
    productName: 'Nasi Goreng',
    unitPrice: 50000,
    quantity: 2,
  );

  test('diskon persen dihitung sebelum pajak dan service', () {
    const cart = Cart(items: [item], discountPercent: 10);

    expect(cart.subtotal, 100000);
    expect(cart.discountValue, 10000);
    expect(cart.subtotalAfterDiscount, 90000);
    expect(cart.taxAmount(10), 9000);
    expect(cart.serviceChargeAmount(5), 4500);
    expect(cart.total(10, 5), 103500);
  });

  test('diskon tidak pernah membuat total menjadi negatif', () {
    const cart = Cart(items: [item], discountPercent: 250);

    expect(cart.discountValue, 100000);
    expect(cart.total(10, 5), 0);
  });

  test('notifier membatasi input diskon ke rentang 0 sampai 100', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(cartProvider.notifier).addItem(item);
    container.read(cartProvider.notifier).setDiscount(percent: 125);
    expect(container.read(cartProvider).discountPercent, 100);
    expect(container.read(cartProvider).discountValue, 100000);

    container.read(cartProvider.notifier).setDiscount(percent: -15);
    expect(container.read(cartProvider).discountPercent, 0);
    expect(container.read(cartProvider).discountValue, 0);
  });
}
