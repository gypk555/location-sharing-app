import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/models/user_model.dart';
import 'core/models/contact_model.dart';
import 'core/models/location_model.dart';
import 'core/services/background_service.dart';
import 'core/services/fake_call_service.dart';
import 'core/services/secure_hive.dart';
import 'core/services/sos_service.dart';
import 'shared/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables (gracefully handle missing file)
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    AppLogger.warning('Could not load .env file - using defaults');
  }

  // Initialize Supabase with graceful fallback
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  final hasSupabaseCreds = supabaseUrl != null &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey.isNotEmpty;

  // Release builds MUST have Supabase credentials wired. A release APK
  // without `.env` silently fell through to in-memory demo auth, so users
  // could "sign in" but every RLS-protected write (SOS included) vanished
  // into the void (security fix M-1). Fail loud in release; keep the
  // graceful path for debug / CI runs.
  if (!kDebugMode && !hasSupabaseCreds) {
    throw StateError(
      'Supabase credentials missing in release build. '
      'SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env.',
    );
  }

  if (hasSupabaseCreds) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      AppLogger.info('Supabase initialized successfully');
    } catch (e) {
      AppLogger.error('Failed to initialize Supabase', e);
      // Continue without Supabase - app can still work in offline/demo mode
    }
  } else {
    AppLogger.warning(
        'Supabase credentials not configured - running in offline/demo mode');
  }

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Register Hive adapters
  Hive.registerAdapter(UserModelAdapter());
  Hive.registerAdapter(ContactModelAdapter());
  Hive.registerAdapter(LocationModelAdapter());

  // Initialize the Hive encryption cipher before any box is opened. Every
  // box in the app is opened via SecureHive.openBox, which applies this
  // cipher and transparently migrates pre-existing unencrypted boxes
  // (security fix H-2).
  await SecureHive.init();

  // Configure the background location service and hydrate SOS / fake-call
  // preferences in parallel — none of the three depend on each other.
  // Safe to call BackgroundService.configure even if the user never starts
  // a live share (the service won't run until explicitly started).
  await Future.wait([
    BackgroundService.configure(),
    SosService().init(),
    FakeCallService().loadPersistedCallerInfo(),
  ]);

  runApp(
    const ProviderScope(
      child: SafetyApp(),
    ),
  );
}
