import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_google_maps_nav/utils/app_config.dart';
import 'package:flutter_google_maps_nav/services/trip_logger_service.dart';
import 'package:flutter_google_maps_nav/services/event_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig integration', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('AppConfig initializes and TripLoggerService reads persisted endpoint',
        () async {
      const endpoint = 'https://example.com/test-endpoint';

      await AppConfig.initialize(apiEndpoint: endpoint, apiKey: 'fake-key');

      // TripLoggerService.initialize without apiUrl should pick up AppConfig endpoint
      await TripLoggerService.initialize();

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('trip_logger_api_endpoint');
      expect(stored, isNotNull);
      expect(stored, equals(endpoint));
    });

    test('EventService uses AppConfig endpoint and reports configured',
        () async {
      const endpoint = 'https://example.com/events';
      await AppConfig.initialize(apiEndpoint: endpoint);

      await EventService.initialize();

      expect(EventService.isConfigured, isTrue);
    });
  });
}
