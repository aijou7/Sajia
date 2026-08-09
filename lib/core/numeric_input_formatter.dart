import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Keeps numeric fields friendly when their stored value starts at zero.
///
/// Typing `5` into a field that currently contains `0` becomes `5`, not `05`.
/// PIN, OTP, phone and other identifiers must not use this formatter because
/// their leading zeroes are meaningful.
class NormalizedNumberInputFormatter extends TextInputFormatter {
  const NormalizedNumberInputFormatter({this.allowDecimal = false});

  final bool allowDecimal;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final raw = newValue.text;
    final valid = allowDecimal
        ? RegExp(r'^\d*(?:[\.,]\d*)?$').hasMatch(raw)
        : RegExp(r'^\d*$').hasMatch(raw);
    if (!valid) return oldValue;

    final separatorIndex = raw.indexOf(RegExp(r'[\.,]'));
    final integerPart =
        separatorIndex < 0 ? raw : raw.substring(0, separatorIndex);
    final decimalPart = separatorIndex < 0 ? '' : raw.substring(separatorIndex);
    final normalizedInteger = integerPart.length <= 1
        ? integerPart
        : integerPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final normalized = '$normalizedInteger$decimalPart';
    if (normalized == raw) return newValue;

    final removed = raw.length - normalized.length;
    final offset = math.max(0, newValue.selection.extentOffset - removed);
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}
