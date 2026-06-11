import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'map_screen.dart';
import 'services/location_service.dart';
import 'services/places_service.dart';
import 'services/navigation_service.dart';
import 'services/pollution_service.dart';
import 'services/app_logger.dart';
import 'services/background_sync_service.dart';
import 'utils/app_config.dart';
import 'sensors/sensor_data.dart';
import 'services/event_service.dart';

const String _buildApiEndpoint = String.fromEnvironment('API_ENDPOINT', defaultValue: '');
const String _buildApiKey = String.fromEnvironment('API_KEY', defaultValue: '');
const String _buildHmacSecret = String.fromEnvironment('HMAC_SECRET', defaultValue: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final DebugPrintCallback previousDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.trim().isNotEmpty) {
      AppLogger.instance.add(message);
    }
    previousDebugPrint(message, wrapWidth: wrapWidth);
  };

  final FlutterExceptionHandler? previousFlutterErrorHandler =
      FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.instance.add('FlutterError: ${details.exceptionAsString()}');
    previousFlutterErrorHandler?.call(details);
  };

  //
  //  v3.0: INITIALIZE SECURE CONFIGURATION
  //

  const String apiEndpoint =
      'https://script.google.com/macros/s/AKfycbzJn8LxIfrnvReyA_bkQuIiOxtYt4GMVvjeq6NfX31nyWNWGURAnEy6HamWOTILbN4/exec';

  await AppConfig.initialize(
    apiEndpoint: _buildApiEndpoint.isNotEmpty ? _buildApiEndpoint : apiEndpoint,
    apiKey: _buildApiKey.isNotEmpty ? _buildApiKey : 'your-api-key-here',
    hmacSecret: _buildHmacSecret.isNotEmpty ? _buildHmacSecret : null,
  );

  runApp(const MyApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_bootstrapAppServices(apiEndpoint));
  });
}

Future<void> _bootstrapAppServices(String apiEndpoint) async {
  await SensorData.initialize(apiUrl: apiEndpoint);
  await EventService.initialize(apiUrl: apiEndpoint);
  await BackgroundSyncService.initialize();

  final configStatus = await AppConfig.getConfigurationStatus();
  final endpointPreview = configStatus['endpoint'] as String?;
  final apiKeyStatus =
      configStatus['hasApiKey'] == true ? 'configured' : 'missing';
  final hmacStatus =
      configStatus['hasHmacSecret'] == true ? 'configured' : 'missing';
  final validStatus = configStatus['isValid'] == true ? 'yes' : 'no';

  debugPrint("");
  debugPrint(" Configuration Status:");
  debugPrint("  API Endpoint: ${endpointPreview ?? '<missing>'}");
  debugPrint("  API Key: $apiKeyStatus");
  debugPrint("  HMAC Secret: $hmacStatus");
  debugPrint("  Valid: $validStatus");
  debugPrint("");

  final queueSize = SensorData.getQueueSize();
  if (queueSize > 0) {
    debugPrint(" Found $queueSize queued events from previous session");
    debugPrint(" Will attempt to upload when network is available");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => PlacesService()),
        ChangeNotifierProvider(create: (_) => NavigationService()),
        ChangeNotifierProvider(create: (_) => PollutionService()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RoadSense',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: const MapScreen(),
      ),
    );
  }
}
