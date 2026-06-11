import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_webservice/directions.dart' as gmaps;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/event_service.dart';
import '../models/pollution_model.dart';
import '../utils/route_risk_analyzer.dart';

/// Navigation step model with lane guidance
class NavigationStep {
  final String instruction;
  final String distance;
  final String duration;
  final LatLng startLocation;
  final LatLng endLocation;
  final String maneuver;
  final List<LaneInfo>? lanes;

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startLocation,
    required this.endLocation,
    required this.maneuver,
    this.lanes,
  });

  IconData get maneuverIcon {
    if (maneuver.contains('left')) return Icons.turn_left;
    if (maneuver.contains('right')) return Icons.turn_right;
    if (maneuver.contains('straight')) return Icons.straight;
    if (maneuver.contains('u-turn')) return Icons.u_turn_left;
    if (maneuver.contains('merge')) return Icons.merge;
    if (maneuver.contains('fork')) return Icons.call_split;
    if (maneuver.contains('ramp')) return Icons.ramp_right;
    if (maneuver.contains('roundabout')) return Icons.roundabout_right;
    return Icons.navigation;
  }
}

/// Lane information for lane guidance
class LaneInfo {
  final List<String> directions;
  final bool isActive;

  LaneInfo({
    required this.directions,
    required this.isActive,
  });
}

/// Route alternative model
class RouteAlternative {
  final String id;
  final List<LatLng> polylineCoordinates;
  final String distanceText;
  final String durationText;
  final num distanceMeters;
  final num durationSeconds;
  final String summary;
  final List<NavigationStep> steps;
  final bool isFastest;
  final bool isShortest;

  RouteAlternative({
    required this.id,
    required this.polylineCoordinates,
    required this.distanceText,
    required this.durationText,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.summary,
    required this.steps,
    this.isFastest = false,
    this.isShortest = false,
  });
}

class NavigationService extends ChangeNotifier {
  final _directions = gmaps.GoogleMapsDirections(
    apiKey: 'AIzaSyAmr6QANQ42SFt-o5XyVN0jlYlmuMV_dgQ',
  );
  final EventService _eventService = EventService();

  // Current active route
  List<LatLng> _polylineCoordinates = [];
  String _distanceText = '';
  String _durationText = '';
  LatLng? _destination;
  LatLng? _origin;
  bool _isNavigating = false;
  String? _destinationName;

  bool _arrivalAnnounced = false;
  DateTime? _navigationStartTime;

  // Turn-by-turn navigation
  List<NavigationStep> _steps = [];
  int _currentStepIndex = 0;
  NavigationStep? get currentStep =>
      _currentStepIndex < _steps.length ? _steps[_currentStepIndex] : null;
  NavigationStep? get nextStep => _currentStepIndex + 1 < _steps.length
      ? _steps[_currentStepIndex + 1]
      : null;

  // Distance to next turn
  double? _distanceToNextTurn;
  double? get distanceToNextTurn => _distanceToNextTurn;

  // Alternative routes
  final List<RouteAlternative> _alternativeRoutes = [];
  RouteAlternative? _selectedRoute;
  bool _isLoadingAlternatives = false;

  //  NEW: Risk analysis
  List<RouteRiskAssessment> _routeRiskAssessments = [];
  List<RouteRiskAssessment> get routeRiskAssessments => _routeRiskAssessments;
  List<EventModel> _lastRoadEvents = [];
  PollutionData? _lastPollutionData;

  RouteRiskAssessment? get selectedRouteRiskAssessment {
    if (_selectedRoute == null || _routeRiskAssessments.isEmpty) return null;
    try {
      return _routeRiskAssessments.firstWhere(
        (a) => a.route.id == _selectedRoute!.id,
      );
    } catch (e) {
      return null;
    }
  }

  // Off-track detection & rerouting
  bool _isOffTrack = false;
  DateTime? _lastRerouteTime;
  bool _isRerouting = false;
  static const double OFF_TRACK_THRESHOLD = 45.0;
  static const int MIN_REROUTE_INTERVAL_SECONDS = 10;
  int _rerouteCount = 0;

  // Route progress tracking
  double _routeProgress = 0.0;
  int _closestPolylineIndex = 0;
  EventModel? _pendingHazardAlert;
  final Set<String> _announcedHazardEventKeys = {};

  static const double hazardAlertDistanceMeters = 50.0;

  // Getters
  List<LatLng> get polylineCoordinates => _polylineCoordinates;
  String get distanceText => _distanceText;
  String get durationText => _durationText;
  LatLng? get destination => _destination;
  LatLng? get origin => _origin;
  bool get isNavigating => _isNavigating;
  String? get destinationName => _destinationName;
  List<NavigationStep> get allSteps => _steps;
  List<RouteAlternative> get alternativeRoutes => _alternativeRoutes;
  RouteAlternative? get selectedRoute => _selectedRoute;
  bool get isLoadingAlternatives => _isLoadingAlternatives;
  bool get isOffTrack => _isOffTrack;
  bool get isRerouting => _isRerouting;
  double get routeProgress => _routeProgress;
  int get rerouteCount => _rerouteCount;
  EventModel? consumePendingHazardAlert() {
    final alert = _pendingHazardAlert;
    _pendingHazardAlert = null;
    return alert;
  }

  /// Update cached risk context from UI/services so reroutes can reuse it.
  void setRiskContext({
    List<EventModel>? roadEvents,
    PollutionData? pollutionData,
  }) {
    if (roadEvents != null) {
      _lastRoadEvents = roadEvents;
    }
    if (pollutionData != null) {
      _lastPollutionData = pollutionData;
    }
  }

  Future<List<EventModel>> _resolveRoadEvents(
      List<EventModel>? roadEvents) async {
    if (roadEvents != null && roadEvents.isNotEmpty) {
      _lastRoadEvents = roadEvents;
      return roadEvents;
    }

    if (_lastRoadEvents.isNotEmpty) {
      return _lastRoadEvents;
    }

    try {
      final fetched = await _eventService.fetchEvents();
      _lastRoadEvents = fetched;
      return fetched;
    } catch (e) {
      debugPrint(' Risk context fetch failed: $e');
      return const <EventModel>[];
    }
  }

  ///  ENHANCED: Get routes with alternatives AND risk analysis
  Future<void> getRouteWithAlternatives({
    required LatLng origin,
    required LatLng destination,
    String? placeName,
    List<EventModel>? roadEvents,
    PollutionData? pollutionData,
    bool selectSafestRoute = true,
  }) async {
    try {
      debugPrint(' Fetching routes with alternatives...');

      final effectiveRoadEvents = await _resolveRoadEvents(roadEvents);
      final effectivePollution = pollutionData ?? _lastPollutionData;
      if (pollutionData != null) {
        _lastPollutionData = pollutionData;
      }

      _isLoadingAlternatives = true;
      _alternativeRoutes.clear();
      _routeRiskAssessments.clear();
      notifyListeners();

      final response = await _directions.directionsWithLocation(
        gmaps.Location(lat: origin.latitude, lng: origin.longitude),
        gmaps.Location(lat: destination.latitude, lng: destination.longitude),
        travelMode: gmaps.TravelMode.driving,
        alternatives: true,
      );

      if (response.isOkay && response.routes.isNotEmpty) {
        _origin = origin;
        _destination = destination;
        _destinationName = placeName;

        // Find fastest and shortest routes
        int fastestIndex = 0;
        int shortestIndex = 0;
        num minDuration = response.routes[0].legs[0].duration.value;
        num minDistance = response.routes[0].legs[0].distance.value;

        for (int i = 1; i < response.routes.length; i++) {
          final leg = response.routes[i].legs[0];
          if (leg.duration.value < minDuration) {
            minDuration = leg.duration.value;
            fastestIndex = i;
          }
          if (leg.distance.value < minDistance) {
            minDistance = leg.distance.value;
            shortestIndex = i;
          }
        }

        // Parse all routes
        for (int i = 0; i < response.routes.length; i++) {
          final route = response.routes[i];
          final leg = route.legs[0];

          // Parse polyline
          final polylinePoints = PolylinePoints();
          final result =
              polylinePoints.decodePolyline(route.overviewPolyline.points);
          final coordinates =
              result.map((p) => LatLng(p.latitude, p.longitude)).toList();

          // Parse steps with lane guidance
          final steps = <NavigationStep>[];
          for (var step in leg.steps) {
            List<LaneInfo>? lanes;
            if (step.maneuver != null && step.maneuver!.contains('turn')) {
              lanes = _parseLaneInfo(step);
            }

            steps.add(NavigationStep(
              instruction: _cleanHtmlInstruction(step.htmlInstructions),
              distance: step.distance.text,
              duration: step.duration.text,
              startLocation:
                  LatLng(step.startLocation.lat, step.startLocation.lng),
              endLocation: LatLng(step.endLocation.lat, step.endLocation.lng),
              maneuver: step.maneuver ?? 'straight',
              lanes: lanes,
            ));
          }

          final alternative = RouteAlternative(
            id: 'route_$i',
            polylineCoordinates: coordinates,
            distanceText: leg.distance.text,
            durationText: leg.duration.text,
            distanceMeters: leg.distance.value,
            durationSeconds: leg.duration.value,
            summary: route.summary,
            steps: steps,
            isFastest: i == fastestIndex,
            isShortest: i == shortestIndex,
          );

          _alternativeRoutes.add(alternative);
        }

        debugPrint(' Found ${_alternativeRoutes.length} alternative routes');

        //  NEW: Perform risk analysis if event data is available
        if (effectiveRoadEvents.isNotEmpty) {
          debugPrint(' Analyzing route risks...');

          _routeRiskAssessments = RouteRiskAnalyzer.analyzeAndRankRoutes(
            routes: _alternativeRoutes,
            roadEvents: effectiveRoadEvents,
            pollutionData: effectivePollution,
          );

          if (selectSafestRoute && _routeRiskAssessments.isNotEmpty) {
            // Select the safest route
            final safestAssessment = _routeRiskAssessments.first;
            await selectRoute(safestAssessment.route);

            debugPrint(
                ' Selected SAFEST route: ${safestAssessment.route.summary}');
            debugPrint('   Risk Level: ${safestAssessment.riskLevel}');
            debugPrint('   Hazards: ${safestAssessment.hazardCount}');
            debugPrint(
                '   Total Risk Score: ${safestAssessment.totalRiskScore.toStringAsFixed(1)}');
          } else {
            // Fallback to first route
            await selectRoute(_alternativeRoutes[0]);
          }
        } else {
          // No risk data available, select first route (usually fastest)
          debugPrint(' No hazard data available for risk analysis');
          await selectRoute(_alternativeRoutes[0]);
        }
      } else {
        throw Exception('Failed to get routes: ${response.errorMessage}');
      }
    } catch (e) {
      debugPrint(' Error fetching routes: $e');
      rethrow;
    } finally {
      _isLoadingAlternatives = false;
      notifyListeners();
    }
  }

  /// Parse lane information (simplified)
  List<LaneInfo>? _parseLaneInfo(gmaps.Step step) {
    if (step.maneuver == null) return null;

    if (step.maneuver!.contains('left')) {
      return [
        LaneInfo(directions: ['left'], isActive: true),
        LaneInfo(directions: ['through'], isActive: false),
        LaneInfo(directions: ['through'], isActive: false),
      ];
    } else if (step.maneuver!.contains('right')) {
      return [
        LaneInfo(directions: ['through'], isActive: false),
        LaneInfo(directions: ['through'], isActive: false),
        LaneInfo(directions: ['right'], isActive: true),
      ];
    }

    return null;
  }

  /// Select a route alternative
  Future<void> selectRoute(RouteAlternative route) async {
    _selectedRoute = route;
    _polylineCoordinates = route.polylineCoordinates;
    _distanceText = route.distanceText;
    _durationText = route.durationText;
    _steps = route.steps;
    _currentStepIndex = 0;
    _closestPolylineIndex = 0;
    _routeProgress = 0.0;
    _clearHazardAlertState();

    debugPrint(' Selected route: ${route.summary}');
    notifyListeners();
  }

  /// Legacy method for backward compatibility
  Future<void> getRoute({
    required LatLng origin,
    required LatLng destination,
    String? placeName,
  }) async {
    await getRouteWithAlternatives(
      origin: origin,
      destination: destination,
      placeName: placeName,
    );
  }

  /// Start active navigation
  void startNavigation({String? placeName}) {
    if (_polylineCoordinates.isEmpty || _destination == null) {
      debugPrint(' Cannot start navigation: no route available');
      return;
    }

    _isNavigating = true;
    _destinationName = placeName;
    _arrivalAnnounced = false;
    _navigationStartTime = DateTime.now();
    _currentStepIndex = 0;
    _isOffTrack = false;
    _rerouteCount = 0;
    _routeProgress = 0.0;
    _clearHazardAlertState();
    notifyListeners();

    debugPrint(' Navigation started with ${_steps.length} steps');
  }

  /// Update navigation progress with off-track detection
  void updateNavigationProgress(LatLng currentLocation) {
    if (!_isNavigating || currentStep == null) return;

    // Update closest polyline point for progress tracking
    _updateClosestPolylinePoint(currentLocation);

    // Calculate distance to current step's end location
    _distanceToNextTurn = _calculateDistance(
      currentLocation.latitude,
      currentLocation.longitude,
      currentStep!.endLocation.latitude,
      currentStep!.endLocation.longitude,
    );

    // Check if off-track
    final distanceToRoute = _calculateDistanceToPolyline(currentLocation);

    if (distanceToRoute > OFF_TRACK_THRESHOLD) {
      if (!_isOffTrack) {
        _isOffTrack = true;
        debugPrint(
            ' User is off-track (${distanceToRoute.toStringAsFixed(1)}m from route)');
        notifyListeners();

        _triggerRerouting(currentLocation);
      }
    } else {
      if (_isOffTrack) {
        _isOffTrack = false;
        debugPrint(' User is back on track');
        notifyListeners();
      }
    }

    // Move to next step if close enough (more tolerant for GPS jitter)
    if (_distanceToNextTurn! < 35 && _currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      debugPrint(' Moving to step ${_currentStepIndex + 1}/${_steps.length}');
      notifyListeners();
    }

    final hazardAlert = _findUpcomingHazardAlert(currentLocation);
    if (hazardAlert != null) {
      _pendingHazardAlert = hazardAlert;
    }
  }

  EventModel? _findUpcomingHazardAlert(LatLng currentLocation) {
    if (!_isNavigating ||
        _polylineCoordinates.isEmpty ||
        _lastRoadEvents.isEmpty) {
      return null;
    }

    EventModel? closestHazard;
    double closestDistance = double.infinity;

    for (final event in _lastRoadEvents) {
      final normalizedType = event.type.toLowerCase().trim();
      if (!_isPreAlertHazardType(normalizedType)) {
        continue;
      }

      final eventKey = _hazardEventKey(event);
      if (_announcedHazardEventKeys.contains(eventKey)) {
        continue;
      }

      final distanceToUser = _calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        event.lat,
        event.lon,
      );
      if (distanceToUser > hazardAlertDistanceMeters) {
        continue;
      }

      final distanceToRoute = _calculateDistanceToPolyline(event.position);
      if (distanceToRoute > RouteRiskAnalyzer.hazardProximityThreshold) {
        continue;
      }

      final eventRouteIndex = _nearestPolylinePointIndex(event.position);
      if (eventRouteIndex + 3 < _closestPolylineIndex) {
        continue;
      }

      if (distanceToUser < closestDistance) {
        closestDistance = distanceToUser;
        closestHazard = event;
      }
    }

    if (closestHazard != null) {
      _announcedHazardEventKeys.add(_hazardEventKey(closestHazard));
    }

    return closestHazard;
  }

  bool _isPreAlertHazardType(String normalizedType) {
    return normalizedType == 'pothole' ||
        normalizedType == 'speed bump' ||
        normalizedType == 'bump';
  }

  String _hazardEventKey(EventModel event) {
    return '${event.lat.toStringAsFixed(6)}_${event.lon.toStringAsFixed(6)}_${event.type.toLowerCase().trim()}';
  }

  int _nearestPolylinePointIndex(LatLng point) {
    if (_polylineCoordinates.isEmpty) {
      return -1;
    }

    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < _polylineCoordinates.length; i++) {
      final routePoint = _polylineCoordinates[i];
      final distance = _calculateDistance(
        point.latitude,
        point.longitude,
        routePoint.latitude,
        routePoint.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return closestIndex;
  }

  void _clearHazardAlertState() {
    _pendingHazardAlert = null;
    _announcedHazardEventKeys.clear();
  }

  /// Calculate distance from current location to polyline
  double _calculateDistanceToPolyline(LatLng point) {
    if (_polylineCoordinates.isEmpty) return double.infinity;

    double minDistance = double.infinity;

    for (int i = 0; i < _polylineCoordinates.length - 1; i++) {
      final segmentDistance = _distanceToLineSegment(
        point,
        _polylineCoordinates[i],
        _polylineCoordinates[i + 1],
      );

      if (segmentDistance < minDistance) {
        minDistance = segmentDistance;
      }
    }

    return minDistance;
  }

  /// Calculate distance from point to line segment
  double _distanceToLineSegment(
      LatLng point, LatLng lineStart, LatLng lineEnd) {
    final x = point.latitude;
    final y = point.longitude;
    final x1 = lineStart.latitude;
    final y1 = lineStart.longitude;
    final x2 = lineEnd.latitude;
    final y2 = lineEnd.longitude;

    final A = x - x1;
    final B = y - y1;
    final C = x2 - x1;
    final D = y2 - y1;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    double param = -1;

    if (lenSq != 0) param = dot / lenSq;

    double xx, yy;

    if (param < 0) {
      xx = x1;
      yy = y1;
    } else if (param > 1) {
      xx = x2;
      yy = y2;
    } else {
      xx = x1 + param * C;
      yy = y1 + param * D;
    }

    return _calculateDistance(x, y, xx, yy);
  }

  /// Update closest polyline point for progress tracking
  void _updateClosestPolylinePoint(LatLng currentLocation) {
    if (_polylineCoordinates.isEmpty) return;

    double minDistance = double.infinity;
    int closestIndex = _closestPolylineIndex;

    final searchStart =
        (_closestPolylineIndex - 10).clamp(0, _polylineCoordinates.length - 1);
    final searchEnd =
        (_closestPolylineIndex + 50).clamp(0, _polylineCoordinates.length - 1);

    for (int i = searchStart; i < searchEnd; i++) {
      final distance = _calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        _polylineCoordinates[i].latitude,
        _polylineCoordinates[i].longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    _closestPolylineIndex = closestIndex;
    _routeProgress = _closestPolylineIndex / _polylineCoordinates.length;
  }

  /// Trigger automatic rerouting
  Future<void> _triggerRerouting(LatLng currentLocation) async {
    if (_lastRerouteTime != null) {
      final elapsed = DateTime.now().difference(_lastRerouteTime!);
      if (elapsed.inSeconds < MIN_REROUTE_INTERVAL_SECONDS) {
        debugPrint(' Too soon to reroute (${elapsed.inSeconds}s elapsed)');
        return;
      }
    }

    if (_isRerouting || _destination == null) return;

    _isRerouting = true;
    _rerouteCount++;
    debugPrint(' Rerouting... (attempt #$_rerouteCount)');
    notifyListeners();

    try {
      await getRouteWithAlternatives(
        origin: currentLocation,
        destination: _destination!,
        placeName: _destinationName,
        roadEvents: _lastRoadEvents,
        pollutionData: _lastPollutionData,
      );

      _lastRerouteTime = DateTime.now();
      _isOffTrack = false;
      _currentStepIndex = 0;

      debugPrint(' Rerouting successful');
    } catch (e) {
      debugPrint(' Rerouting failed: $e');
    } finally {
      _isRerouting = false;
      notifyListeners();
    }
  }

  /// Manual reroute request
  Future<void> requestReroute(LatLng currentLocation) async {
    if (_destination == null) return;

    debugPrint(' Manual reroute requested');
    await _triggerRerouting(currentLocation);
  }

  /// Clean HTML instructions
  String _cleanHtmlInstruction(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .trim();
  }

  /// Stop navigation
  void stopNavigation() {
    _isNavigating = false;
    _arrivalAnnounced = false;
    _navigationStartTime = null;
    _currentStepIndex = 0;
    _distanceToNextTurn = null;
    _isOffTrack = false;
    _isRerouting = false;
    _rerouteCount = 0;
    _routeProgress = 0.0;
    _closestPolylineIndex = 0;
    _lastRerouteTime = null; //  CRITICAL FIX: Reset reroute timer
    _clearHazardAlertState();

    //  Key fix: Notify listeners to update UI properly
    notifyListeners();

    debugPrint(' Navigation stopped - route remains visible');
  }

  /// Clear route and navigation state
  void clearRoute() {
    _polylineCoordinates.clear();
    _distanceText = '';
    _durationText = '';
    _destination = null;
    _origin = null;
    _isNavigating = false;
    _destinationName = null;
    _arrivalAnnounced = false;
    _navigationStartTime = null;
    _steps.clear();
    _currentStepIndex = 0;
    _distanceToNextTurn = null;
    _alternativeRoutes.clear();
    _selectedRoute = null;
    _routeRiskAssessments.clear();
    _isOffTrack = false;
    _isRerouting = false;
    _rerouteCount = 0;
    _routeProgress = 0.0;
    _closestPolylineIndex = 0;
    _lastRerouteTime = null; //  ADDED: Reset reroute timer
    _clearHazardAlertState();
    notifyListeners();

    debugPrint(' Route cleared');
  }

  /// Arrival detection
  bool isNearDestination(LatLng currentLocation) {
    if (!_isNavigating || _destination == null || _arrivalAnnounced) {
      return false;
    }

    if (_navigationStartTime != null) {
      final elapsed = DateTime.now().difference(_navigationStartTime!);
      if (elapsed.inSeconds < 5) {
        return false;
      }
    }

    final distance = _calculateDistance(
      currentLocation.latitude,
      currentLocation.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    debugPrint(' Distance to destination: ${distance.toStringAsFixed(1)}m');

    final isNear = distance < 30;

    if (isNear) {
      _arrivalAnnounced = true;
      debugPrint(' ARRIVED!');
    }

    return isNear;
  }

  /// Calculate distance (Haversine formula)
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2));

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * 3.141592653589793 / 180;
  }

  /// Get distance to destination
  double? getDistanceToDestination(LatLng currentLocation) {
    if (_destination == null) return null;

    return _calculateDistance(
      currentLocation.latitude,
      currentLocation.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );
  }

  /// Get formatted distance
  String? getFormattedDistanceToDestination(LatLng currentLocation) {
    final distance = getDistanceToDestination(currentLocation);
    if (distance == null) return null;

    if (distance < 1000) {
      return '${distance.round()} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Get formatted distance to next turn
  String? getFormattedDistanceToNextTurn() {
    if (_distanceToNextTurn == null) return null;

    if (_distanceToNextTurn! < 1000) {
      return '${_distanceToNextTurn!.round()} m';
    } else {
      return '${(_distanceToNextTurn! / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Get remaining distance text
  String getRemainingDistanceText() {
    if (!_isNavigating || _steps.isEmpty) return _distanceText;

    int remainingMeters = 0;
    for (int i = _currentStepIndex; i < _steps.length; i++) {
      remainingMeters += 500;
    }

    if (remainingMeters < 1000) {
      return '$remainingMeters m';
    } else {
      return '${(remainingMeters / 1000).toStringAsFixed(1)} km';
    }
  }
}
