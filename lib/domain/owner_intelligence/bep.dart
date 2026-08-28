/// Safe, deterministic break-even calculations.
///
/// A result is invalid when the inputs cannot describe a positive contribution
/// margin. Callers should show the reason instead of rendering Infinity/NaN.
class BepInputs {
  final double fixedCosts;
  final double sellingPrice;
  final double variableCostPerUnit;

  const BepInputs({
    required this.fixedCosts,
    required this.sellingPrice,
    required this.variableCostPerUnit,
  });
}

class BepResult {
  final BepInputs inputs;
  final double contributionMarginPerUnit;
  final double contributionMarginRatio;
  final double? bepUnits;
  final double? bepRevenue;
  final String? invalidReason;

  const BepResult._({
    required this.inputs,
    required this.contributionMarginPerUnit,
    required this.contributionMarginRatio,
    required this.bepUnits,
    required this.bepRevenue,
    required this.invalidReason,
  });

  bool get isValid => invalidReason == null;

  factory BepResult.calculate(BepInputs inputs) {
    final fixed = _finiteNonNegative(inputs.fixedCosts);
    final price = _finiteNonNegative(inputs.sellingPrice);
    final variable = _finiteNonNegative(inputs.variableCostPerUnit);
    final contribution = price - variable;
    final ratio = price > 0 ? contribution / price : 0.0;
    final normalized = BepInputs(
      fixedCosts: fixed,
      sellingPrice: price,
      variableCostPerUnit: variable,
    );

    String? reason;
    if (fixed <= 0) {
      reason = 'Biaya tetap harus lebih besar dari nol.';
    } else if (price <= 0) {
      reason = 'Harga jual harus lebih besar dari nol.';
    } else if (contribution <= 0 || ratio <= 0) {
      reason = 'Margin kontribusi harus lebih besar dari nol.';
    }

    if (reason != null) {
      return BepResult._(
        inputs: normalized,
        contributionMarginPerUnit: _finite(contribution),
        contributionMarginRatio: _finite(ratio),
        bepUnits: null,
        bepRevenue: null,
        invalidReason: reason,
      );
    }

    final units = fixed / contribution;
    final revenue = fixed / ratio;
    if (!units.isFinite || !revenue.isFinite) {
      return BepResult._(
        inputs: normalized,
        contributionMarginPerUnit: _finite(contribution),
        contributionMarginRatio: _finite(ratio),
        bepUnits: null,
        bepRevenue: null,
        invalidReason: 'Input menghasilkan angka BEP yang tidak valid.',
      );
    }

    return BepResult._(
      inputs: normalized,
      contributionMarginPerUnit: contribution,
      contributionMarginRatio: ratio,
      bepUnits: units,
      bepRevenue: revenue,
      invalidReason: null,
    );
  }
}

class BepProgress {
  final double actualRevenue;
  final double bepRevenue;
  final int elapsedDays;
  final int totalDays;

  const BepProgress({
    required this.actualRevenue,
    required this.bepRevenue,
    required this.elapsedDays,
    required this.totalDays,
  });

  int get _safeTotalDays => totalDays > 0 ? totalDays : 0;

  double get _safeActualRevenue => _finiteNonNegative(actualRevenue);

  double get _safeBepRevenue => _finiteNonNegative(bepRevenue);

  int get safeElapsedDays => elapsedDays.clamp(0, _safeTotalDays).toInt();

  int get daysRemaining =>
      (_safeTotalDays - safeElapsedDays).clamp(0, _safeTotalDays).toInt();

  double get progressRatio {
    if (_safeBepRevenue <= 0) return 0;
    return _finite(
        (_safeActualRevenue / _safeBepRevenue).clamp(0, 1).toDouble());
  }

  double get currentDailyAverage =>
      safeElapsedDays > 0 ? _finite(_safeActualRevenue / safeElapsedDays) : 0;

  double get requiredDailyRevenue {
    final remaining = _safeBepRevenue - _safeActualRevenue;
    if (remaining <= 0 || daysRemaining == 0) return 0;
    return _finite(remaining / daysRemaining);
  }

  double get projectedEndRevenue =>
      _finite(_safeActualRevenue + currentDailyAverage * daysRemaining);

  double get projectedBepGap =>
      _finite((_safeBepRevenue - projectedEndRevenue)
          .clamp(0, double.infinity)
          .toDouble());
}

double _finiteNonNegative(double value) =>
    value.isFinite && value > 0 ? value : 0;

double _finite(double value) => value.isFinite ? value : 0;
