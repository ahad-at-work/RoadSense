import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/places_service.dart';
import '../services/navigation_service.dart';
import '../services/location_service.dart';
import '../services/pollution_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/route_alternatives_sheet.dart';

class PlaceDetailsSlidingPanel extends StatefulWidget {
  const PlaceDetailsSlidingPanel({super.key});

  @override
  State<PlaceDetailsSlidingPanel> createState() =>
      PlaceDetailsSlidingPanelState();
}

class PlaceDetailsSlidingPanelState extends State<PlaceDetailsSlidingPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  bool _isNavigating = false;

  bool _isVisible = false;
  bool get isVisible => _isVisible;

  bool _isExpanded = true;
  bool get isExpanded => _isExpanded;

  static const double _minHeight = 80.0;
  static const double _maxHeightFraction = 0.7;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  void show() {
    final shouldLog = !_isVisible || !_isExpanded;

    if (!_isVisible || !_isExpanded) {
      setState(() {
        _isVisible = true;
        _isExpanded = true;
      });
    }

    if (_animationController.status != AnimationStatus.forward &&
        _animationController.value < 1.0) {
      _animationController.forward();
    }

    if (shouldLog) {
      debugPrint(' Sliding panel shown (expanded)');
    }
  }

  void hide() {
    if (_isVisible) {
      _animationController.reverse().then((_) {
        if (mounted) {
          // Keep panel visible if another show() was triggered mid-animation.
          if (_animationController.status == AnimationStatus.dismissed) {
            setState(() {
              _isVisible = false;
              _isExpanded = false;
            });
          }
        }
      });
      debugPrint(' Sliding panel hidden');
    }
  }

  void minimize() {
    if (_isExpanded) {
      setState(() {
        _isExpanded = false;
      });
      debugPrint(' Sliding panel minimized to preview');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          (context as Element).markNeedsBuild();
        }
      });
    }
  }

  void expand() {
    if (!_isExpanded) {
      setState(() {
        _isExpanded = true;
      });
      debugPrint(' Sliding panel expanded from preview');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          (context as Element).markNeedsBuild();
        }
      });
    }
  }

  void toggle() {
    if (_isExpanded) {
      minimize();
    } else {
      expand();
    }
  }

  void _startNavigation() async {
    final placesService = context.read<PlacesService>();
    final navigationService = context.read<NavigationService>();
    final locationService = context.read<LocationService>();
    final pollutionService = context.read<PollutionService>();

    final place = placesService.selectedPlace;
    final current = locationService.currentLocation;

    if (place == null || current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(' Unable to start navigation'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isNavigating = true;
    });

    try {
      final destination = LatLng(
        place.geometry!.location.lat,
        place.geometry!.location.lng,
      );

      if (navigationService.polylineCoordinates.isEmpty) {
        await navigationService.getRouteWithAlternatives(
          origin: LatLng(current.latitude, current.longitude),
          destination: destination,
          placeName: place.name,
          pollutionData: pollutionService.currentPollution,
        );
      }

      navigationService.startNavigation(placeName: place.name);

      if (!navigationService.isNavigating) {
        throw StateError('Navigation could not be started');
      }

      if (mounted) {
        minimize();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.navigation, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ' Navigation started to ${place.name}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'Stop',
              textColor: Colors.white,
              onPressed: () {
                //  FIX #3: Only stop navigation, don't clear place or route
                navigationService.stopNavigation();
              },
            ),
          ),
        );

        debugPrint(' Navigation started to ${place.name}');
      }
    } catch (e) {
      debugPrint(' Error starting navigation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start navigation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final placesService = context.watch<PlacesService>();
    final place = placesService.selectedPlace;

    if (place == null || !_isVisible) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: _isExpanded
            ? _buildFullPanel(place)
            : _buildMinimizedPreview(place),
      ),
    );
  }

  Widget _buildMinimizedPreview(place) {
    return GestureDetector(
      onTap: expand,
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta! < -5) {
          expand();
        }
      },
      child: Container(
        height: _minHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  height: 5,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.place,
                        color: Colors.blue[700],
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            place.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (place.vicinity != null)
                            Text(
                              place.vicinity!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_up,
                      color: Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullPanel(place) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta! > 5) {
          minimize();
        }
      },
      child: _buildPanelContent(place),
    );
  }

  Widget _buildPanelContent(place) {
    final navigationService = context.watch<NavigationService>();
    final locationService = context.watch<LocationService>();
    final current = locationService.currentLocation;

    final hasRoute = navigationService.polylineCoordinates.isNotEmpty;
    final canNavigate = current != null &&
        place.geometry?.location.lat != null &&
        place.geometry?.location.lng != null;

    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * _maxHeightFraction;

    return Container(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(place),
                  const SizedBox(height: 12),
                  if (place.formattedAddress != null) _buildAddressRow(place),
                  const SizedBox(height: 12),
                  _buildInfoRow(place),
                  const SizedBox(height: 16),
                  if (hasRoute && navigationService.distanceText.isNotEmpty)
                    _buildRouteInfo(navigationService),
                  const SizedBox(height: 16),
                  _buildActionButtons(canNavigate, place),
                  if (place.openingHours?.weekdayText != null)
                    _buildOpeningHours(place),
                  if (place.formattedPhoneNumber != null)
                    _buildPhoneNumber(place),
                  if (place.website != null) _buildWebsite(place),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          height: 5,
          width: 40,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(place) {
    return Row(
      children: [
        Expanded(
          child: Text(
            place.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: minimize,
          tooltip: 'Minimize',
        ),
      ],
    );
  }

  Widget _buildAddressRow(place) {
    return Row(
      children: [
        Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            place.formattedAddress!,
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(place) {
    return Row(
      children: [
        if (place.rating != null)
          Row(
            children: [
              const Icon(Icons.star, color: Colors.orange, size: 18),
              const SizedBox(width: 4),
              Text(
                '${place.rating}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 16),
            ],
          ),
        if (place.openingHours != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: place.openingHours!.openNow
                  ? Colors.green[50]
                  : Colors.red[50],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              place.openingHours!.openNow ? 'Open Now' : 'Closed',
              style: TextStyle(
                color: place.openingHours!.openNow
                    ? Colors.green[700]
                    : Colors.red[700],
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

// 2 UPDATE _buildRouteInfo() method (replace existing around line ~380):
  Widget _buildRouteInfo(NavigationService navigationService) {
    final selectedRoute = navigationService.selectedRoute;
    final alternatives = navigationService.alternativeRoutes;

    return Column(
      children: [
        // Selected route info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!, width: 1),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.directions_car, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              navigationService.distanceText,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.blue[900],
                              ),
                            ),
                            Text(
                              '  ${navigationService.durationText}',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        if (selectedRoute != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            selectedRoute.summary,
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (selectedRoute?.isFastest ?? false)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ' Fastest',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (selectedRoute?.isShortest ?? false)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ' Shortest',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              //  NEW: Alternative routes button
              if (alternatives.length > 1) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
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
                            if (mounted) {
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.alt_route,
                          size: 16,
                          color: Colors.blue[900],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${alternatives.length} routes available - Tap to compare',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[900],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.blue[900],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

// ========================================
// THAT'S THE ONLY CHANGE NEEDED FOR THIS FILE
// ========================================
// This adds a button to view alternative routes
// when multiple routes are available
// ========================================

  Widget _buildActionButtons(bool canNavigate, place) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: canNavigate && !_isNavigating ? _startNavigation : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            icon: _isNavigating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.navigation, size: 20),
            label: Text(
              _isNavigating ? 'Starting...' : 'Start',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (place.formattedPhoneNumber != null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(' Call feature coming soon'),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(color: Colors.blue[300]!),
              ),
              icon: Icon(Icons.phone, size: 18, color: Colors.blue[700]),
              label: Text(
                'Call',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(' Share feature coming soon'),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(color: Colors.blue[300]!),
              ),
              icon: Icon(Icons.share, size: 18, color: Colors.blue[700]),
              label: Text(
                'Share',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOpeningHours(place) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Opening Hours',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(Icons.access_time, size: 18, color: Colors.grey[600]),
          ],
        ),
        const SizedBox(height: 8),
        ...place.openingHours!.weekdayText
            .take(3)
            .map<Widget>(
              (day) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  day,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            )
            .toList(),
        if (place.openingHours!.weekdayText.length > 3)
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Opening Hours'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: place.openingHours!.weekdayText
                        .map<Widget>((day) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(day),
                            ))
                        .toList(),
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
            child: const Text('See all hours'),
          ),
      ],
    );
  }

  Widget _buildPhoneNumber(place) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.phone, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            place.formattedPhoneNumber!,
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildWebsite(place) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.language, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              place.website!,
              style: TextStyle(
                color: Colors.blue[700],
                decoration: TextDecoration.underline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
