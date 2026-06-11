import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/places_service.dart';
import '../services/navigation_service.dart';
import '../services/location_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FloatingButtonWidget extends StatelessWidget {
  final GoogleMapController? mapController;

  const FloatingButtonWidget({super.key, this.mapController});

  @override
  Widget build(BuildContext context) {
    final placesService = context.watch<PlacesService>();
    final navigationService = context.watch<NavigationService>();
    final locationService = context.watch<LocationService>();

    // Show button only if a place is selected
    if (placesService.selectedPlace == null) return const SizedBox.shrink();

    return FloatingActionButton.small(
      onPressed: () {
        // Clear selected place
        placesService.clearSelectedPlace();
        navigationService.clearRoute();

        // Animate map back to current location
        final current = locationService.currentLocation;
        if (current != null && mapController != null) {
          mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(current.latitude, current.longitude),
              15,
            ),
          );
        }
      },
      tooltip: 'Clear selection',
      child: const Icon(Icons.clear),
    );
  }
}
