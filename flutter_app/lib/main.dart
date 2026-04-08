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

  if (supabaseUrl != null &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey.isNotEmpty) {
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

  runApp(
    const ProviderScope(
      child: SafetyApp(),
    ),
  );
}
