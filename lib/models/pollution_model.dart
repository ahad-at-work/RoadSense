import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Represents air quality data for a specific location
class PollutionData {
  final DateTime timestamp;
  final LatLng location;
  final int aqi;
  final String category;
  final String dominantPollutant;
  final Map<String, PollutantConcentration> pollutants;
  final List<HourlyForecast>? forecasts;
  final HealthRecommendation healthRecommendation;

  PollutionData({
    required this.timestamp,
    required this.location,
    required this.aqi,
    required this.category,
    required this.dominantPollutant,
    required this.pollutants,
    this.forecasts,
    required this.healthRecommendation,
  });

  factory PollutionData.fromJson(Map<String, dynamic> json, double lat, double lon) {
    try {
      // Extract AQI from indexes array
      final indexes = json['indexes'] as List?;
      int aqi = 0;
      String category = 'unknown';
      String dominantPollutant = 'unknown';

      if (indexes != null && indexes.isNotEmpty) {
        final aqiIndex = indexes.firstWhere(
          (idx) => idx['code'] == 'uaqi',
          orElse: () => indexes.first,
        );
        aqi = (aqiIndex['aqi'] as num?)?.toInt() ?? 0;
        category = (aqiIndex['category'] ?? 'unknown').toString().toLowerCase();
        dominantPollutant = (aqiIndex['dominantPollutant'] ?? 'unknown').toString();
      }

      // Extract pollutant concentrations
      final pollutantsMap = <String, PollutantConcentration>{};
      final pollutantsList = json['pollutants'] as List?;
      
      if (pollutantsList != null) {
        for (var p in pollutantsList) {
          final code = p['code'] as String?;
          if (code != null) {
            pollutantsMap[code] = PollutantConcentration.fromJson(p);
          }
        }
      }

      // Extract hourly forecasts if available
      List<HourlyForecast>? forecasts;
      final hourlyForecasts = json['hourlyForecasts'] as List?;
      if (hourlyForecasts != null) {
        forecasts = hourlyForecasts
            .map((f) => HourlyForecast.fromJson(f))
            .toList();
      }

      // Generate health recommendation
      final healthRec = HealthRecommendation.fromAQI(aqi, category);

      return PollutionData(
        timestamp: DateTime.now(),
        location: LatLng(lat, lon),
        aqi: aqi,
        category: category,
        dominantPollutant: dominantPollutant,
        pollutants: pollutantsMap,
        forecasts: forecasts,
        healthRecommendation: healthRec,
      );
    } catch (e) {
      throw Exception('Failed to parse pollution data: $e');
    }
  }

  bool isExpired() {
    return DateTime.now().difference(timestamp).inMinutes > 15;
  }

  bool exceedsThreshold(int threshold) {
    return aqi > threshold;
  }
}

/// Individual pollutant concentration data
class PollutantConcentration {
  final String code;
  final String displayName;
  final String fullName;
  final double concentration;
  final String unit;

  PollutantConcentration({
    required this.code,
    required this.displayName,
    required this.fullName,
    required this.concentration,
    required this.unit,
  });

  factory PollutantConcentration.fromJson(Map<String, dynamic> json) {
    return PollutantConcentration(
      code: json['code'] as String? ?? 'unknown',
      displayName: json['displayName'] as String? ?? 'Unknown',
      fullName: json['fullName'] as String? ?? 'Unknown Pollutant',
      concentration: (json['concentration']?['value'] as num?)?.toDouble() ?? 0.0,
      unit: json['concentration']?['units'] as String? ?? 'g/m',
    );
  }
}

/// Hourly forecast data
class HourlyForecast {
  final DateTime dateTime;
  final int aqi;
  final String category;

  HourlyForecast({
    required this.dateTime,
    required this.aqi,
    required this.category,
  });

  factory HourlyForecast.fromJson(Map<String, dynamic> json) {
    final indexes = json['indexes'] as List?;
    int aqi = 0;
    String category = 'unknown';

    if (indexes != null && indexes.isNotEmpty) {
      final aqiIndex = indexes.first;
      aqi = (aqiIndex['aqi'] as num?)?.toInt() ?? 0;
      category = (aqiIndex['category'] ?? 'unknown').toString().toLowerCase();
    }

    return HourlyForecast(
      dateTime: DateTime.parse(json['dateTime'] as String),
      aqi: aqi,
      category: category,
    );
  }
}

/// Health recommendations based on AQI
class HealthRecommendation {
  final String general;
  final String sensitive;
  final String activity;

  HealthRecommendation({
    required this.general,
    required this.sensitive,
    required this.activity,
  });

  factory HealthRecommendation.fromAQI(int aqi, String category) {
    if (aqi <= 50) {
      return HealthRecommendation(
        general: 'Air quality is good. Enjoy outdoor activities!',
        sensitive: 'No health concerns for sensitive groups.',
        activity: 'Ideal conditions for outdoor activities.',
      );
    } else if (aqi <= 100) {
      return HealthRecommendation(
        general: 'Air quality is acceptable for most people.',
        sensitive: 'Sensitive individuals should consider limiting prolonged outdoor exertion.',
        activity: 'Generally acceptable for outdoor activities.',
      );
    } else if (aqi <= 150) {
      return HealthRecommendation(
        general: 'Sensitive groups may experience health effects.',
        sensitive: 'Limit prolonged outdoor activities. Consider wearing a mask.',
        activity: 'Reduce prolonged or heavy outdoor exertion.',
      );
    } else if (aqi <= 200) {
      return HealthRecommendation(
        general: 'Everyone may experience health effects.',
        sensitive: 'Avoid prolonged outdoor activities. Wear a protective mask.',
        activity: 'Avoid prolonged outdoor exertion. Keep activities short.',
      );
    } else if (aqi <= 300) {
      return HealthRecommendation(
        general: 'Health alert: everyone may experience serious effects.',
        sensitive: 'Stay indoors and keep windows closed. Use air purifiers.',
        activity: 'Avoid all outdoor activities.',
      );
    } else {
      return HealthRecommendation(
        general: 'Health warning: emergency conditions.',
        sensitive: 'Remain indoors at all times. Seek medical attention if experiencing symptoms.',
        activity: 'Avoid all outdoor exposure.',
      );
    }
  }
}

/// User's pollution alert settings
class PollutionAlertSettings {
  final bool enabled;
  final int aqiThreshold;
  final Set<String> alertPollutants;

  PollutionAlertSettings({
    this.enabled = false,
    this.aqiThreshold = 100,
    this.alertPollutants = const {'pm25', 'pm10', 'no2'},
  });

  PollutionAlertSettings copyWith({
    bool? enabled,
    int? aqiThreshold,
    Set<String>? alertPollutants,
  }) {
    return PollutionAlertSettings(
      enabled: enabled ?? this.enabled,
      aqiThreshold: aqiThreshold ?? this.aqiThreshold,
      alertPollutants: alertPollutants ?? this.alertPollutants,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'aqiThreshold': aqiThreshold,
      'alertPollutants': alertPollutants.toList(),
    };
  }

  factory PollutionAlertSettings.fromJson(Map<String, dynamic> json) {
    return PollutionAlertSettings(
      enabled: json['enabled'] as bool? ?? false,
      aqiThreshold: json['aqiThreshold'] as int? ?? 100,
      alertPollutants: Set<String>.from(json['alertPollutants'] as List? ?? []),
    );
  }
}
