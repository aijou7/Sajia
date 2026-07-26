import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/providers.dart';
import 'core/brand.dart';
import 'core/onboarding_service.dart';
import 'core/router.dart';
import 'core/theme.dart';

const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://dglykanljjzysglwllju.supabase.co',
);

const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_muNOtjPaEROhkExG6Dd1Vw_oQg4AUFo'),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Status bar transparan
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await initializeDateFormatting('id_ID');

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );

  runApp(const ProviderScope(child: SajiaApp()));
}

class SajiaApp extends ConsumerStatefulWidget {
  final bool startSyncOnLaunch;

  const SajiaApp({
    super.key,
    this.startSyncOnLaunch = true,
  });

  @override
  ConsumerState<SajiaApp> createState() => _SajiaAppState();
}

class _SajiaAppState extends ConsumerState<SajiaApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapAndStartSync();
    });
  }

  Future<void> _bootstrapAndStartSync() async {
    final outletId = await OnboardingService().getCurrentOutletId();
    if (!mounted) return;

    if (outletId != null && outletId.isNotEmpty) {
      ref.read(currentOutletIdProvider.notifier).state = outletId;
    }

    if (widget.startSyncOnLaunch) {
      ref.read(syncServiceProvider).start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return ScreenUtilInit(
      designSize: const Size(1024, 768),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: AppBrand.name,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.light,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          locale: const Locale('id', 'ID'),
        );
      },
    );
  }
}
