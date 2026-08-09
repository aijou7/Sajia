import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/domain/entities/entities.dart';

AppUser _user(String role) => AppUser(
      id: '$role-user',
      name: role,
      role: role,
      outletId: 'outlet-1',
    );

void main() {
  test('cashier can view sales history but cannot void transactions', () {
    final cashier = _user('cashier');

    expect(cashier.canViewSalesHistory, isTrue);
    expect(cashier.canVoidTransactions, isFalse);
    expect(cashier.canViewFinancialReports, isFalse);
  });

  test('manager and owner can void transactions', () {
    expect(_user('manager').canVoidTransactions, isTrue);
    expect(_user('owner').canVoidTransactions, isTrue);
  });
}
