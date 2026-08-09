import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/numeric_input_formatter.dart';

void main() {
  const integerFormatter = NormalizedNumberInputFormatter();
  const decimalFormatter = NormalizedNumberInputFormatter(allowDecimal: true);

  TextEditingValue value(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  test('replaces an initial zero when the user types an amount', () {
    final result = integerFormatter.formatEditUpdate(value('0'), value('05'));

    expect(result.text, '5');
    expect(result.selection.baseOffset, 1);
  });

  test('keeps a single zero and allows clearing the field', () {
    expect(
      integerFormatter.formatEditUpdate(value(''), value('0')).text,
      '0',
    );
    expect(
      integerFormatter.formatEditUpdate(value('0'), value('')).text,
      '',
    );
  });

  test('keeps the required zero before a decimal separator', () {
    final result = decimalFormatter.formatEditUpdate(value('0'), value('0.5'));

    expect(result.text, '0.5');
  });

  test('rejects non numeric input without altering the previous value', () {
    final result = integerFormatter.formatEditUpdate(value('12'), value('12a'));

    expect(result.text, '12');
  });
}
