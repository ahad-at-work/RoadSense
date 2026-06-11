import 'dart:math' as math;
import 'package:flutter/material.dart'; //  MOVED: Import at top
import '../services/event_service.dart';
import '../models/pollution_model.dart';
import '../services/navigation_service.dart';

/// Analyzes routes for safety risks including hazards and pollution
class RouteRiskAnalyzer {
  // Risk weights (adjustable based on preferences)
  static const double hazardWeight = 15.0; // Points per hazard
  static const double pollutionWeight = 0.5; // Multiplier for AQI
  static const double distanceWeight = 0.01; // Penalty for extra distance

  static const double hazardProximityThreshold = 50.0; // meters

  /// Analyze a single route for risks
  static RouteRiskAssessment analyzeRoute({
    required RouteAlternative route,
    required List<EventModel> roadEvents,
    PollutionData? pollutionData,
  }) {
    final hazards = _findHazardsOnRoute(route, roadEvents);
    final pollutionScore = _calculatePollutionScore(pollutionData);
    final distancePenalty = route.distanceMeters * distanceWeight;

    // Calculate total risk score (lower is better)
    final totalRisk = (hazards.length * hazardWeight) +
        (pollutionScore * pollutionWeight) +
        distancePenalty;

    return RouteRiskAssessment(
      route: route,
      hazardCount: hazards.length,
      hazards: hazards,
      pollutionScore: pollutionScore,
      distancePenaltyScore: distancePenalty,
      totalRiskScore: totalRisk,
      riskLevel: _determineRiskLevel(totalRisk, hazards.length),
    );
  }

  /// Analyze multiple routes and return sorted by safety
  static List<RouteRiskAssessment> analyzeAndRankRoutes({
    required List<RouteAlternative> routes,
    required List<EventModel> roadEvents,
    PollutionData? pollutionData,
  }) {
    final assessments = <RouteRiskAssessment>[];

    for (var route in routes) {
      final assessment = analyzeRoute(
        route: route,
        roadEvents: roadEvents,
        pollutionData: pollutionData,
      );
      assessments.add(assessment);
    }

    // Sort by total risk score (ascending - lower is safer)
    assessments.sort((a, b) => a.totalRiskScore.compareTo(b.totalRiskScore));

    debugPrint(' Route Risk Analysis:');
    for (int i = 0; i < assessments.length; i++) {
      final assessment = assessments[i];
      debugPrint('  ${i + 1}. ${assessment.route.summary}: '
          'Risk=${assessment.totalRiskScore.toStringAsFixed(1)}, '
          'Hazards=${assessment.hazardCount}, '
          'Level=${assessment.riskLevel}');
    }

    return assessments;
  }

  /// Find hazards along a route
  static List<RouteHazard> _findHazardsOnRoute(
    RouteAlternative route,
    List<EventModel> events,
  ) {
    final hazards = <RouteHazard>[];
    final processedEvents = <String>{};

    for (var event in events) {
      // Skip if already processed (avoid duplicates)
      final eventKey = '${event.lat}_${event.lon}_${event.type}';
      if (processedEvents.contains(eventKey)) continue;

      // Check if event is near any point on route
      double minDistance = double.infinity;
      int nearestSegmentIndex = -1;

      if (route.polylineCoordinates.isEmpty) {
        continue;
      }

      for (int i = 0; i < route.polylineCoordinates.length; i++) {
        final point = route.polylineCoordinates[i];

        final distance = i < route.polylineCoordinates.length - 1
            ? _distanceToLineSegment(
                event.lat,
                event.lon,
                point.latitude,
                point.longitude,
                route.polylineCoordinates[i + 1].latitude,
                route.polylineCoordinates[i + 1].longitude,
              )
            : _calculateDistance(
                event.lat,
                event.lon,
                point.latitude,
                point.longitude,
              );

        if (distance < minDistance) {
          minDistance = distance;
          nearestSegmentIndex = i;
        }
      }

      // If event is close enough to route, mark as hazard
      if (minDistance <= hazardProximityThreshold) {
        hazards.add(RouteHazard(
          event: event,
          distanceFromRoute: minDistance,
          routeSegmentIndex: nearestSegmentIndex,
          severity: _getHazardSeverity(event.type),
        ));
        processedEvents.add(eventKey);
      }
    }

    return hazards;
  }

  /// Calculate distance from a point to a line segment.
  static double _distanceToLineSegment(
    double pointLat,
    double pointLon,
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) {
    final x = pointLat;
    final y = pointLon;
    final x1 = startLat;
    final y1 = startLon;
    final x2 = endLat;
    final y2 = endLon;

    final a = x - x1;
    final b = y - y1;
    final c = x2 - x1;
    final d = y2 - y1;

    final dot = a * c + b * d;
    final lenSq = c * c + d * d;
    double param = -1;

    if (lenSq != 0) {
      param = dot / lenSq;
    }

    double closestLat;
    double closestLon;

    if (param < 0) {
      closestLat = x1;
      closestLon = y1;
    } else if (param > 1) {
      closestLat = x2;
      closestLon = y2;
    } else {
      closestLat = x1 + param * c;
      closestLon = y1 + param * d;
    }

    return _calculateDistance(pointLat, pointLon, closestLat, closestLon);
  }

  /// Calculate pollution score for route area
  static double _calculatePollutionScore(PollutionData? pollution) {
    if (pollution == null) return 0.0;

    // AQI ranges from 0-500+, normalize to 0-100 scale
    return math.min(pollution.aqi.toDouble(), 500.0) / 5.0;
  }

  /// Determine risk level based on total score and hazard count
  static RiskLevel _determineRiskLevel(double totalRisk, int hazardCount) {
    if (hazardCount >= 5 || totalRisk > 150) {
      return RiskLevel.high;
    } else if (hazardCount >= 3 || totalRisk > 80) {
      return RiskLevel.medium;
    } else if (hazardCount >= 1 || totalRisk > 30) {
      return RiskLevel.low;
    } else {
      return RiskLevel.safe;
    }
  }

  /// Get severity score for hazard type
  static HazardSeverity _getHazardSeverity(String eventType) {
    switch (eventType.toLowerCase().trim()) {
      case 'pothole':
        return HazardSeverity.high;
      case 'impact':
        return HazardSeverity.high;
      case 'speed bump':
      case 'bump':
        return HazardSeverity.medium;
      case 'vibration':
        return HazardSeverity.medium;
      case 'rotation':
        return HazardSeverity.low;
      default:
        return HazardSeverity.medium;
    }
  }

  /// Calculate distance between two coordinates (Haversine)
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  /// Generate risk report text
  static String generateRiskReport(RouteRiskAssessment assessment) {
    final buffer = StringBuffer();

    buffer.writeln('Route Risk Assessment: ${assessment.route.summary}');
    buffer.writeln(
        'Risk Level: ${assessment.riskLevel.toString().split('.').last.toUpperCase()}');
    buffer.writeln(
        'Total Risk Score: ${assessment.totalRiskScore.toStringAsFixed(1)}');
    buffer.writeln('\nDetails:');
    buffer.writeln('- Hazards on route: ${assessment.hazardCount}');

    if (assessment.hazards.isNotEmpty) {
      final highSeverity = assessment.hazards
          .where((h) => h.severity == HazardSeverity.high)
          .length;
      final mediumSeverity = assessment.hazards
          .where((h) => h.severity == HazardSeverity.medium)
          .length;
      final lowSeverity = assessment.hazards
          .where((h) => h.severity == HazardSeverity.low)
          .length;

      if (highSeverity > 0) buffer.writeln('   High severity: $highSeverity');
      if (mediumSeverity > 0) {
        buffer.writeln('   Medium severity: $mediumSeverity');
      }
      if (lowSeverity > 0) buffer.writeln('   Low severity: $lowSeverity');
    }

    if (assessment.pollutionScore > 0) {
      buffer.writeln(
          '- Air quality impact: ${assessment.pollutionScore.toStringAsFixed(1)}');
    }

    buffer.writeln('- Distance: ${assessment.route.distanceText}');
    buffer.writeln('- Duration: ${assessment.route.durationText}');

    return buffer.toString();
  }
}

/// Risk assessment result for a route
class RouteRiskAssessment {
  final RouteAlternative route;
  final int hazardCount;
  final List<RouteHazard> hazards;
  final double pollutionScore;
  final double distancePenaltyScore;
  final double totalRiskScore;
  final RiskLevel riskLevel;

  RouteRiskAssessment({
    required this.route,
    required this.hazardCount,
    required this.hazards,
    required this.pollutionScore,
    required this.distancePenaltyScore,
    required this.totalRiskScore,
    required this.riskLevel,
  });

  /// Check if route is safe enough to recommend
  bool get isSafe => riskLevel == RiskLevel.safe || riskLevel == RiskLevel.low;

  /// Get risk level color
  Color get riskColor {
    switch (riskLevel) {
      case RiskLevel.safe:
        return const Color(0xFF4CAF50); // Green
      case RiskLevel.low:
        return const Color(0xFF8BC34A); // Light Green
      case RiskLevel.medium:
        return const Color(0xFFFF9800); // Orange
      case RiskLevel.high:
        return const Color(0xFFF44336); // Red
    }
  }

  /// Get risk level icon
  IconData get riskIcon {
    switch (riskLevel) {
      case RiskLevel.safe:
        return Icons.check_circle;
      case RiskLevel.low:
        return Icons.info;
      case RiskLevel.medium:
        return Icons.warning;
      case RiskLevel.high:
        return Icons.dangerous;
    }
  }

  /// Get human-readable risk description
  String get riskDescription {
    switch (riskLevel) {
      case RiskLevel.safe:
        return 'Safe route with no hazards detected';
      case RiskLevel.low:
        return 'Minor hazards present, proceed with caution';
      case RiskLevel.medium:
        return 'Multiple hazards detected, drive carefully';
      case RiskLevel.high:
        return 'High risk route - consider alternative';
    }
  }
}

/// Individual hazard found on route
class RouteHazard {
  final EventModel event;
  final double distanceFromRoute; // meters
  final int routeSegmentIndex; // index in polyline
  final HazardSeverity severity;

  RouteHazard({
    required this.event,
    required this.distanceFromRoute,
    required this.routeSegmentIndex,
    required this.severity,
  });
}

/// Risk level categories
enum RiskLevel {
  safe, // 0 hazards
  low, // 1-2 hazards
  medium, // 3-4 hazards
  high, // 5+ hazards
}

/// Hazard severity levels
enum HazardSeverity {
  low, // Minor inconvenience
  medium, // Requires attention
  high, // Potential danger
}

//  REMOVED: Duplicate import moved to top
extension RiskLevelColors on RiskLevel {
  Color get color {
    switch (this) {
      case RiskLevel.safe:
        return const Color(0xFF4CAF50);
      case RiskLevel.low:
        return const Color(0xFF8BC34A);
      case RiskLevel.medium:
        return const Color(0xFFFF9800);
      case RiskLevel.high:
        return const Color(0xFFF44336);
    }
  }

  IconData get icon {
    switch (this) {
      case RiskLevel.safe:
        return Icons.check_circle;
      case RiskLevel.low:
        return Icons.info;
      case RiskLevel.medium:
        return Icons.warning;
      case RiskLevel.high:
        return Icons.dangerous;
    }
  }
}

