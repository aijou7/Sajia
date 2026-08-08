import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

Future<String?> uploadProductImage({
  required SupabaseClient client,
  required String outletId,
  required String productId,
  required String? source,
}) async {
  if (source == null || source.trim().isEmpty || source.startsWith('http')) {
    return source;
  }

  final file = File(source);
  if (!await file.exists()) {
    throw StateError('Foto produk lokal tidak ditemukan');
  }

  final extension = path.extension(source).toLowerCase();
  final safeExtension = {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
      ? extension
      : '.jpg';
  final contentType = switch (safeExtension) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    _ => 'image/jpeg',
  };
  final objectPath = '$outletId/$productId/primary$safeExtension';
  await client.storage.from('product-images').upload(
        objectPath,
        file,
        fileOptions: FileOptions(
          upsert: true,
          contentType: contentType,
          cacheControl: '3600',
        ),
      );
  return client.storage.from('product-images').getPublicUrl(objectPath);
}
