import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/app_tables.dart';

part 'finance_dao.g.dart';

class FinanceSummary {
  final String outletId;
  final String outletName;
  final double revenue;
  final double cogs;
  final double expenses;
  final int transactions;

  const FinanceSummary({
    required this.outletId,
    required this.outletName,
    required this.revenue,
    required this.cogs,
    required this.expenses,
    required this.transactions,
  });

  double get grossProfit => revenue - cogs;
  double get netProfit => grossProfit - expenses;
  double get margin => revenue == 0 ? 0 : netProfit / revenue * 100;
}

@DriftAccessor(tables: [Outlets, Orders, OrderItems, Products, Expenses])
class FinanceDao extends DatabaseAccessor<AppDatabase> with _$FinanceDaoMixin {
  FinanceDao(super.db);

  Future<void> addExpense(ExpensesCompanion expense) =>
      into(expenses).insert(expense);

  Future<void> upsertExpense(ExpensesCompanion expense) =>
      into(expenses).insertOnConflictUpdate(expense);

  Future<List<Expense>> getUnsyncedExpenses() =>
      (select(expenses)..where((expense) => expense.isSynced.equals(false)))
          .get();

  Future<void> markExpenseSynced(String id) =>
      (update(expenses)..where((expense) => expense.id.equals(id)))
          .write(const ExpensesCompanion(isSynced: Value(true)));

  Future<int> deleteExpense(String id) =>
      (delete(expenses)..where((expense) => expense.id.equals(id))).go();

  Future<List<Expense>> getExpenses(
    String outletId,
    DateTime from,
    DateTime to,
  ) =>
      (select(expenses)
            ..where((e) =>
                e.outletId.equals(outletId) &
                e.occurredAt.isBetweenValues(from, to))
            ..orderBy([(e) => OrderingTerm.desc(e.occurredAt)]))
          .get();

  Future<List<FinanceSummary>> getBranchSummaries(
    DateTime from,
    DateTime to,
  ) async {
    final allOutlets = await select(outlets).get();
    final realOutlets = allOutlets
        .where((outlet) =>
            outlet.id != 'default-outlet' ||
            outlet.name.trim().toLowerCase() != 'nama kafe saya')
        .toList();
    final visibleOutlets = realOutlets.isEmpty ? allOutlets : realOutlets;
    return getBranchSummariesForOutlets(
      visibleOutlets.map((outlet) => outlet.id).toList(),
      from,
      to,
      outletNames: {
        for (final outlet in visibleOutlets) outlet.id: outlet.name
      },
    );
  }

  Future<List<FinanceSummary>> getBranchSummariesForOutlets(
    List<String> outletIds,
    DateTime from,
    DateTime to, {
    Map<String, String>? outletNames,
  }) async {
    if (outletIds.isEmpty) return [];
    final names = outletNames ??
        {
          for (final outlet in await (select(outlets)
                ..where((outlet) => outlet.id.isIn(outletIds)))
              .get())
            outlet.id: outlet.name,
        };
    final result = <FinanceSummary>[];
    for (final outletId in outletIds.toSet()) {
      result.add(await getOutletSummary(
        outletId,
        from,
        to,
        names[outletId] ?? 'Outlet',
      ));
    }
    result.sort((a, b) => b.revenue.compareTo(a.revenue));
    return result;
  }

  Future<FinanceSummary> getOutletSummary(
    String outletId,
    DateTime from,
    DateTime to, [
    String? outletName,
  ]) async {
    final paidOrders = await (select(orders)
          ..where((o) =>
              o.outletId.equals(outletId) &
              o.status.equals('paid') &
              o.paidAt.isBetweenValues(from, to)))
        .get();
    final orderIds = paidOrders.map((o) => o.id).toList();
    final revenue = paidOrders.fold<double>(
      0,
      (sum, order) => sum + (double.tryParse(order.total) ?? 0),
    );
    double cogs = 0;
    if (orderIds.isNotEmpty) {
      final paidItems = await (select(orderItems)
            ..where((item) => item.orderId.isIn(orderIds)))
          .get();
      final productList = await (select(products)
            ..where((product) => product.outletId.equals(outletId)))
          .get();
      final productCogs = {
        for (final product in productList)
          product.id: double.tryParse(product.cogs) ?? 0,
      };
      for (final item in paidItems) {
        final snapshottedCogs = item.unitCogs == null
            ? productCogs[item.productId] ?? 0
            : double.tryParse(item.unitCogs!) ?? 0;
        cogs += snapshottedCogs * (double.tryParse(item.quantity) ?? 0);
      }
    }
    final expenseRows = await getExpenses(outletId, from, to);
    final expenseTotal = expenseRows.fold<double>(
      0,
      (sum, expense) => sum + (double.tryParse(expense.amount) ?? 0),
    );
    return FinanceSummary(
      outletId: outletId,
      outletName: outletName ?? 'Outlet',
      revenue: revenue,
      cogs: cogs,
      expenses: expenseTotal,
      transactions: paidOrders.length,
    );
  }

  Future<List<FinanceSummary>> getDailySummaries(
    DateTime from,
    DateTime to,
  ) async {
    final days = <FinanceSummary>[];
    for (var day = DateTime(from.year, from.month, from.day);
        !day.isAfter(to);
        day = day.add(const Duration(days: 1))) {
      final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
      final branches = await getBranchSummaries(day, end);
      days.add(FinanceSummary(
        outletId: day.toIso8601String(),
        outletName: '${day.day}/${day.month}',
        revenue: branches.fold(0, (sum, branch) => sum + branch.revenue),
        cogs: branches.fold(0, (sum, branch) => sum + branch.cogs),
        expenses: branches.fold(0, (sum, branch) => sum + branch.expenses),
        transactions:
            branches.fold(0, (sum, branch) => sum + branch.transactions),
      ));
    }
    return days;
  }

  Future<List<FinanceSummary>> getDailySummariesForOutlet(
    String outletId,
    String outletName,
    DateTime from,
    DateTime to,
  ) async {
    final days = <FinanceSummary>[];
    for (var day = DateTime(from.year, from.month, from.day);
        !day.isAfter(to);
        day = day.add(const Duration(days: 1))) {
      final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
      final summary = await getOutletSummary(outletId, day, end, outletName);
      days.add(FinanceSummary(
        outletId: day.toIso8601String(),
        outletName: '${day.day}/${day.month}',
        revenue: summary.revenue,
        cogs: summary.cogs,
        expenses: summary.expenses,
        transactions: summary.transactions,
      ));
    }
    return days;
  }

  Future<List<FinanceSummary>> getDailySummariesForOutlets(
    List<String> outletIds,
    DateTime from,
    DateTime to,
  ) async {
    final days = <FinanceSummary>[];
    for (var day = DateTime(from.year, from.month, from.day);
        !day.isAfter(to);
        day = day.add(const Duration(days: 1))) {
      final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
      final branches = await getBranchSummariesForOutlets(outletIds, day, end);
      days.add(FinanceSummary(
        outletId: day.toIso8601String(),
        outletName: '${day.day}/${day.month}',
        revenue: branches.fold(0, (sum, branch) => sum + branch.revenue),
        cogs: branches.fold(0, (sum, branch) => sum + branch.cogs),
        expenses: branches.fold(0, (sum, branch) => sum + branch.expenses),
        transactions:
            branches.fold(0, (sum, branch) => sum + branch.transactions),
      ));
    }
    return days;
  }
}
