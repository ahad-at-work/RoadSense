import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import '../utils/app_config.dart';

import '../sensors/sensor_data.dart';
import 'event_service.dart';
import 'location_service.dart';
import 'pollution_service.dart';
import 'trip_logger_service.dart';

class BackgroundSyncService {
  static const String _syncQueuesUniqueName =
      'roadsense.background.sync.queues';
  static const String syncQueuesTask = 'sync_queued_data_task';

  static Future<void> initialize() async {
    if (!Platform.isAndroid) {
      return;
    }

    await Workmanager().initialize(
      backgroundSyncTaskDispatcher,
      isInDebugMode: false,
    );

    await Workmanager().registerPeriodicTask(
      _syncQueuesUniqueName,
      syncQueuesTask,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 5),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    debugPrint(' Background queue sync worker registered');
  }

  static Future<void> runOnceNow() async {
    if (!Platform.isAndroid) {
      return;
    }

    await Workmanager().registerOneOffTask(
      'roadsense.background.sync.now',
      syncQueuesTask,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
}

@pragma('vm:entry-point')
void backgroundSyncTaskDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (task != BackgroundSyncService.syncQueuesTask) {
      return Future.value(true);
    }

    try {
      final configUrl = await AppConfig.getApiEndpoint();

      await SensorData.initialize(apiUrl: configUrl);
      await SensorData.retryOfflineQueue();

      await TripLoggerService.initialize(apiUrl: configUrl);
      await TripLoggerService.flushOfflineQueue();

      await EventService.initialize(apiUrl: configUrl);
      final eventCount =
          (await EventService().fetchEvents(forceRefresh: true)).length;

      final lastCoordinate =
          await LocationService.getLastKnownCoordinateForBackground();
      if (lastCoordinate != null) {
        final pollutionService = PollutionService();
        await pollutionService.fetchAirQuality(
          lastCoordinate['lat']!,
          lastCoordinate['lon']!,
        );
      }

      debugPrint(
        ' Background sync completed (events: $eventCount, pollution refreshed: ${lastCoordinate != null})',
      );
      return Future.value(true);
    } catch (error, stackTrace) {
      debugPrint(' Background queue sync failed: $error');
      debugPrint('$stackTrace');
      return Future.value(false);
    }
  });
}
