import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/owner_web/owner_web_app.dart';

const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://dglykanljjzysglwllju.supabase.co',
);

const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_muNOtjPaEROhkExG6Dd1Vw_oQg4AUFo'),
);

/// Entry point khusus dashboard owner di browser.
///
/// Jangan menambahkan import kasir native (Drift/SQLite, printer Bluetooth,
/// path_provider, atau dart:io) pada dependency graph target ini.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );

  runApp(const OwnerWebApp());
}
