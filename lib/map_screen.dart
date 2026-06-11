import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import '../services/navigation_service.dart';
import '../services/event_service.dart';
import '../services/pollution_service.dart';
import '../services/trip_logger_service.dart';
import '../services/background_execution_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/place_details_sliding_panel.dart';
import '../widgets/pollution_overlay_widget.dart';
import '../widgets/pollution_details_sheet.dart';
import '../sensors/sensors.dart';
import '../widgets/navigation_status_widget.dart';
import '../widgets/route_alternatives_sheet.dart'
    hide CompactRouteSelectorButton;
import '../widgets/compass_speed_overlay.dart';
import '../widgets/hazard_details_sheet.dart';
import '../widgets/TurnInstructionsWidget.dart';
import '../widgets/log_sliding_panel.dart';
import '../widgets/enhanced_widgets.dart';
import '../services/alert_service.dart';
import '../utils/pollution_heatmap_generator.dart';
import '../widgets/category_buttons_widget.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Marker? _selectedMarker;
  late final LocationService _locationService;
  late final PlacesService _placesService;
  late final NavigationService _navigationService;

  late SensorMonitor _sensorMonitor;
  bool _isMonitoring = false;
  bool _isTripLogging = false;
  String? _activeTripId;
  String? _activeRouteType;

  final EventService _eventService = EventService();
  Set<Polyline> _eventLineMarkers = {};
  Set<Circle> _eventCircles = {};
  List<EventModel> _currentRoadEvents = [];
  bool _isLoadingEvents = false;
  String? _eventError;

  Timer? _autoRefreshTimer;
  Timer? _eventMapRefreshDebounce;
  bool _isFollowingLocation = true;
  bool _isProgrammaticMove = false;
  StreamSubscription<Position>? _locationUpdateSubscription;
  bool _showPollution = false;
  bool _mapReady = false;
  bool _eventsInitialized = false;
  Timer? _deferredEventInitTimer;
  Timer? _initialPollutionFetchTimer;

  String? _currentDisplayedPlaceId;
  // Add state variables to _MapScreenState (around line 50):
  Set<Polygon> _pollutionHeatmapPolygons = {};
  bool _showPollutionHeatmap = false;
  Position? _lastPosition;

  Position? _previousPosition;
  Position? _targetPosition;
  Timer? _interpolationTimer;
  double _interpolationProgress = 0.0;

// Add these new fields to _MapScreenState (around line 50):
  bool _userIsGesturing = false;
  Timer? _gestureTimer;
  bool _isAutoCameraUpdate = false;
  Timer? _autoResumeFollowTimer;

  Timer? _cameraUpdateThrottle;

  //  NEW: Compass control
  final GlobalKey<CompassSpeedOverlayState> _compassKey =
      GlobalKey<CompassSpeedOverlayState>();

  final GlobalKey<PlaceDetailsSlidingPanelState> _slidingPanelKey =
      GlobalKey<PlaceDetailsSlidingPanelState>();

  //  FIX #1: Add pollution overlay animation controller
  bool _isPollutionVisible = true;
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  DateTime? _lastSuccessfulEventFetch;
  bool _batteryOptimizationPromptShown = false;
  bool _startupPermissionPromptShown = false;
  bool _isRequestingLocationAccess = false;
  static const String _startupPermissionsCompletedKey =
      'startup_permissions_completed';
// 2 REPLACE initState() method (around line 65)
  @override
  void initState() {
    super.initState();

    _locationService = context.read<LocationService>();
    _placesService = context.read<PlacesService>();
    _navigationService = context.read<NavigationService>();

    _sensorMonitor = SensorMonitor(
      locationService: _locationService,
      navigationService: _navigationService,
    );

    _sensorMonitor.eventDetectedStream.listen((payload) {
      if (!mounted) return;
      final eventType = (payload['type'] ?? 'Event').toString();
      final confidence = (payload['confidence'] is num)
          ? (payload['confidence'] as num).toDouble()
          : double.tryParse(payload['confidence']?.toString() ?? '0') ?? 0.0;

      _showImmediateSnackbar(
        '$eventType detected (${(confidence * 100).toStringAsFixed(0)}% confidence)',
        eventType.toLowerCase().contains('pothole')
            ? Colors.deepOrange
            : Colors.amber.shade800,
      );

      _scheduleEventMapRefresh();
    });

    // Listen for model risk predictions and surface immediate alerts (snackbar + haptic)
    _sensorMonitor.riskPredictionStream.listen((payload) {
      if (!mounted) return;
      final label = (payload['label'] ?? '').toString();
      final rawScore = payload['score'];
      final score = (rawScore is num)
          ? rawScore.toDouble()
          : double.tryParse(rawScore?.toString() ?? '0') ?? 0.0;

      if (label == 'high_risk' || label == 'crash_like') {
        // AlertService already cooldowns overlay/audio; skip duplicate snackbars.
        if (AlertService.instance.isOnCooldown(label)) return;
        final msg =
            '${label.toUpperCase()} ${(score * 100).toStringAsFixed(0)}%';
        EnhancedSnackbar.show(
          context,
          message: msg,
          icon: label == 'crash_like' ? Icons.dangerous : Icons.warning,
          backgroundColor: label == 'crash_like' ? Colors.red : Colors.orange,
          duration: const Duration(seconds: 4),
          actionLabel: 'View',
          onAction: () {
            final lat = (payload['lat'] is num)
                ? (payload['lat'] as num).toDouble()
                : double.tryParse(payload['lat']?.toString() ?? '0') ?? 0.0;
            final lon = (payload['lon'] is num)
                ? (payload['lon'] as num).toDouble()
                : double.tryParse(payload['lon']?.toString() ?? '0') ?? 0.0;
            if (_mapController != null && lat != 0.0 && lon != 0.0) {
              _mapController!
                  .animateCamera(CameraUpdate.newLatLng(LatLng(lat, lon)));
            }
          },
        );

        // Fire richer alert (overlay, sound, system notification)
        try {
          AlertService.instance.showAlert(
            context,
            label: label,
            score: score,
            lat: (payload['lat'] is num)
                ? (payload['lat'] as num).toDouble()
                : null,
            lon: (payload['lon'] is num)
                ? (payload['lon'] as num).toDouble()
                : null,
          );
        } catch (_) {}

        try {
          if (label == 'crash_like') {
            HapticFeedback.heavyImpact();
            Future.delayed(const Duration(milliseconds: 120),
                () => HapticFeedback.heavyImpact());
          } else {
            HapticFeedback.mediumImpact();
          }
        } catch (_) {}
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placesService.addListener(_handlePlaceSelectionChange);
      _navigationService.addListener(_handleNavigationStateChange);

      _startPollutionMonitoring();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        unawaited(_handleStartupPermissions());
      });

      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        unawaited(_initializeTripLogger());
      });

      debugPrint(" Startup permission check and deferred services scheduled");
    });
  }

  Future<void> _handleStartupPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final permissionsCompleted =
        prefs.getBool(_startupPermissionsCompletedKey) ?? false;

    if (!mounted) {
      return;
    }

    if (permissionsCompleted) {
      await _ensureNotificationPermissionForAlerts();
      if (!_locationService.isTracking) {
        _locationService.startContinuousTracking();
      }
      await _locationService.refreshLocation();

      if (!mounted) {
        return;
      }

      _startLocationFollowing();
      if (_locationService.isTracking) {
        _showImmediateSnackbar(
          ' Location tracking enabled',
          Colors.green,
        );
      }
      return;
    }

    final permissionsReady =
        await BackgroundExecutionService.areRoadMonitoringPermissionsReady();
    if (permissionsReady) {
      await prefs.setBool(_startupPermissionsCompletedKey, true);
      await _ensureNotificationPermissionForAlerts();
      if (!_locationService.isTracking) {
        _locationService.startContinuousTracking();
      }
      await _locationService.refreshLocation();

      if (!mounted) {
        return;
      }

      _startLocationFollowing();
      if (_locationService.isTracking) {
        _showImmediateSnackbar(
          ' Location tracking enabled',
          Colors.green,
        );
      }
      return;
    }

    await _showStartupLocationPrompt();
  }

  Future<void> _showStartupLocationPrompt() async {
    if (_startupPermissionPromptShown || !mounted) {
      return;
    }

    _startupPermissionPromptShown = true;

    final shouldEnableLocation = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enable location tracking'),
          content: const Text(
            'RoadSense uses your location to show your position, keep the map centered, and run background monitoring. This one-time setup will request location access and the Android "allow all the time" background permission together.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Enable now'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldEnableLocation != true) {
      return;
    }

    await _requestLocationAccess();
  }

  Future<void> _ensureNotificationPermissionForAlerts() async {
    if (!mounted) {
      return;
    }

    final status = await Permission.notification.status;
    if (status.isGranted) {
      return;
    }

    final result = await Permission.notification.request();
    if (!result.isGranted && mounted) {
      _showImmediateSnackbar(
        ' Notification permission is disabled. System alerts will stay in-app only.',
        Colors.orange,
      );
    }
  }

  Future<void> _requestLocationAccess() async {
    if (_isRequestingLocationAccess) {
      return;
    }

    final permission = await _locationService.checkPermissions();
    if (!mounted) {
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      _showImmediateSnackbar(
        ' Location permission is permanently denied. Open app settings to enable it.',
        Colors.orange,
      );
      await Geolocator.openAppSettings();
      return;
    }

    if (permission == LocationPermission.denied) {
      final requestedPermission = await _locationService.requestPermissions();
      if (!mounted) {
        return;
      }

      if (requestedPermission == LocationPermission.denied) {
        _showImmediateSnackbar(
          ' Location permission denied. Please allow location access in the prompt.',
          Colors.orange,
        );
        return;
      }

      if (requestedPermission == LocationPermission.deniedForever) {
        _showImmediateSnackbar(
          ' Location permission is permanently denied. Open app settings to enable it.',
          Colors.orange,
        );
        await Geolocator.openAppSettings();
        return;
      }
    }

    setState(() {
      _isRequestingLocationAccess = true;
    });

    try {
      await _startLocationSetupAndPersist(requestWithPrompt: true);
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingLocationAccess = false;
        });
      }
    }
  }

  Future<void> _startLocationSetupAndPersist({
    required bool requestWithPrompt,
  }) async {
    if (requestWithPrompt) {
      await _locationService.startContinuousTrackingWithBackgroundSupport();
    } else {
      _locationService.startContinuousTracking();
    }
    await _locationService.refreshLocation();

    if (!mounted) {
      return;
    }

    if (_locationService.isTracking) {
      _startLocationFollowing();
      final permissionsReady =
          await BackgroundExecutionService.areRoadMonitoringPermissionsReady();
      if (permissionsReady) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_startupPermissionsCompletedKey, true);
      }
      _showImmediateSnackbar(
        ' Location tracking enabled',
        Colors.green,
      );
    } else if (_locationService.status.isNotEmpty) {
      _showImmediateSnackbar(
        ' ${_locationService.status}',
        Colors.orange,
      );
    }
  }

  Future<void> _initializeTripLogger() async {
    // Dedicated Google Sheets endpoint for GPS trip logging.
    const tripLoggerEndpoint =
        'https://script.google.com/macros/s/AKfycbwrQ_pD2ZtxhwOs4GsDSSQ3EmuBK_ieYvsucuVYs6pYHin9UWNx6h9gWr_ziXWVjP34Fw/exec';
    await TripLoggerService.initialize(apiUrl: tripLoggerEndpoint);
  }

// 3 ADD THIS NEW METHOD (after initState, around line 110)
  ///  FIX: Safe event initialization with configuration check
  Future<void> _initializeEvents() async {
    // Check if EventService is properly configured
    if (!EventService.isConfigured) {
      debugPrint(" EventService not configured - skipping event load");
      debugPrint(" Set API endpoint in main.dart or via AppConfig");
      setState(() {
        _eventError = "Events feature not configured";
      });

      // Show one-time info message (not repeated)
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _showImmediateSnackbar(
            ' Event monitoring unavailable (not configured)',
            Colors.grey,
          );
        }
      });
      return;
    }

    debugPrint(" Initializing event service...");

    // Load initial events
    await _loadEventLineMarkers();

    //  FIX: Only start auto-refresh if initial load succeeded
    if (_eventError == null) {
      _startAutoRefresh();
      debugPrint(" Event service initialized successfully");
    } else {
      debugPrint(
          " Event service initialization failed - auto-refresh disabled");
      _showImmediateSnackbar(
        ' Events unavailable. Tap refresh to retry.',
        Colors.orange,
      );
    }
  }

  // Handle navigation state changes (start/stop)
// Replace the existing _handleNavigationStateChange method
  void _handleNavigationStateChange() {
    final navigationService = context.read<NavigationService>();

    // When navigation stops, ensure UI state is properly updated
    if (!navigationService.isNavigating && mounted) {
      // Use a post-frame callback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            // Force UI rebuild to hide reroute button and update other states
          });
          debugPrint(" Navigation stopped - UI state updated");
        }
      });
    }
  }

  void _handlePlaceSelectionChange() {
    final placesService = context.read<PlacesService>();
    final selected = placesService.selectedPlace;

    if (selected == null) {
      if (_selectedMarker != null) {
        setState(() {
          _selectedMarker = null;
          _currentDisplayedPlaceId = null;
        });
        _slidingPanelKey.currentState?.hide();
      }
      return;
    }

    if (selected.placeId == _currentDisplayedPlaceId &&
        _selectedMarker != null) {
      debugPrint(' Place already displayed on map - skipping');
      return;
    }

    debugPrint(
        ' NEW place selected: ${selected.name} (ID: ${selected.placeId})');
    _onPlaceSelected();
  }

  void _startPollutionMonitoring() {
    final locationService = context.read<LocationService>();
    final pollutionService = context.read<PollutionService>();
    final navigationService = context.read<NavigationService>();

    final current = locationService.currentLocation;
    if (current != null) {
      // Defer first pollution fetch slightly to reduce startup main-thread contention.
      _initialPollutionFetchTimer?.cancel();
      _initialPollutionFetchTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        pollutionService.fetchAirQuality(current.latitude, current.longitude);
      });
    }

    locationService.addListener(() {
      final location = locationService.currentLocation;
      if (location != null && _showPollution) {
        pollutionService.smartUpdate(location.latitude, location.longitude);
        //  NEW: Update heat map when pollution data changes
        if (_showPollutionHeatmap) {
          _updatePollutionHeatmap();
        }
      }
    });
    //  NEW: Listen to pollution service changes
    pollutionService.addListener(() {
      navigationService.setRiskContext(
        roadEvents: _currentRoadEvents,
        pollutionData: pollutionService.currentPollution,
      );

      if (_showPollutionHeatmap && pollutionService.currentPollution != null) {
        _updatePollutionHeatmap();
      }
    });
  }

//  ADVANCED: Replace _startLocationFollowing with interpolated version
  void _startLocationFollowing({bool requestBackgroundSupport = false}) {
    final locationService = context.read<LocationService>();

    if (!locationService.isTracking && requestBackgroundSupport) {
      unawaited(locationService.startContinuousTrackingWithBackgroundSupport());
    } else if (!locationService.isTracking) {
      locationService.startContinuousTracking();
    }

    _locationUpdateSubscription?.cancel();
    _locationUpdateSubscription =
        locationService.locationUpdates.listen((position) {
      if (!mounted) return;

      if (_mapController == null || !_isFollowingLocation) return;

      // Update navigation progress
      final navService = context.read<NavigationService>();
      if (navService.isNavigating) {
        final currentLatLng = LatLng(position.latitude, position.longitude);
        navService.updateNavigationProgress(currentLatLng);

        final hazardEvent = navService.consumePendingHazardAlert();
        if (hazardEvent != null) {
          final distanceMeters = Geolocator.distanceBetween(
            currentLatLng.latitude,
            currentLatLng.longitude,
            hazardEvent.lat,
            hazardEvent.lon,
          );
          final hazardLabel = hazardEvent.type.toLowerCase().trim();
          final friendlyLabel = hazardEvent.type.trim().isEmpty
              ? 'Road hazard'
              : hazardEvent.type.trim();
          final title = '$friendlyLabel ahead';
          final message = distanceMeters <= 0
              ? 'Road hazard at your current location. Slow down now.'
              : 'About ${distanceMeters.toStringAsFixed(0)}m ahead. Slow down now.';

          try {
            AlertService.instance.showAlert(
              context,
              label: hazardLabel,
              score: 1.0,
              lat: hazardEvent.lat,
              lon: hazardEvent.lon,
              title: title,
              message: message,
            );
          } catch (_) {}
        }

        if (navService.isNearDestination(currentLatLng)) {
          navService.stopNavigation();
          _showImmediateSnackbar(
            'Arrived at destination',
            Colors.green,
          );
        }
      }

      // Set up interpolation targets
      _previousPosition = _lastPosition ?? position;
      _targetPosition = position;
      _interpolationProgress = 0.0;

      // Cancel previous interpolation
      _interpolationTimer?.cancel();

      // Use ~30 FPS updates to reduce camera pressure on lower-end devices.
      _interpolationTimer =
          Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!mounted || !_isFollowingLocation || _targetPosition == null) {
          timer.cancel();
          return;
        }

        _interpolationProgress += 0.33;

        if (_interpolationProgress >= 1.0) {
          _interpolationProgress = 1.0;
          timer.cancel();
        }

        _updateCameraWithInterpolation();
      });

      _lastPosition = position;
    });

    debugPrint(" Advanced interpolated tracking started (30 FPS smooth)");
  }

  Future<void> _toggleTripLogging() async {
    if (_isTripLogging) {
      final sentCount = TripLoggerService.currentTripSentCount;
      final queuedCount = TripLoggerService.currentTripQueuedCount;
      final pendingCount = TripLoggerService.pendingQueueSize;
      TripLoggerService.stopTrip();
      setState(() {
        _isTripLogging = false;
        _activeTripId = null;
        _activeRouteType = null;
      });
      _showImmediateSnackbar(
        ' Trip logging stopped • sent:$sentCount queued:$queuedCount pending:$pendingCount',
        Colors.red,
      );
      return;
    }

    final selectedRouteType = await _selectRouteType();
    if (selectedRouteType == null) {
      return;
    }

    final tripId =
        await TripLoggerService.startTrip(routeType: selectedRouteType);
    if (tripId == null) {
      _showImmediateSnackbar(
          ' Trip logger endpoint not configured', Colors.orange);
      return;
    }

    setState(() {
      _isTripLogging = true;
      _activeTripId = tripId;
      _activeRouteType = selectedRouteType;
    });

    // Capture a fresh starting coordinate for the trip.
    _captureInitialTripCoordinate();

    _showImmediateSnackbar(
        ' Trip logging started ($_activeRouteType)', Colors.green);
  }

  Future<String?> _selectRouteType() async {
    const routeTypes = <String>['city', 'highway', 'rough_road', 'mixed'];
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Route Type'),
        children: routeTypes
            .map(
              (routeType) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(routeType),
                child: Text(routeType),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _captureInitialTripCoordinate() async {
    try {
      // Attempt to get a fresh location for the trip start
      final freshLocation = await _locationService.getFreshLocation();

      if (freshLocation != null) {
        // Verify location is fresh (< 5 seconds old)
        final now = DateTime.now();
        final locationAge = now.difference(freshLocation.timestamp).inSeconds;

        if (locationAge < 5) {
          await TripLoggerService.logPosition(freshLocation);
          debugPrint(' Trip initial coordinate logged: '
              '${freshLocation.latitude.toStringAsFixed(6)}, '
              '${freshLocation.longitude.toStringAsFixed(6)} (age: ${locationAge}s)');
        } else {
          debugPrint(
              ' Trip start: fresh location too old (${locationAge}s), using cached');
          // Fallback to cached location if fresh location is stale
          final cached = _locationService.currentLocation;
          if (cached != null) {
            await TripLoggerService.logPosition(cached);
          }
        }
      } else {
        debugPrint(
            ' Trip start: could not get fresh location, attempting cached');
        // Final fallback to cached location
        final cached = _locationService.currentLocation;
        if (cached != null) {
          await TripLoggerService.logPosition(cached);
        } else {
          debugPrint(' Trip start: no location available (fresh or cached)');
        }
      }
    } catch (error) {
      debugPrint(' Trip initial coordinate capture failed: $error');
      // Attempt fallback with cached location
      try {
        final cached = _locationService.currentLocation;
        if (cached != null) {
          await TripLoggerService.logPosition(cached);
          debugPrint(' Trip start: logged cached location after error');
        }
      } catch (fallbackError) {
        debugPrint(
            ' Trip start: fallback coordinate capture also failed: $fallbackError');
      }
    }
  }

//  Interpolation update method
  void _updateCameraWithInterpolation() {
    if (_previousPosition == null ||
        _targetPosition == null ||
        _mapController == null) {
      return;
    }

    final speedKmh = _targetPosition!.speed * 3.6;

    // Ease-out interpolation for smooth deceleration
    final t = _easeOutCubic(_interpolationProgress);

    // Interpolate position
    final lat =
        _lerp(_previousPosition!.latitude, _targetPosition!.latitude, t);
    final lng =
        _lerp(_previousPosition!.longitude, _targetPosition!.longitude, t);
    final heading =
        _lerpAngle(_previousPosition!.heading, _targetPosition!.heading, t);

    // Speed-adaptive camera settings
    double targetZoom;
    double targetTilt;
    LatLng targetPosition = LatLng(lat, lng);

    if (speedKmh > 40) {
      targetZoom = 16.5;
      targetTilt = 60;

      // Predict ahead at high speeds
      const predictionTime = 0.25;
      final distanceAhead = _targetPosition!.speed * predictionTime;
      final latOffset =
          distanceAhead * 0.000009 * math.cos(heading * math.pi / 180);
      final lngOffset =
          distanceAhead * 0.000009 * math.sin(heading * math.pi / 180);

      targetPosition = LatLng(lat + latOffset, lng + lngOffset);
    } else if (speedKmh > 15) {
      targetZoom = 17;
      targetTilt = 45;
    } else {
      targetZoom = 18;
      targetTilt = 0;
    }

    // Mark internal camera updates so gesture handlers don't disable follow mode.
    _isProgrammaticMove = true;
    _isAutoCameraUpdate = true;

    // Instant camera update (no animation needed due to interpolation)
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: targetPosition,
          zoom: targetZoom,
          bearing: heading,
          tilt: targetTilt,
        ),
      ),
    );

    _cameraUpdateThrottle?.cancel();
    _cameraUpdateThrottle = Timer(const Duration(milliseconds: 120), () {
      _isAutoCameraUpdate = false;
      _isProgrammaticMove = false;
    });
  }

  void _scheduleAutoResumeFollow() {
    _autoResumeFollowTimer?.cancel();
    _autoResumeFollowTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _isFollowingLocation) return;

      final isMoving = (_locationService.speedKmh ?? 0.0) > 2.0;
      final isNavigating = _navigationService.isNavigating;
      if (!isMoving && !isNavigating) return;

      setState(() {
        _isFollowingLocation = true;
      });
      _startLocationFollowing();
      _showImmediateSnackbar('Auto-follow resumed', Colors.blue);
    });
  }

//  Interpolation helper methods
  double _lerp(double start, double end, double t) {
    return start + (end - start) * t;
  }

  double _lerpAngle(double start, double end, double t) {
    // Handle angle wrapping (0-360)
    double diff = end - start;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (start + diff * t) % 360;
  }

  double _easeOutCubic(double t) {
    return 1 - math.pow(1 - t, 3).toDouble();
  }

  Future<void> _recenterToCurrentLocation() async {
    final locationService = context.read<LocationService>();
    final navigationService = context.read<NavigationService>();
    final placesService = context.read<PlacesService>();

    // Clear route if user has searched a place (but not navigating)
    if (placesService.selectedPlace != null &&
        !navigationService.isNavigating) {
      navigationService.clearRoute();
    }

    setState(() {
      _isProgrammaticMove = true;
      _isFollowingLocation = true; // Always enable following when recentring
    });

    final freshLocation = await locationService.getFreshLocation();

    if (freshLocation != null && _mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(freshLocation.latitude, freshLocation.longitude),
          17,
        ),
      );

      // Always restart location following
      _startLocationFollowing();

      //  FIX #2: Use immediate snackbar
      _showImmediateSnackbar(
        ' Location following enabled',
        Colors.blue,
      );

      debugPrint(" Recentered to current location");
    } else {
      final current = locationService.currentLocation;
      if (current != null && _mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(current.latitude, current.longitude),
            17,
          ),
        );

        // Always restart location following
        _startLocationFollowing();

        debugPrint(" Recentered to cached location");
      } else {
        //  FIX #2: Use immediate snackbar
        _showImmediateSnackbar(
          ' Unable to get current location',
          Colors.red,
        );
      }
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isProgrammaticMove = false;
        });
      }
    });
  }

  //  FIX #2: Immediate snackbar method that clears previous ones
  void _showImmediateSnackbar(String message, Color backgroundColor) {
    _scaffoldKey.currentState?.clearSnackBars();
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _togglePollutionOverlay() {
    setState(() {
      _showPollution = !_showPollution;
      _isPollutionVisible = _showPollution;
    });

    if (_showPollution) {
      final locationService = context.read<LocationService>();
      final pollutionService = context.read<PollutionService>();
      final current = locationService.currentLocation;

      if (current != null) {
        pollutionService.fetchAirQuality(current.latitude, current.longitude);
      }
    }

    //  FIX #2: Use immediate snackbar
    _showImmediateSnackbar(
      _showPollution
          ? ' Pollution monitoring enabled'
          : ' Pollution monitoring disabled',
      _showPollution ? Colors.green : Colors.grey,
    );
  }

  // Add method to toggle heat map (around line 350):
  void _togglePollutionHeatmap() {
    //  NEW: Check if pollution monitoring is enabled first
    if (!_showPollution && !_showPollutionHeatmap) {
      _showImmediateSnackbar(
        ' Enable pollution monitoring first to get required data',
        Colors.orange,
      );
      return;
    }
    setState(() {
      _showPollutionHeatmap = !_showPollutionHeatmap;
    });

    if (_showPollutionHeatmap) {
      _updatePollutionHeatmap();

      _showImmediateSnackbar(
        ' Pollution heat map enabled',
        Colors.green,
      );
    } else {
      setState(() {
        _pollutionHeatmapPolygons.clear();
      });

      _showImmediateSnackbar(
        ' Pollution heat map disabled',
        Colors.grey,
      );
    }
  }

// Add method to generate heat map (around line 380):
  void _updatePollutionHeatmap() {
    final pollutionService = context.read<PollutionService>();
    final locationService = context.read<LocationService>();
    final current = locationService.currentLocation;

    if (current == null || pollutionService.currentPollution == null) {
      debugPrint(' Cannot generate heat map: missing data');
      return;
    }

    final pollution = pollutionService.currentPollution!;
    final center = LatLng(current.latitude, current.longitude);

    setState(() {
      _pollutionHeatmapPolygons = PollutionHeatmapGenerator.generateHeatmap(
        pollution: pollution,
        center: center,
        zones: 4, // 4 concentric zones
        maxRadiusKm: 3.0, // 3km radius
      );
    });

    debugPrint(' Generated ${_pollutionHeatmapPolygons.length} heat map zones');
  }

  void _showPollutionDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PollutionDetailsSheet(),
    );
  }

  @override
  void dispose() {
    _interpolationTimer?.cancel();
    _cameraUpdateThrottle?.cancel();
    _gestureTimer?.cancel();
    _autoResumeFollowTimer?.cancel();
    _deferredEventInitTimer?.cancel();
    _initialPollutionFetchTimer?.cancel();
    _eventMapRefreshDebounce?.cancel();
    _sensorMonitor.stopMonitoring();
    _autoRefreshTimer?.cancel();
    _locationUpdateSubscription?.cancel();
    _mapController?.dispose();

    _placesService.removeListener(_handlePlaceSelectionChange);
    _navigationService.removeListener(_handleNavigationStateChange);

    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();

    //  FIX: Only auto-refresh if events are working (no error state)
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isLoadingEvents && _eventError == null) {
        debugPrint(" Auto-refreshing events (30s timer)");
        _loadEventLineMarkers(forceRefresh: true);
      } else if (_eventError != null) {
        debugPrint(" Auto-refresh skipped (error state)");
      }
    });

    debugPrint(" Auto-refresh timer started (every 30s)");
  }

  void _toggleMonitoring() {
    if (_isMonitoring) {
      _sensorMonitor.stopMonitoring();
      //  FIX #2: Use immediate snackbar
      _showImmediateSnackbar(
        ' Stopped sensor monitoring',
        Colors.red,
      );
      setState(() {
        _isMonitoring = false;
      });
      return;
    }

    unawaited(_startMonitoringWithBackgroundSupport());
  }

  Future<void> _startMonitoringWithBackgroundSupport() async {
    final preparationResult =
        await BackgroundExecutionService.ensureReadyForRoadMonitoring();

    if (!mounted) return;

    if (!preparationResult.canStart) {
      _showImmediateSnackbar(
        preparationResult.userMessage ??
            'Unable to start monitoring with background support.',
        Colors.orange,
      );
      return;
    }

    await _sensorMonitor.startMonitoringWithBackgroundSupport();
    _showImmediateSnackbar(
      ' Started sensor monitoring with background support',
      Colors.green,
    );

    setState(() {
      _isMonitoring = true;
    });

    if (preparationResult.needsBatteryOptimizationExemption &&
        !_batteryOptimizationPromptShown) {
      _batteryOptimizationPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Allow screen-off tracking'),
              content: const Text(
                'To keep RoadSense running when the screen is off, allow it to ignore battery optimizations. Android can otherwise pause GPS and sensor updates on some devices.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await BackgroundExecutionService
                        .openBatteryOptimizationSettings();
                  },
                  child: const Text('Open settings'),
                ),
              ],
            );
          },
        );
      });
    }
  }

  void _scheduleEventMapRefresh() {
    _eventMapRefreshDebounce?.cancel();
    _eventMapRefreshDebounce = Timer(const Duration(seconds: 4), () {
      if (!mounted || _isLoadingEvents) return;
      _loadEventLineMarkers(forceRefresh: true);
    });
  }

// 5 REPLACE _loadEventLineMarkers() method (around line 530)
  Future<void> _loadEventLineMarkers({bool forceRefresh = false}) async {
    if (_isLoadingEvents) return;

    final navigationService = context.read<NavigationService>();
    final pollutionService = context.read<PollutionService>();

    setState(() {
      _isLoadingEvents = true;
      //  Clear error state on force refresh
      if (forceRefresh) {
        _eventError = null;
      }
    });

    try {
      debugPrint(
          " Fetching events${forceRefresh ? ' (force refresh)' : ' (using cache)'}...");

      //  FIX: Pass forceRefresh parameter to service
      final List<EventModel> events = await _eventService.fetchEvents(
        forceRefresh: forceRefresh,
      );
      _currentRoadEvents = events;
      navigationService.setRiskContext(
        roadEvents: events,
        pollutionData: pollutionService.currentPollution,
      );

      final markers = _createEnhancedEventMarkers(events);
      _eventLineMarkers = markers['polylines'] as Set<Polyline>;
      _eventCircles = markers['circles'] as Set<Circle>;

      if (mounted) {
        setState(() {
          _eventError = null; //  Clear error on success
          _lastSuccessfulEventFetch = DateTime.now(); //  Track last success
        });

        //  Only show success message for manual refreshes or first load
        if (_autoRefreshTimer == null ||
            !_autoRefreshTimer!.isActive ||
            forceRefresh) {
          _showImmediateSnackbar(
            ' Loaded ${events.length} road events',
            Colors.green,
          );
        }
      }

      debugPrint(" Loaded ${events.length} enhanced event markers");
    } catch (e) {
      debugPrint(" Failed to load event markers: $e");

      if (mounted) {
        setState(() {
          _eventError = e.toString();
        });

        //  FIX: Better error message based on configuration
        final errorMessage = EventService.isConfigured
            ? ' Failed to load events from server'
            : ' Events not configured properly';

        _scaffoldKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _loadEventLineMarkers(forceRefresh: true),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  Map<String, Set<dynamic>> _createEnhancedEventMarkers(
      List<EventModel> events) {
    final polylines = <Polyline>{};
    final circles = <Circle>{};

    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      final eventType = event.type.toLowerCase().trim();
      final position = event.position;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final markerKey = '${timestamp}_$index';

      // Outer glow circle
      circles.add(Circle(
        circleId: CircleId('glow_${event.lat}_${event.lon}_$markerKey'),
        center: position,
        radius: 15,
        fillColor: _getEventColor(eventType).withValues(alpha: 0.15),
        strokeColor: _getEventColor(eventType).withValues(alpha: 0.3),
        strokeWidth: 1,
        zIndex: 1,
        consumeTapEvents: true, //  NEW
        onTap: () => _showHazardDetails(event), //  NEW
      ));

      // Main marker circle
      circles.add(Circle(
        circleId: CircleId('main_${event.lat}_${event.lon}_$markerKey'),
        center: position,
        radius: 8,
        fillColor: _getEventColor(eventType).withValues(alpha: 0.6),
        strokeColor: _getEventColor(eventType),
        strokeWidth: 3,
        zIndex: 2,
        consumeTapEvents: true, //  NEW
        onTap: () => _showHazardDetails(event), //  NEW
      ));

      final iconLines = _createWarningIcon(position, eventType);
      for (var i = 0; i < iconLines.length; i++) {
        polylines.add(Polyline(
          polylineId:
              PolylineId('icon_${event.lat}_${event.lon}_${i}_$markerKey'),
          points: iconLines[i],
          color: Colors.white,
          width: 3,
          geodesic: false,
          zIndex: 3,
        ));
      }

      polylines.add(Polyline(
        polylineId: PolylineId('ring_${event.lat}_${event.lon}_$markerKey'),
        points: _createCirclePoints(position, 8),
        color: _getEventColor(eventType),
        width: 4,
        geodesic: false,
        zIndex: 2,
      ));
    }

    return {
      'polylines': polylines,
      'circles': circles,
    };
  }

  List<List<LatLng>> _createWarningIcon(LatLng center, String eventType) {
    const iconSize = 0.00004;

    if (eventType == 'pothole') {
      return [
        [
          LatLng(center.latitude + iconSize, center.longitude - iconSize),
          LatLng(center.latitude - iconSize, center.longitude + iconSize),
        ],
        [
          LatLng(center.latitude + iconSize, center.longitude + iconSize),
          LatLng(center.latitude - iconSize, center.longitude - iconSize),
        ],
      ];
    } else {
      return [
        [
          LatLng(center.latitude + iconSize, center.longitude),
          LatLng(center.latitude - iconSize, center.longitude),
        ],
        [
          LatLng(center.latitude, center.longitude - iconSize),
          LatLng(center.latitude, center.longitude + iconSize),
        ],
      ];
    }
  }

  List<LatLng> _createCirclePoints(LatLng center, double radiusMeters) {
    const int points = 32;
    final List<LatLng> circlePoints = [];
    final double radiusDegrees = radiusMeters / 111320;

    for (int i = 0; i <= points; i++) {
      final double angle = (i * 360 / points) * math.pi / 180;
      final double lat = center.latitude + (radiusDegrees * math.cos(angle));
      final double lng = center.longitude +
          (radiusDegrees *
              math.sin(angle) /
              math.cos(center.latitude * math.pi / 180));
      circlePoints.add(LatLng(lat, lng));
    }

    return circlePoints;
  }

  Color _getEventColor(String eventType) {
    switch (eventType.toLowerCase().trim()) {
      case 'pothole':
        return const Color(0xFFFF0000);
      case 'speed bump':
      case 'bump':
        return const Color(0xFFFF8C00);
      case 'rotation':
        return const Color(0xFF0066FF);
      case 'vibration':
        return const Color(0xFFFFD700);
      case 'impact':
        return const Color(0xFFFF1744);
      default:
        return const Color(0xFF9C27B0);
    }
  }

// 2 UPDATE _onPlaceSelected() method (replace existing method around line ~400):
  void _onPlaceSelected() async {
    final placesService = context.read<PlacesService>();
    final navigationService = context.read<NavigationService>();
    final locationService = context.read<LocationService>();
    final currentPollution = context.read<PollutionService>().currentPollution;

    final selected = placesService.selectedPlace;

    if (selected == null) {
      debugPrint(' No place selected');
      return;
    }

    if (_mapController == null) {
      debugPrint(' Map not ready - waiting...');
      await Future.delayed(const Duration(milliseconds: 500));
      if (_mapController == null) {
        debugPrint(' Map controller still null - aborting');
        _showImmediateSnackbar(
          ' Map not ready yet. Please try again.',
          Colors.orange,
        );
        return;
      }
    }

    final lat = selected.geometry?.location.lat;
    final lon = selected.geometry?.location.lng;

    if (lat == null || lon == null || lat == 0.0 || lon == 0.0) {
      debugPrint(' Invalid coordinates: lat=$lat, lon=$lon');
      _showImmediateSnackbar(
        ' Could not get place location',
        Colors.red,
      );
      return;
    }

    final destination = LatLng(lat, lon);
    final current = locationService.currentLocation;

    setState(() {
      _isProgrammaticMove = true;
    });

    if (_isFollowingLocation) {
      setState(() {
        _isFollowingLocation = false;
      });
      _locationUpdateSubscription?.cancel();
      debugPrint(' Auto-follow disabled for place selection');
    }

    try {
      setState(() {
        _selectedMarker = Marker(
          markerId: MarkerId('selected_place_${selected.placeId}'),
          position: destination,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: selected.name,
            snippet: selected.vicinity ?? selected.formattedAddress ?? '',
          ),
        );
        _currentDisplayedPlaceId = selected.placeId;
      });

      final cameraFuture = _animateToPlace(destination, current);

      //  UPDATED: Use getRouteWithAlternatives instead of getRoute
      final Future<void> routeFuture = current != null
          ? navigationService.getRouteWithAlternatives(
              origin: LatLng(current.latitude, current.longitude),
              destination: destination,
              placeName: selected.name,
              roadEvents: _currentRoadEvents,
              pollutionData: currentPollution,
            )
          : Future.value();

      // Await camera move quickly, but don't block UI waiting for routes.
      // Start route fetch in background so the bottom sheet can show immediately
      // and display a loading indicator while alternatives arrive.
      await cameraFuture;
      if (current != null) {
        routeFuture.catchError(
            (e) => debugPrint('getRouteWithAlternatives failed: $e'));
      }

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _slidingPanelKey.currentState?.show();
          _slidingPanelKey.currentState?.expand();
        });

        //  NEW: Show route alternatives if multiple routes found
        if (navigationService.alternativeRoutes.length > 1) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            _showRouteAlternatives();
          }
        }
      }
    } catch (e) {
      debugPrint(' Error in place selection: $e');
      _showImmediateSnackbar(
        'Failed to show place: $e',
        Colors.red,
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _isProgrammaticMove = false;
          });
        }
      });
    }
  }

// 3 ADD NEW METHOD for showing route alternatives (add after _onPlaceSelected):
  void _showRouteAlternatives() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        builder: (_, controller) => RouteAlternativesSheet(
          onRouteSelected: () {
            setState(() {}); // Refresh polylines
            _slidingPanelKey.currentState?.show();
            _slidingPanelKey.currentState?.expand();
            _showImmediateSnackbar(
              ' Route updated',
              Colors.blue,
            );
          },
        ),
      ),
    ).whenComplete(() {
      if (!mounted) return;
      _slidingPanelKey.currentState?.show();
    });
  }

  Future<void> _animateToPlace(LatLng destination, Position? current) async {
    if (_mapController == null) return;

    try {
      if (current != null) {
        final origin = LatLng(current.latitude, current.longitude);
        final bounds = _calculateBounds(origin, destination);

        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100),
        );
      } else {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(destination, 15),
        );
      }
    } catch (e) {
      debugPrint(' Camera animation error: $e');
    }
  }

  LatLngBounds _calculateBounds(LatLng origin, LatLng destination) {
    final southwest = LatLng(
      origin.latitude < destination.latitude
          ? origin.latitude
          : destination.latitude,
      origin.longitude < destination.longitude
          ? origin.longitude
          : destination.longitude,
    );

    final northeast = LatLng(
      origin.latitude > destination.latitude
          ? origin.latitude
          : destination.latitude,
      origin.longitude > destination.longitude
          ? origin.longitude
          : destination.longitude,
    );

    return LatLngBounds(southwest: southwest, northeast: northeast);
  }

  void _showHazardDetails(EventModel event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, //  Important for custom height
      backgroundColor: Colors.transparent,
      isDismissible: true, //  Allow dismiss by tapping outside
      enableDrag: true, //  Allow drag to dismiss
      builder: (_) => HazardDetailsSheet(event: event),
    );
  }

  void _clearSelection() {
    final placesService = context.read<PlacesService>();
    final navigationService = context.read<NavigationService>();
    final locationService = context.read<LocationService>();

    _currentDisplayedPlaceId = null;

    //  Clear in correct order
    _slidingPanelKey.currentState?.hide(); // Hide panel first
    placesService.clearSelectedPlace(); // Then clear data
    navigationService.clearRoute();

    setState(() {
      _selectedMarker = null;
    });

    _compassKey.currentState?.hide();

    //  Recenter map
    final current = locationService.currentLocation;
    if (current != null && _mapController != null) {
      setState(() {
        _isProgrammaticMove = true;
      });

      _mapController!
          .animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(current.latitude, current.longitude),
          17,
        ),
      )
          .then((_) {
        if (mounted) {
          setState(() {
            _isProgrammaticMove = false;
          });
        }
      });

      if (!_isFollowingLocation) {
        setState(() {
          _isFollowingLocation = true;
        });
        _startLocationFollowing();
      }
    }
  }

  Widget _buildEventLoadingIndicator() {
    if (!_isLoadingEvents) return const SizedBox.shrink();

    return Positioned(
      top: 180,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Loading road events...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

// 6 REPLACE _buildEventErrorIndicator() method (around line 990)
  Widget _buildEventErrorIndicator() {
    if (_eventError == null) return const SizedBox.shrink();

    //  Calculate time since last successful fetch
    String timeInfo = '';
    if (_lastSuccessfulEventFetch != null) {
      final elapsed = DateTime.now().difference(_lastSuccessfulEventFetch!);
      if (elapsed.inMinutes < 60) {
        timeInfo = ' (${elapsed.inMinutes}m ago)';
      } else if (elapsed.inHours < 24) {
        timeInfo = ' (${elapsed.inHours}h ago)';
      } else {
        timeInfo = ' (>24h ago)';
      }
    }

    return Positioned(
      top: 180,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {
          //  Tap to retry with force refresh
          setState(() => _eventError = null);
          _loadEventLineMarkers(forceRefresh: true);

          //  Restart auto-refresh if it was stopped
          if (_autoRefreshTimer == null || !_autoRefreshTimer!.isActive) {
            _startAutoRefresh();
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  EventService.isConfigured
                      ? 'Events offline$timeInfo - Tap to retry'
                      : 'Events not configured',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.refresh, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  ///  NEW: Build animated user marker during navigation
  Marker? _buildNavigationUserMarker(
      LocationService locationService, NavigationService navigationService) {
    final current = locationService.currentLocation;
    if (current == null || !navigationService.isNavigating) return null;

    return Marker(
      markerId: const MarkerId('navigation_user_location'),
      position: LatLng(current.latitude, current.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      anchor: const Offset(0.5, 0.5),
      rotation: current.heading,
      flat: true,
      zIndexInt: 1000, // Always on top
      infoWindow: InfoWindow(
        title: 'You are here',
        snippet: '${(current.speed * 3.6).toStringAsFixed(0)} km/h',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final navigationService = context.watch<NavigationService>();
    final placesService = context.watch<PlacesService>();
    final current = locationService.currentLocation;

    final isPanelVisible = placesService.selectedPlace != null;

    return ScaffoldMessenger(
      key: _scaffoldKey,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // 1. Google Map or placeholder while waiting for location.
            if (current != null)
              RefreshIndicator(
                onRefresh: _loadEventLineMarkers,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(current.latitude, current.longitude),
                    zoom: 15,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: {
                    if (_selectedMarker != null) _selectedMarker!,
                    //  FIX #2: Add animated user marker during navigation
                    if (_buildNavigationUserMarker(
                            locationService, navigationService) !=
                        null)
                      _buildNavigationUserMarker(
                          locationService, navigationService)!,
                  },
                  circles: _eventCircles,
                  polylines: {
                    ..._eventLineMarkers,

                    // Show all alternative routes (non-selected ones as gray)
                    ...navigationService.alternativeRoutes
                        .where((route) =>
                            route.id != navigationService.selectedRoute?.id)
                        .map((route) => Polyline(
                              polylineId: PolylineId(route.id),
                              points: route.polylineCoordinates,
                              color: Colors.grey.withValues(alpha: 0.4),
                              width: 4,
                              patterns: [
                                PatternItem.dash(10),
                                PatternItem.gap(10)
                              ],
                              consumeTapEvents: true,
                              onTap: () {
                                navigationService.selectRoute(route);
                                _showImmediateSnackbar(
                                  ' Switched to ${route.summary}',
                                  Colors.blue,
                                );
                              },
                            ))
                        .toSet(),

                    // Selected route (main route)
                    if (navigationService.polylineCoordinates.isNotEmpty)
                      Polyline(
                        polylineId: const PolylineId('selected_route'),
                        points: navigationService.polylineCoordinates,
                        color: navigationService.isNavigating
                            ? Colors.blue
                            : Colors.blue.withValues(alpha: 0.7),
                        width: navigationService.isNavigating ? 6 : 5,
                        patterns: navigationService.isNavigating
                            ? []
                            : [PatternItem.dash(10), PatternItem.gap(5)],
                      ),
                  },
                  onMapCreated: (controller) {
                    _mapController = controller;
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        setState(() {
                          _mapReady = true;
                        });
                        if (!_eventsInitialized) {
                          _eventsInitialized = true;
                          // Defer initial event fetch until first map frame settles.
                          _deferredEventInitTimer?.cancel();
                          _deferredEventInitTimer =
                              Timer(const Duration(milliseconds: 900), () {
                            if (mounted) {
                              _initializeEvents();
                            }
                          });
                        }
                        debugPrint(" Map is ready for place selection");
                      }
                    });
                  },
                  onCameraMoveStarted: () {
                    // Detect when user starts manually moving the camera
                    if (_isFollowingLocation &&
                        !_isProgrammaticMove &&
                        !_isAutoCameraUpdate) {
                      _userIsGesturing = true;
                      debugPrint(" User gesture detected");
                    }
                  },
                  onCameraMove: (position) {
                    if (!_mapReady) return;
                  },
                  onCameraIdle: () {
                    // Only disable auto-follow if user was actually gesturing
                    if (_userIsGesturing &&
                        _isFollowingLocation &&
                        !_isProgrammaticMove &&
                        !_isAutoCameraUpdate) {
                      _gestureTimer?.cancel();
                      _gestureTimer =
                          Timer(const Duration(milliseconds: 100), () {
                        if (mounted) {
                          setState(() {
                            _isFollowingLocation = false;
                          });
                          _scheduleAutoResumeFollow();
                          _showImmediateSnackbar(
                            'Temporarily paused auto-follow',
                            Colors.orange,
                          );
                          debugPrint(
                              " Auto-follow disabled - user moved camera");
                        }
                      });
                    }
                    _userIsGesturing = false;
                  },
                  polygons: {
                    ..._pollutionHeatmapPolygons,
                  },
                ),
              )
            else if (locationService.status.toLowerCase().contains('permission') ||
                locationService.status.toLowerCase().contains('disabled') ||
                locationService.status.toLowerCase().contains('denied'))
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      elevation: 10,
                      color: Colors.white.withValues(alpha: 0.96),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isRequestingLocationAccess
                                    ? Icons.hourglass_top
                                    : Icons.location_on,
                                size: 34,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Location access needed',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              locationService.status,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[700],
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'RoadSense needs location before the map, tracking, and road alerts can start.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[600],
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isRequestingLocationAccess
                                    ? null
                                    : _requestLocationAccess,
                                icon: _isRequestingLocationAccess
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.play_arrow),
                                label: Text(
                                  _isRequestingLocationAccess
                                      ? 'Requesting access...'
                                      : 'Enable location',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () async {
                                await Geolocator.openLocationSettings();
                              },
                              child: const Text('Open location settings'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Pollution overlay
            if (_showPollution) ...[
              Consumer<PollutionService>(
                builder: (context, pollutionService, _) {
                  if (pollutionService.isLoading) {
                    return _buildSwipeablePollutionWidget(
                      const PollutionLoadingWidget(),
                    );
                  } else if (pollutionService.errorMessage != null) {
                    return _buildSwipeablePollutionWidget(
                      PollutionErrorWidget(
                        onRetry: () {
                          final current =
                              context.read<LocationService>().currentLocation;
                          if (current != null) {
                            pollutionService.fetchAirQuality(
                              current.latitude,
                              current.longitude,
                            );
                          }
                        },
                      ),
                    );
                  } else if (pollutionService.currentPollution != null) {
                    return _buildSwipeablePollutionWidget(
                      PollutionOverlayWidget(
                        pollution: pollutionService.currentPollution!,
                        onTap: _showPollutionDetails,
                        showAlert: pollutionService.hasActiveAlert(),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],

            // 2. Category buttons
            if (!navigationService.isNavigating)
              Positioned(
                top: 118,
                left: 0,
                right: 0,
                child: CategoryButtonsWidget(
                  isRoadMonitoringActive: _isMonitoring,
                  isPollutionMonitoringActive: _showPollution,
                  isPollutionHeatmapActive: _showPollutionHeatmap,
                  onRoadMonitoringTap: _toggleMonitoring,
                  onPollutionMonitoringTap: _togglePollutionOverlay,
                  onPollutionHeatmapTap: _togglePollutionHeatmap,
                ),
              ),

            // 3. Search bar
            if (!navigationService.isNavigating)
              Positioned(
                top: 50,
                left: 16,
                right: 16,
                child: SearchBarWidget(
                  onClear: _clearSelection,
                ),
              ),

            // 4. Navigation status widget
            const NavigationStatusWidget(),

            // Turn-by-turn instruction card
            const TurnInstructionsWidget(),

            // 5. Event loading indicator
            _buildEventLoadingIndicator(),

            if (_isRequestingLocationAccess)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.06),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Waiting for permission response...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 6. Event error indicator
            _buildEventErrorIndicator(),

            // 7. Clear button
            if ((placesService.selectedPlace != null ||
                    navigationService.polylineCoordinates.isNotEmpty) &&
                !navigationService.isNavigating)
              Positioned(
                top: 58,
                right: 16,
                child: FloatingActionButton.small(
                  onPressed: () async {
                    debugPrint(
                        " Cross button pressed - clearing route and selection");

                    if (navigationService.isNavigating) {
                      navigationService.stopNavigation();
                    }

                    navigationService.clearRoute();
                    _clearSelection();

                    if (!_isFollowingLocation) {
                      setState(() {
                        _isFollowingLocation = true;
                      });
                      _startLocationFollowing();
                    }

                    if (mounted) {
                      setState(() {});
                    }

                    debugPrint(
                        " Cleared selection and re-enabled location following");
                  },
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.clear, color: Colors.black87),
                ),
              ),

            // 8. Compass and Speed Display
            if (current != null && !navigationService.isNavigating)
              CompassSpeedOverlay(
                key: _compassKey,
                heading: current.heading,
                speedKmh: locationService.speedKmh,
                isNavigating: navigationService.isNavigating,
              ),

            // Compact speed indicator during navigation
            if (current != null && navigationService.isNavigating)
              Positioned(
                top: 200,
                right: 16,
                child: CompactSpeedIndicator(
                  speedKmh: locationService.speedKmh,
                ),
              ),

            // 9. FLOATING ACTION BUTTONS
            if (current != null)
              Positioned(
                bottom: 74,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      onPressed: _recenterToCurrentLocation,
                      heroTag: "recenterBtn",
                      tooltip: 'Recenter to my location',
                      backgroundColor:
                          _isFollowingLocation ? Colors.blue : Colors.grey,
                      child: Icon(
                        _isFollowingLocation
                            ? Icons.my_location
                            : Icons.location_searching,
                        color: Colors.white,
                      ),
                    ),

                    // Reroute button
                    if (navigationService.isNavigating) ...[
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        onPressed: () async {
                          final current = locationService.currentLocation;
                          if (current != null &&
                              navigationService.isNavigating) {
                            try {
                              await navigationService.requestReroute(
                                LatLng(current.latitude, current.longitude),
                              );
                              _showImmediateSnackbar(
                                ' Recalculating route...',
                                Colors.orange,
                              );
                            } catch (e) {
                              _showImmediateSnackbar(
                                ' Failed to reroute',
                                Colors.red,
                              );
                            }
                          } else {
                            _showImmediateSnackbar(
                              ' Location not available',
                              Colors.orange,
                            );
                          }
                        },
                        heroTag: "rerouteBtn",
                        tooltip: 'Recalculate route',
                        backgroundColor: navigationService.isRerouting
                            ? Colors.orange
                            : Colors.blue,
                        child: navigationService.isRerouting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.alt_route),
                      ),
                    ],

                    const SizedBox(height: 12),
                    FloatingActionButton(
                      onPressed: () {
                        if (_isLoadingEvents) {
                          return; // Don't allow during loading
                        }

                        //  Clear error state
                        if (_eventError != null) {
                          setState(() => _eventError = null);
                        }

                        //  Force refresh (bypass cache)
                        _loadEventLineMarkers(forceRefresh: true);

                        //  Restart auto-refresh if stopped
                        if (_autoRefreshTimer == null ||
                            !_autoRefreshTimer!.isActive) {
                          debugPrint(" Restarting auto-refresh timer");
                          _startAutoRefresh();
                        }
                      },
                      heroTag: "refreshBtn",
                      tooltip: 'Refresh road events',
                      backgroundColor:
                          _isLoadingEvents ? Colors.grey : Colors.blueGrey,
                      child: _isLoadingEvents
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.refresh),
                    ),

                    const SizedBox(height: 12),
                    FloatingActionButton(
                      onPressed: _toggleTripLogging,
                      heroTag: "tripLoggerBtn",
                      tooltip: _isTripLogging
                          ? 'Stop GPS trip logging'
                          : 'Start GPS trip logging',
                      backgroundColor:
                          _isTripLogging ? Colors.redAccent : Colors.teal,
                      child: Icon(
                        _isTripLogging ? Icons.stop : Icons.pin_drop,
                      ),
                    ),

                    if (_isTripLogging && _activeTripId != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'GPS LOGGING',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _activeRouteType ?? 'unknown',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_eventCircles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          // Show event statistics
                          final stats =
                              await _eventService.getEventStatistics();
                          if (!context.mounted) return;
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text(' Event Statistics'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Total Events: ${stats['totalEvents']}'),
                                  Text('Potholes: ${stats['potholes']}'),
                                  Text('Speed Bumps: ${stats['speedBumps']}'),
                                  Text(
                                      'High Confidence: ${stats['highConfidence']}'),
                                  const SizedBox(height: 8),
                                  if (_lastSuccessfulEventFetch != null)
                                    Text(
                                      'Last Updated: ${_getTimeAgo(_lastSuccessfulEventFetch!)}',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.info_outline,
                                  color: Colors.white, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                '${_currentRoadEvents.length} events',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    if (!navigationService.isNavigating &&
                        navigationService.alternativeRoutes.length > 1)
                      CompactRouteSelectorButton(
                        onTap: _showRouteAlternatives,
                      ),
                  ],
                ),
              ),

            // 10. Keep place details panel above floating buttons.
            if (isPanelVisible)
              PlaceDetailsSlidingPanel(
                key: _slidingPanelKey,
              ),

            Positioned(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 0,
              right: 0,
              child: const LogSlidingPanel(),
            ),
          ],
        ),
      ),
    );
  }

  // 9 ADD HELPER METHOD (at the end of _MapScreenState class)
  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  //  FIX #1: Build swipeable pollution widget
  Widget _buildSwipeablePollutionWidget(Widget child) {
    return Stack(
      children: [
        // Main pollution widget
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          top: 180,
          left: _isPollutionVisible ? 16 : -400,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              if (details.delta.dx < -5) {
                setState(() {
                  _isPollutionVisible = false;
                });
              } else if (details.delta.dx > 5) {
                setState(() {
                  _isPollutionVisible = true;
                });
              }
            },
            child: child,
          ),
        ),

        //  NEW: Swipe handle/tab to show pollution widget when hidden
        if (!_isPollutionVisible)
          Positioned(
            top: 180,
            left: 0,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isPollutionVisible = true;
                });
              },
              onHorizontalDragUpdate: (details) {
                if (details.delta.dx > 5) {
                  setState(() {
                    _isPollutionVisible = true;
                  });
                }
              },
              child: Container(
                width: 32,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.9),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.air,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(height: 4),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
