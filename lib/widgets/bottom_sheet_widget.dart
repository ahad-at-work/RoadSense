import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/places_service.dart';
import '../services/navigation_service.dart';

class BottomSheetWidget extends StatelessWidget {
  const BottomSheetWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final placesService = context.watch<PlacesService>();
    final navigationService = context.watch<NavigationService>();

    if (placesService.selectedPlace == null && navigationService.polylineCoordinates.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(15),
      height: 200,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (placesService.selectedPlace != null) ...[
            Text(
              placesService.selectedPlace!.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(placesService.selectedPlace!.formattedAddress ?? ''),
          ],
          if (navigationService.polylineCoordinates.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Distance: ${navigationService.distanceText}'),
            Text('Duration: ${navigationService.durationText}'),
          ],
        ],
      ),
    );
  }
}
