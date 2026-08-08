import 'dart:convert';

class ProductVariantOption {
  const ProductVariantOption({
    required this.name,
    this.priceDelta = 0,
  });

  final String name;
  final double priceDelta;
}

/// Parses the locally stored JSON option list while remaining compatible with
/// early builds that stored comma/newline separated text.
List<String> parseProductVariantOptions(String raw) {
  return parseProductVariantOptionDetails(raw)
      .map((option) => option.name)
      .toList(growable: false);
}

List<ProductVariantOption> parseProductVariantOptionDetails(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  Iterable<Object?> values;
  try {
    final decoded = jsonDecode(trimmed);
    values = decoded is List ? decoded : <Object?>[decoded];
  } catch (_) {
    values = trimmed.split(RegExp(r'[,\n]'));
  }

  final result = <ProductVariantOption>[];
  final seen = <String>{};
  for (final value in values) {
    String name;
    double priceDelta;
    if (value is Map) {
      name = (value['name'] ?? value['label'] ?? value['value'] ?? '')
          .toString()
          .trim();
      final rawDelta = value['price_delta'] ??
          value['priceDelta'] ??
          value['delta'] ??
          value['additional_price'];
      priceDelta = rawDelta is num
          ? rawDelta.toDouble()
          : double.tryParse(rawDelta?.toString() ?? '') ?? 0;
    } else {
      name = value?.toString().trim() ?? '';
      priceDelta = 0;
    }
    final key = name.toLowerCase();
    if (name.isEmpty || !seen.add(key)) continue;
    if (!priceDelta.isFinite || priceDelta < 0) priceDelta = 0;
    result.add(ProductVariantOption(name: name, priceDelta: priceDelta));
  }
  return result;
}

String encodeProductVariantOptions(Iterable<String> options) {
  return encodeProductVariantOptionDetails(
    options.map((option) => ProductVariantOption(name: option)),
  );
}

String encodeProductVariantOptionDetails(
  Iterable<ProductVariantOption> options,
) {
  final normalized = <Object>[];
  final seen = <String>{};
  for (final value in options) {
    final name = value.name.trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    final priceDelta = value.priceDelta.isFinite && value.priceDelta > 0
        ? value.priceDelta
        : 0.0;
    if (priceDelta == 0) {
      normalized.add(name);
    } else {
      normalized.add({
        'name': name,
        'price_delta': priceDelta == priceDelta.roundToDouble()
            ? priceDelta.toInt()
            : priceDelta,
      });
    }
  }
  return jsonEncode(normalized);
}

double totalVariantPriceDelta(
  Iterable<ProductVariantOption> selections,
) =>
    selections.fold<double>(
      0,
      (total, option) =>
          total +
          (option.priceDelta.isFinite && option.priceDelta > 0
              ? option.priceDelta
              : 0),
    );

String buildVariantSummary(
  Iterable<MapEntry<String, String>> selections,
) =>
    selections
        .where((entry) =>
            entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
        .map((entry) => '${entry.key.trim()}: ${entry.value.trim()}')
        .join(', ');
