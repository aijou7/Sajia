/// Keeps PIN keypad rows compact on wide tablets while preserving comfortable
/// touch targets on narrow phones.
double pinNumpadButtonSize(double availableWidth) {
  return (availableWidth / 3 - 18).clamp(48.0, 64.0).toDouble();
}
