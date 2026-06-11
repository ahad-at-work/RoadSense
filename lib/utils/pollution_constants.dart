import 'package:flutter/material.dart';

/// AQI color standards based on international guidelines
class AQIColors {
  static Color getColor(int aqi) {
    if (aqi <= 50) return const Color(0xFF00E400);      // Good - Green
    if (aqi <= 100) return const Color(0xFFFFFF00);     // Moderate - Yellow
    if (aqi <= 150) return const Color(0xFFFF7E00);     // Unhealthy for Sensitive - Orange
    if (aqi <= 200) return const Color(0xFFFF0000);     // Unhealthy - Red
    if (aqi <= 300) return const Color(0xFF8F3F97);     // Very Unhealthy - Purple
    return const Color(0xFF7E0023);                     // Hazardous - Maroon
  }

  static Color getColorWithOpacity(int aqi, double opacity) {
    return getColor(aqi).withValues(alpha: opacity);
  }

  static String getCategory(int aqi) {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for Sensitive Groups';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  static IconData getCategoryIcon(int aqi) {
    if (aqi <= 50) return Icons.sentiment_very_satisfied;
    if (aqi <= 100) return Icons.sentiment_satisfied;
    if (aqi <= 150) return Icons.sentiment_neutral;
    if (aqi <= 200) return Icons.sentiment_dissatisfied;
    if (aqi <= 300) return Icons.sentiment_very_dissatisfied;
    return Icons.warning;
  }
}

/// Pollutant information and display names
class PollutantInfo {
  static const Map<String, String> displayNames = {
    'pm25': 'PM2.5',
    'pm10': 'PM10',
    'no2': 'NO',
    'so2': 'SO',
    'co': 'CO',
    'o3': 'O',
  };

  static const Map<String, String> fullNames = {
    'pm25': 'Fine Particulate Matter',
    'pm10': 'Coarse Particulate Matter',
    'no2': 'Nitrogen Dioxide',
    'so2': 'Sulfur Dioxide',
    'co': 'Carbon Monoxide',
    'o3': 'Ozone',
  };

  static const Map<String, String> descriptions = {
    'pm25': 'Tiny particles that can penetrate deep into lungs',
    'pm10': 'Inhalable particles from dust, pollen, and mold',
    'no2': 'Gas produced by vehicle emissions and power plants',
    'so2': 'Gas released from burning fossil fuels',
    'co': 'Odorless gas from incomplete combustion',
    'o3': 'Ground-level ozone formed by sunlight and pollutants',
  };

  static const Map<String, IconData> icons = {
    'pm25': Icons.blur_on,
    'pm10': Icons.grain,
    'no2': Icons.local_shipping,
    'so2': Icons.factory,
    'co': Icons.smoke_free,
    'o3': Icons.wb_sunny,
  };

  static String getDisplayName(String code) {
    return displayNames[code.toLowerCase()] ?? code.toUpperCase();
  }

  static String getFullName(String code) {
    return fullNames[code.toLowerCase()] ?? 'Unknown Pollutant';
  }

  static String getDescription(String code) {
    return descriptions[code.toLowerCase()] ?? 'No description available';
  }

  static IconData getIcon(String code) {
    return icons[code.toLowerCase()] ?? Icons.help_outline;
  }
}

/// Update intervals and thresholds
class PollutionConfig {
  static const Duration updateInterval = Duration(minutes: 15);
  static const double significantMoveDistanceMeters = 5000; // 5km
  static const Duration cacheExpiration = Duration(minutes: 15);
  static const int maxCacheSize = 50;
  
  // Default alert threshold (Moderate level)
  static const int defaultAlertThreshold = 100;
  
  // Minimum time between alerts (to avoid spam)
  static const Duration alertCooldown = Duration(minutes: 30);
}

/// Health recommendation categories
class HealthCategories {
  static const List<String> groups = [
    'General Population',
    'Sensitive Groups',
    'Activity Level',
  ];

  static const Map<String, String> sensitiveGroupsInfo = {
    'Children': 'Children are more vulnerable due to developing respiratory systems',
    'Elderly': 'Older adults may have weakened immune systems',
    'Asthma': 'People with asthma are highly sensitive to air pollutants',
    'Heart Disease': 'Cardiovascular patients should take extra precautions',
    'Lung Disease': 'Those with lung conditions should limit exposure',
  };
}

/// Formatting utilities
class PollutionFormatters {
  static String formatConcentration(double value, String unit) {
    if (value < 1) {
      return '${value.toStringAsFixed(2)} $unit';
    } else if (value < 10) {
      return '${value.toStringAsFixed(1)} $unit';
    } else {
      return '${value.toStringAsFixed(0)} $unit';
    }
  }

  static String formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);
    
    if (difference.inMinutes.abs() < 60) {
      return '${difference.inMinutes.abs()} min';
    } else {
      return '${difference.inHours}h';
    }
  }

  static String getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

