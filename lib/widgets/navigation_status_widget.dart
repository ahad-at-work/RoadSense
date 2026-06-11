import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navigation_service.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

//  FIXED: Proper listener management to prevent widget corruption
class NavigationStatusWidget extends StatefulWidget {
  const NavigationStatusWidget({super.key});

  @override
  State<NavigationStatusWidget> createState() => _NavigationStatusWidgetState();
}

class _NavigationStatusWidgetState extends State<NavigationStatusWidget> {
  bool _listenerAdded = false; //  CRITICAL: Track if listener is already added
  LocationService? _locationService;
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    debugPrint(' NavigationStatusWidget: initState');
  }

  //  FIX: Use didChangeDependencies instead of initState for adding listeners
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    //  Only add listener ONCE
    if (!_listenerAdded) {
      _locationService = context.read<LocationService>();
      _locationService!.addListener(_onLocationUpdate);
      _listenerAdded = true;
      debugPrint(' NavigationStatusWidget: Added location listener');
    }
  }

  void _onLocationUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    //  Clean up listener properly
    if (_listenerAdded && _locationService != null) {
      try {
        _locationService!.removeListener(_onLocationUpdate);
        debugPrint(' NavigationStatusWidget: Removed location listener');
      } catch (e) {
        debugPrint(' NavigationStatusWidget: Error removing listener: $e');
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigationService = context.watch<NavigationService>();
    final locationService = context.watch<LocationService>();
    final placesService = context.watch<PlacesService>();

    //  Return early if not navigating (prevents unnecessary rebuilds)
    if (!navigationService.isNavigating) {
      return const SizedBox.shrink();
    }

    final current = locationService.currentLocation;
    String distanceInfo = navigationService.distanceText;

    // Update with real-time distance if location available
    if (current != null) {
      final realtimeDistance =
          navigationService.getFormattedDistanceToDestination(
        LatLng(current.latitude, current.longitude),
      );

      if (realtimeDistance != null) {
        distanceInfo = realtimeDistance;
      }
    }

    final destinationName = navigationService.destinationName ??
        placesService.selectedPlace?.name ??
        'Destination';

    // Show rerouting status
    if (navigationService.isRerouting) {
      return _buildReroutingStatus(destinationName);
    }

    // Show off-track warning
    if (navigationService.isOffTrack) {
      return _buildOffTrackStatus(
          destinationName, distanceInfo, navigationService.durationText);
    }

    // Normal navigation status
    return _buildNormalNavigationStatus(
      context,
      destinationName,
      distanceInfo,
      navigationService.durationText,
      current,
      locationService,
      navigationService,
    );
  }

  Widget _buildReroutingStatus(String destinationName) {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange[700]!, Colors.orange[500]!],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destinationName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Recalculating route...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffTrackStatus(
      String destinationName, String distance, String duration) {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red[700]!, Colors.red[500]!],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Off Route',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Searching for new route...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$distance  $duration to $destinationName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalNavigationStatus(
    BuildContext context,
    String destinationName,
    String distanceInfo,
    String durationText,
    Position? current,
    LocationService locationService,
    NavigationService navigationService,
  ) {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta == null) return;
          if (details.primaryDelta! > 6 && !_isCollapsed) {
            setState(() => _isCollapsed = true);
          } else if (details.primaryDelta! < -6 && _isCollapsed) {
            setState(() => _isCollapsed = false);
          }
        },
        onTap: () {
          setState(() => _isCollapsed = !_isCollapsed);
        },
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E88E5), Color(0xFF1976D2)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            destinationName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                distanceInfo,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '  $durationText',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isCollapsed
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      color: Colors.white,
                      size: 20,
                    ),
                    IconButton(
                      onPressed: () {
                        _showStopNavigationDialog(context);
                      },
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Stop navigation',
                    ),
                  ],
                ),
                if (!_isCollapsed &&
                    current != null &&
                    locationService.speedKmh != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.speed,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${locationService.speedKmh!.toStringAsFixed(0)} km/h',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: navigationService.routeProgress,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.3),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                  minHeight: 3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${(navigationService.routeProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (navigationService.rerouteCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.alt_route,
                                color: Colors.white,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${navigationService.rerouteCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showStopNavigationDialog(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop Navigation'),
        content: const Text('Are you sure you want to stop navigation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final navigationService = dialogContext.read<NavigationService>();
              navigationService.stopNavigation();
              Navigator.of(dialogContext).pop();

              messenger?.showSnackBar(
                const SnackBar(
                  content: Text(' Navigation stopped'),
                  backgroundColor: Colors.grey,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text(
              'Stop',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
