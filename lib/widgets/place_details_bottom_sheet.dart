import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/places_service.dart';
import '../services/navigation_service.dart';
import '../services/location_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceDetailsBottomSheet extends StatefulWidget {
  const PlaceDetailsBottomSheet({super.key});

  @override
  State<PlaceDetailsBottomSheet> createState() =>
      _PlaceDetailsBottomSheetState();
}

class _PlaceDetailsBottomSheetState extends State<PlaceDetailsBottomSheet> {
  bool _isNavigating = false;

  void _startNavigation() async {
    final placesService = context.read<PlacesService>();
    final navigationService = context.read<NavigationService>();
    final locationService = context.read<LocationService>();

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

      // Fetch route if not already loaded
      if (navigationService.polylineCoordinates.isEmpty) {
        await navigationService.getRoute(
          origin: LatLng(current.latitude, current.longitude),
          destination: destination,
          placeName: place.name,
        );
      }

      //  CRITICAL: Actually start the navigation
      navigationService.startNavigation(placeName: place.name);

      if (!navigationService.isNavigating) {
        throw StateError('Navigation could not be started');
      }

      if (mounted) {
        // Close bottom sheet
        Navigator.of(context).pop();

        // Show navigation started snackbar
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
                navigationService.stopNavigation();
                navigationService.clearRoute();
                placesService.clearSelectedPlace();
              },
            ),
          ),
        );

        debugPrint(' Navigation started to ${place.name}');
        debugPrint(' Navigation state: ${navigationService.isNavigating}');
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
    final navigationService = context.watch<NavigationService>();
    final locationService = context.watch<LocationService>();
    final place = placesService.selectedPlace;
    final current = locationService.currentLocation;

    if (place == null) return const SizedBox.shrink();

    final hasRoute = navigationService.polylineCoordinates.isNotEmpty;
    final canNavigate = current != null &&
        place.geometry?.location.lat != null &&
        place.geometry?.location.lng != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              height: 5,
              width: 40,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header with title and close button
          Row(
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
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Address
          if (place.formattedAddress != null)
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    place.formattedAddress!,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),

          // Rating and opening hours
          Row(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          ),
          const SizedBox(height: 16),

          // Distance and duration card (if route exists)
          if (hasRoute && navigationService.distanceText.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.directions_car, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          navigationService.durationText,
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'via fastest route',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              // Start Navigation Button (Primary)
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed:
                      canNavigate && !_isNavigating ? _startNavigation : null,
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
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

              // Call button (if phone number available)
              if (place.formattedPhoneNumber != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Implement phone call
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
                      // Share location
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
          ),

          // Additional details section
          if (place.openingHours?.weekdayText != null) ...[
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
            ...place.openingHours!.weekdayText.take(3).map(
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
                ),
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
                            .map((day) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
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

          // Phone number
          if (place.formattedPhoneNumber != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  place.formattedPhoneNumber!,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ],

          // Website
          if (place.website != null) ...[
            const SizedBox(height: 8),
            Row(
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
          ],

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
