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
import 'features/shared/startup_splash.dart';

const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://dglykanljjzysglwllju.supabase.co',
);

const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_muNOtjPaEROhkExG6Dd1Vw_oQg4AUFo'),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Status bar transparan
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const ProviderScope(child: SajiaBootstrap()));
}

bool _supabaseInitialized = false;

Future<_BootstrapData> _initializeApplication() async {
  // Durasi minimum singkat membuat gerak masuk logo selesai tanpa menahan
  // startup yang memang membutuhkan waktu lebih lama.
  final minimumSplashTime =
      Future<void>.delayed(const Duration(milliseconds: 1100));

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await initializeDateFormatting('id_ID');

  if (!_supabaseInitialized) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    _supabaseInitialized = true;
  }

  final initialOutletId = await OnboardingService().getCurrentOutletId();
  await minimumSplashTime;
  return _BootstrapData(initialOutletId: initialOutletId);
}

class _BootstrapData {
  final String? initialOutletId;

  const _BootstrapData({required this.initialOutletId});
}

class SajiaBootstrap extends StatefulWidget {
  const SajiaBootstrap({super.key});

  @override
  State<SajiaBootstrap> createState() => _SajiaBootstrapState();
}

class _SajiaBootstrapState extends State<SajiaBootstrap> {
  late Future<_BootstrapData> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeApplication();
  }

  void _retry() {
    setState(() => _initialization = _initializeApplication());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapData>(
      future: _initialization,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          child = SajiaApp(
            key: const ValueKey('sajia-app'),
            initialOutletId: snapshot.requireData.initialOutletId,
          );
        } else if (snapshot.hasError) {
          child = SajiaStartupError(
            key: const ValueKey('startup-error'),
            onRetry: _retry,
          );
        } else {
          child = const SajiaStartupSplash(
            key: ValueKey('startup-splash'),
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: child,
        );
      },
    );
  }
}

class SajiaApp extends ConsumerStatefulWidget {
  final bool startSyncOnLaunch;
  final String? initialOutletId;

  const SajiaApp({
    super.key,
    this.startSyncOnLaunch = true,
    this.initialOutletId,
  });

  @override
  ConsumerState<SajiaApp> createState() => _SajiaAppState();
}

class _SajiaAppState extends ConsumerState<SajiaApp> {
  @override
  void initState() {
    super.initState();
    final initialOutletId = widget.initialOutletId;
    if (initialOutletId != null && initialOutletId.isNotEmpty) {
      ref.read(currentOutletIdProvider.notifier).state = initialOutletId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSync();
    });
  }

  void _startSync() {
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
