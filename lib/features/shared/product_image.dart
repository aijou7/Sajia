import 'dart:io';

import 'package:flutter/material.dart';

/// Displays both gallery-backed local images and remotely synced image URLs.
class ProductImage extends StatelessWidget {
  final String? source;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget fallback;

  const ProductImage({
    super.key,
    required this.source,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final rawSource = source?.trim();
    if (rawSource == null || rawSource.isEmpty) return fallback;

    if (_isLocalPath(rawSource)) {
      return Image.file(
        File(_toLocalPath(rawSource)),
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return Image.network(
      rawSource,
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  bool _isLocalPath(String value) {
    return value.startsWith('/') ||
        value.startsWith('file://') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  String _toLocalPath(String value) {
    if (!value.startsWith('file://')) return value;
    return Uri.parse(value).toFilePath();
  }
}
