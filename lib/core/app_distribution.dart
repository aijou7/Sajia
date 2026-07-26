class AppDistribution {
  static const channel = String.fromEnvironment(
    'SAJIA_DISTRIBUTION',
    defaultValue: 'direct',
  );

  static const isPlayStore = channel == 'play';
}
