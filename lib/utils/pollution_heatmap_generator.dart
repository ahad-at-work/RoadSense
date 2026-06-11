import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/pollution_model.dart';
import '../utils/pollution_constants.dart';

/// Generates heat map visualization for pollution data
class PollutionHeatmapGenerator {
  /// Generate polygon-based heat map for a pollution reading
  /// Creates concentric zones with decreasing intensity
  static Set<Polygon> generateHeatmap({
    required PollutionData pollution,
    required LatLng center,
    int zones = 4,
    double maxRadiusKm = 5.0,
  }) {
    final polygons = <Polygon>{};
    final baseColor = AQIColors.getColor(pollution.aqi);

    // Create zones from outer to inner for proper layering
    for (int i = zones - 1; i >= 0; i--) {
      final zoneRadius = maxRadiusKm * ((i + 1) / zones);
      final opacity = 0.15 + (0.15 * (zones - i) / zones); // 0.15 to 0.30
      
      final polygon = _createCircularPolygon(
        center: center,
        radiusKm: zoneRadius,
        color: baseColor,
        opacity: opacity,
        zIndex: i,
        id: 'pollution_zone_${i}_${center.latitude}_${center.longitude}',
      );
      
      polygons.add(polygon);
    }

    return polygons;
  }

  /// Generate grid-based heat map for multiple pollution readings
  /// More accurate when you have multiple data points
  static Set<Polygon> generateGridHeatmap({
    required List<PollutionDataPoint> dataPoints,
    required LatLngBounds bounds,
    double gridSizeKm = 1.0,
  }) {
    final polygons = <Polygon>{};
    
    if (dataPoints.isEmpty) {
      debugPrint(' No data points for grid heatmap');
      return polygons;
    }
    
    // Calculate grid dimensions
    final latStep = gridSizeKm / 111.0; // ~111km per degree latitude
    final lngStep = gridSizeKm / (111.0 * math.cos(bounds.southwest.latitude * math.pi / 180));

    // Generate grid cells
    for (double lat = bounds.southwest.latitude; 
         lat < bounds.northeast.latitude; 
         lat += latStep) {
      for (double lng = bounds.southwest.longitude; 
           lng < bounds.northeast.longitude; 
           lng += lngStep) {
        
        final cellCenter = LatLng(lat + latStep / 2, lng + lngStep / 2);
        
        // Find nearest pollution reading
        final nearest = _findNearestDataPoint(cellCenter, dataPoints);
        
        if (nearest != null && nearest.distance < gridSizeKm * 1000) {
          // Weight by distance
          final weight = 1 - (nearest.distance / (gridSizeKm * 1000));
          //  FIXED: Direct access to PollutionData's aqi
          final aqi = nearest.data.data.aqi;
          final color = AQIColors.getColor(aqi);
          
          final cellPolygon = _createRectangularPolygon(
            southwest: LatLng(lat, lng),
            northeast: LatLng(lat + latStep, lng + lngStep),
            color: color,
            opacity: 0.2 * weight,
            id: 'grid_${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}',
          );
          
          polygons.add(cellPolygon);
        }
      }
    }

    debugPrint(' Generated ${polygons.length} grid cells');
    return polygons;
  }

  /// Create a circular polygon
  static Polygon _createCircularPolygon({
    required LatLng center,
    required double radiusKm,
    required Color color,
    required double opacity,
    required int zIndex,
    required String id,
    int segments = 32,
  }) {
    final points = <LatLng>[];
    final radiusDegrees = radiusKm / 111.0;

    for (int i = 0; i <= segments; i++) {
      final angle = (i * 360 / segments) * math.pi / 180;
      final lat = center.latitude + (radiusDegrees * math.cos(angle));
      final lng = center.longitude + 
          (radiusDegrees * math.sin(angle) / math.cos(center.latitude * math.pi / 180));
      points.add(LatLng(lat, lng));
    }

    return Polygon(
      polygonId: PolygonId(id),
      points: points,
      fillColor: color.withValues(alpha: opacity),
      strokeColor: color.withValues(alpha: opacity * 2),
      strokeWidth: 1,
      zIndex: zIndex,
      geodesic: false,
      consumeTapEvents: false, // Don't block map interactions
    );
  }

  /// Create a rectangular polygon (for grid cells)
  static Polygon _createRectangularPolygon({
    required LatLng southwest,
    required LatLng northeast,
    required Color color,
    required double opacity,
    required String id,
  }) {
    final points = [
      southwest,
      LatLng(northeast.latitude, southwest.longitude),
      northeast,
      LatLng(southwest.latitude, northeast.longitude),
      southwest, // Close the polygon
    ];

    return Polygon(
      polygonId: PolygonId(id),
      points: points,
      fillColor: color.withValues(alpha: opacity),
      strokeColor: color.withValues(alpha: opacity * 1.5),
      strokeWidth: 1,
      geodesic: false,
      consumeTapEvents: false,
    );
  }

  /// Find nearest pollution data point to a location
  static NearestDataPoint? _findNearestDataPoint(
    LatLng target,
    List<PollutionDataPoint> dataPoints,
  ) {
    if (dataPoints.isEmpty) return null;

    PollutionDataPoint? nearest;
    double minDistance = double.infinity;

    for (var point in dataPoints) {
      final distance = _calculateDistance(
        target.latitude,
        target.longitude,
        point.location.latitude,
        point.location.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearest = point;
      }
    }

    return nearest != null 
        ? NearestDataPoint(data: nearest, distance: minDistance)
        : null;
  }

  ///  FIXED: Calculate distance between two points (Haversine formula)
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    
    // Convert to radians
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);
    
    // Haversine formula
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(lat1Rad) * math.cos(lat2Rad) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  /// Generate interpolated heat map (advanced - for future use)
  /// Uses inverse distance weighting for smooth gradients
  static Set<Polygon> generateInterpolatedHeatmap({
    required List<PollutionDataPoint> dataPoints,
    required LatLngBounds bounds,
    double gridSizeKm = 0.5,
    double influenceRadiusKm = 3.0,
  }) {
    final polygons = <Polygon>{};
    
    if (dataPoints.isEmpty) {
      debugPrint(' No data points for interpolated heatmap');
      return polygons;
    }

    final latStep = gridSizeKm / 111.0;
    final lngStep = gridSizeKm / (111.0 * math.cos(bounds.southwest.latitude * math.pi / 180));

    int generatedCells = 0;
    for (double lat = bounds.southwest.latitude; 
         lat < bounds.northeast.latitude; 
         lat += latStep) {
      for (double lng = bounds.southwest.longitude; 
           lng < bounds.northeast.longitude; 
           lng += lngStep) {
        
        final cellCenter = LatLng(lat + latStep / 2, lng + lngStep / 2);
        
        // Calculate weighted AQI based on nearby points
        final interpolatedAQI = _interpolateAQI(
          cellCenter,
          dataPoints,
          influenceRadiusKm * 1000,
        );
        
        if (interpolatedAQI != null) {
          final color = AQIColors.getColor(interpolatedAQI.round());
          
          final cellPolygon = _createRectangularPolygon(
            southwest: LatLng(lat, lng),
            northeast: LatLng(lat + latStep, lng + lngStep),
            color: color,
            opacity: 0.25,
            id: 'interp_${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}',
          );
          
          polygons.add(cellPolygon);
          generatedCells++;
        }
      }
    }

    debugPrint(' Generated $generatedCells interpolated cells');
    return polygons;
  }

  /// Interpolate AQI using inverse distance weighting
  static double? _interpolateAQI(
    LatLng target,
    List<PollutionDataPoint> dataPoints,
    double maxDistance,
  ) {
    double weightedSum = 0;
    double weightSum = 0;
    int pointsUsed = 0;

    for (var point in dataPoints) {
      final distance = _calculateDistance(
        target.latitude,
        target.longitude,
        point.location.latitude,
        point.location.longitude,
      );

      if (distance > maxDistance) continue;

      // Inverse distance weighting (avoid division by zero)
      final weight = distance < 1 ? 1000.0 : 1.0 / distance;
      //  FIXED: Direct access to aqi
      weightedSum += point.data.aqi * weight;
      weightSum += weight;
      pointsUsed++;
    }

    if (weightSum > 0) {
      debugPrint('   Interpolated cell using $pointsUsed data points');
      return weightedSum / weightSum;
    }
    
    return null;
  }
}

/// Helper class for pollution data with location
class PollutionDataPoint {
  final PollutionData data;
  final LatLng location;

  PollutionDataPoint({
    required this.data,
    required this.location,
  });
}

/// Helper class for nearest data point search
class NearestDataPoint {
  final PollutionDataPoint data;
  final double distance; // in meters

  NearestDataPoint({
    required this.data,
    required this.distance,
  });
}

