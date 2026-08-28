/// Deterministic metrics used by the owner decision-support layer.
///
/// This file deliberately contains no Flutter, database, or Supabase code so
/// the same formulas can be used by the mobile dashboard, owner web dashboard,
/// and unit tests without changing the POS write path.
class OwnerMetricSnapshot {
  final double revenue;
  final double cogs;
  final double expenses;
  final int transactions;
  /// Share of sold item quantity with a trustworthy transaction-time HPP.
  /// A value below 1 means profitability metrics must be treated as partial.
  final double hppCoverageRatio;

  const OwnerMetricSnapshot({
    required this.revenue,
    required this.cogs,
    required this.expenses,
    required this.transactions,
    this.hppCoverageRatio = 0,
  });

  const OwnerMetricSnapshot.empty()
      : revenue = 0,
        cogs = 0,
        expenses = 0,
        transactions = 0,
        hppCoverageRatio = 0;

  double get estimatedGrossProfit => revenue - cogs;

  bool get hasReliableHpp => hppCoverageRatio >= 0.999999;

  double? get reliableEstimatedGrossProfit =>
      hasReliableHpp ? estimatedGrossProfit : null;

  /// This is an operational estimate, not accounting-level net profit.
  double get estimatedProfitAfterRecordedExpenses =>
      estimatedGrossProfit - expenses;

  double get averageOrderValue =>
      transactions > 0 ? _finite(revenue / transactions) : 0;

  double get grossMarginPercent =>
      revenue > 0 ? _finite(estimatedGrossProfit / revenue * 100) : 0;

  double? get reliableGrossMarginPercent =>
      hasReliableHpp && revenue > 0 ? grossMarginPercent : null;

  double get recordedExpenseRatioPercent =>
      revenue > 0 ? _finite(expenses / revenue * 100) : 0;

  OwnerMetricSnapshot operator +(OwnerMetricSnapshot other) =>
      OwnerMetricSnapshot(
        revenue: revenue + other.revenue,
        cogs: cogs + other.cogs,
        expenses: expenses + other.expenses,
        transactions: transactions + other.transactions,
        hppCoverageRatio: _weightedCoverage(this, other),
      );
}

class MetricChange {
  final double current;
  final double previous;

  const MetricChange({required this.current, required this.previous});

  bool get hasBaseline => previous != 0;

  double get delta => current - previous;

  double get percent => hasBaseline ? _finite(delta / previous * 100) : 0;

  bool get isIncrease => delta > 0;
  bool get isDecrease => delta < 0;
}

class OwnerMetricComparison {
  final OwnerMetricSnapshot current;
  final OwnerMetricSnapshot previous;

  const OwnerMetricComparison({
    required this.current,
    required this.previous,
  });

  MetricChange get revenue =>
      MetricChange(current: current.revenue, previous: previous.revenue);

  MetricChange get transactions => MetricChange(
        current: current.transactions.toDouble(),
        previous: previous.transactions.toDouble(),
      );

  MetricChange get averageOrderValue => MetricChange(
        current: current.averageOrderValue,
        previous: previous.averageOrderValue,
      );

  MetricChange get grossMarginPercent => MetricChange(
        current: current.grossMarginPercent,
        previous: previous.grossMarginPercent,
      );

  MetricChange get expenses =>
      MetricChange(current: current.expenses, previous: previous.expenses);
}

double _weightedCoverage(
  OwnerMetricSnapshot first,
  OwnerMetricSnapshot second,
) {
  final totalTransactions = first.transactions + second.transactions;
  if (totalTransactions <= 0) return 0;
  return _finite((first.hppCoverageRatio * first.transactions +
          second.hppCoverageRatio * second.transactions) /
      totalTransactions);
}

double _finite(double value) => value.isFinite ? value : 0;
