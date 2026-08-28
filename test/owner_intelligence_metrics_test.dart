import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/domain/owner_intelligence/bep.dart';
import 'package:pos_mobile/domain/owner_intelligence/owner_metrics.dart';

void main() {
  group('OwnerMetricSnapshot', () {
    test('calculates operational metrics deterministically', () {
      const snapshot = OwnerMetricSnapshot(
        revenue: 1_000_000,
        cogs: 400_000,
        expenses: 100_000,
        transactions: 40,
      );

      expect(snapshot.averageOrderValue, 25_000);
      expect(snapshot.estimatedGrossProfit, 600_000);
      expect(snapshot.estimatedProfitAfterRecordedExpenses, 500_000);
      expect(snapshot.grossMarginPercent, 60);
      expect(snapshot.recordedExpenseRatioPercent, 10);
      expect(snapshot.reliableGrossMarginPercent, isNull);

      const covered = OwnerMetricSnapshot(
        revenue: 1_000_000,
        cogs: 400_000,
        expenses: 100_000,
        transactions: 40,
        hppCoverageRatio: 1,
      );
      expect(covered.reliableEstimatedGrossProfit, 600_000);
      expect(covered.reliableGrossMarginPercent, 60);
    });

    test('returns safe zero values when there are no transactions', () {
      const snapshot = OwnerMetricSnapshot.empty();

      expect(snapshot.averageOrderValue, 0);
      expect(snapshot.grossMarginPercent, 0);
      expect(snapshot.recordedExpenseRatioPercent, 0);
    });

    test('compares AOV and revenue against a previous period', () {
      const comparison = OwnerMetricComparison(
        current: OwnerMetricSnapshot(
          revenue: 1_200_000,
          cogs: 480_000,
          expenses: 100_000,
          transactions: 48,
        ),
        previous: OwnerMetricSnapshot(
          revenue: 1_000_000,
          cogs: 400_000,
          expenses: 100_000,
          transactions: 40,
        ),
      );

      expect(comparison.revenue.percent, 20);
      expect(comparison.transactions.percent, 20);
      expect(comparison.averageOrderValue.percent, 0);
      expect(comparison.revenue.isIncrease, isTrue);
    });

    test('does not invent a percent change without a baseline', () {
      const comparison = OwnerMetricComparison(
        current: const OwnerMetricSnapshot(
          revenue: 100,
          cogs: 20,
          expenses: 0,
          transactions: 2,
        ),
        previous: const OwnerMetricSnapshot.empty(),
      );

      expect(comparison.revenue.hasBaseline, isFalse);
      expect(comparison.revenue.percent, 0);
    });
  });

  group('BepResult', () {
    test('calculates BEP units and revenue', () {
      final result = BepResult.calculate(const BepInputs(
        fixedCosts: 10_000_000,
        sellingPrice: 25_000,
        variableCostPerUnit: 10_000,
      ));

      expect(result.isValid, isTrue);
      expect(result.contributionMarginPerUnit, 15_000);
      expect(result.contributionMarginRatio, closeTo(.6, 0.0001));
      expect(result.bepUnits, closeTo(666.6667, 0.0001));
      expect(result.bepRevenue, closeTo(16_666_666.6667, 0.01));
    });

    test('rejects zero or negative contribution margin safely', () {
      final result = BepResult.calculate(const BepInputs(
        fixedCosts: 10_000_000,
        sellingPrice: 10_000,
        variableCostPerUnit: 10_000,
      ));

      expect(result.isValid, isFalse);
      expect(result.bepUnits, isNull);
      expect(result.bepRevenue, isNull);
      expect(result.invalidReason, contains('Margin kontribusi'));
    });

    test('projects remaining BEP requirement without Infinity', () {
      const progress = BepProgress(
        actualRevenue: 26_750_000,
        bepRevenue: 35_000_000,
        elapsedDays: 24,
        totalDays: 31,
      );

      expect(progress.daysRemaining, 7);
      expect(progress.progressRatio, closeTo(.7642857, 0.0001));
      expect(progress.currentDailyAverage, closeTo(1_114_583.33, .01));
      expect(progress.requiredDailyRevenue, closeTo(1_178_571.43, .01));
      expect(progress.projectedEndRevenue, closeTo(34_552_083.33, .01));
      expect(progress.projectedBepGap, closeTo(447_916.67, .01));
    });

    test('returns zero required revenue after reaching BEP', () {
      const progress = BepProgress(
        actualRevenue: 40,
        bepRevenue: 35,
        elapsedDays: 2,
        totalDays: 3,
      );

      expect(progress.requiredDailyRevenue, 0);
      expect(progress.projectedBepGap, 0);
    });

    test('normalizes invalid revenue and day inputs safely', () {
      const progress = BepProgress(
        actualRevenue: -10,
        bepRevenue: 100,
        elapsedDays: 10,
        totalDays: 0,
      );

      expect(progress.daysRemaining, 0);
      expect(progress.currentDailyAverage, 0);
      expect(progress.requiredDailyRevenue, 0);
      expect(progress.projectedBepGap, 100);
    });
  });
}
