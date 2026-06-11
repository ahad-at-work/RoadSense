import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/event_service.dart';
import '../services/navigation_service.dart';
import '../services/location_service.dart';

/// Detailed information sheet for road hazards
class HazardDetailsSheet extends StatelessWidget {
  final EventModel event;

  const HazardDetailsSheet({
    super.key,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getEventColor(event.type);
    final icon = _getEventIcon(event.type);
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
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
          ),

          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getEventTitle(event.type),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getEventSubtitle(event.type),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Details section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Confidence badge (if available)
                if (event.confidence != null)
                  _buildConfidenceBadge(event.confidence!),

                const SizedBox(height: 16),

                // Information cards
                _buildInfoCard(
                  Icons.location_on,
                  'Location',
                  '${event.lat.toStringAsFixed(6)}, ${event.lon.toStringAsFixed(6)}',
                  Colors.blue,
                ),
                
                const SizedBox(height: 12),

                if (event.device != null)
                  _buildInfoCard(
                    Icons.devices,
                    'Reported By',
                    event.device!,
                    Colors.green,
                  ),

                const SizedBox(height: 12),

                // Distance from user
                _buildDistanceCard(context),

                const SizedBox(height: 20),

                // Safety recommendations
                _buildSafetyRecommendations(event.type),

                const SizedBox(height: 20),

                // Action buttons
                _buildActionButtons(context),
              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(double confidence) {
    final percentage = (confidence * 100).toInt();
    final isHighConfidence = confidence >= 0.8;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isHighConfidence 
            ? Colors.green[50] 
            : Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighConfidence 
              ? Colors.green[300]! 
              : Colors.orange[300]!,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isHighConfidence ? Icons.verified : Icons.info_outline,
            color: isHighConfidence ? Colors.green[700] : Colors.orange[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHighConfidence ? 'Verified Report' : 'Unverified Report',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isHighConfidence 
                        ? Colors.green[900] 
                        : Colors.orange[900],
                  ),
                ),
                Text(
                  '$percentage% confidence',
                  style: TextStyle(
                    fontSize: 12,
                    color: isHighConfidence 
                        ? Colors.green[700] 
                        : Colors.orange[700],
                  ),
                ),
              ],
            ),
          ),
          // Confidence bar
          SizedBox(
            width: 60,
            child: LinearProgressIndicator(
              value: confidence,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation(
                isHighConfidence ? Colors.green : Colors.orange,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceCard(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final current = locationService.currentLocation;
    
    String distanceText = 'Unknown';
    if (current != null) {
      final distance = locationService.distanceTo(event.lat, event.lon);
      if (distance != null) {
        if (distance < 1000) {
          distanceText = '${distance.round()} m away';
        } else {
          distanceText = '${(distance / 1000).toStringAsFixed(1)} km away';
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.purple[200]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.straighten, color: Colors.purple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distance',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  distanceText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyRecommendations(String eventType) {
    final recommendations = _getSafetyRecommendations(eventType);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.amber[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber[800], size: 20),
              const SizedBox(width: 8),
              Text(
                'Safety Tips',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...recommendations.map((tip) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ' ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.amber[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    tip,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        // Navigate to hazard button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => _navigateToHazard(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            icon: const Icon(Icons.navigation, size: 20),
            label: const Text(
              'Navigate Here',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Share location button
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _shareHazard(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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

  void _navigateToHazard(BuildContext context) async {
    final navigationService = context.read<NavigationService>();
    final locationService = context.read<LocationService>();
    final current = locationService.currentLocation;

    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(' Unable to get current location'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(context); // Close bottom sheet

    try {
      await navigationService.getRouteWithAlternatives(
        origin: LatLng(current.latitude, current.longitude),
        destination: event.position,
        placeName: '${_getEventTitle(event.type)} Location',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ' Route to ${_getEventTitle(event.type)} calculated',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to calculate route: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _shareHazard(BuildContext context) {
    // TODO: Implement share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(' Share feature coming soon'),
        duration: Duration(seconds: 2),
      ),
    );
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

  IconData _getEventIcon(String eventType) {
    switch (eventType.toLowerCase().trim()) {
      case 'pothole':
        return Icons.warning;
      case 'speed bump':
      case 'bump':
        return Icons.speed;
      case 'rotation':
        return Icons.rotate_90_degrees_ccw;
      case 'vibration':
        return Icons.vibration;
      case 'impact':
        return Icons.crisis_alert;
      default:
        return Icons.report_problem;
    }
  }

  String _getEventTitle(String eventType) {
    switch (eventType.toLowerCase().trim()) {
      case 'pothole':
        return 'Pothole Detected';
      case 'speed bump':
      case 'bump':
        return 'Speed Bump';
      case 'rotation':
        return 'Sharp Turn';
      case 'vibration':
        return 'Road Vibration';
      case 'impact':
        return 'Impact Zone';
      default:
        return 'Road Hazard';
    }
  }

  String _getEventSubtitle(String eventType) {
    switch (eventType.toLowerCase().trim()) {
      case 'pothole':
        return 'Road surface damage ahead';
      case 'speed bump':
      case 'bump':
        return 'Slow down to cross safely';
      case 'rotation':
        return 'Reduce speed for turn';
      case 'vibration':
        return 'Rough road surface';
      case 'impact':
        return 'Potential hazard detected';
      default:
        return 'Exercise caution';
    }
  }

  List<String> _getSafetyRecommendations(String eventType) {
    switch (eventType.toLowerCase().trim()) {
      case 'pothole':
        return [
          'Reduce speed to 20-30 km/h before reaching',
          'Keep both hands on steering wheel',
          'Avoid sudden swerving - check mirrors first',
          'If unavoidable, drive slowly over it',
        ];
      case 'speed bump':
      case 'bump':
        return [
          'Slow down to 10-15 km/h',
          'Cross at a perpendicular angle',
          'Keep steady speed while crossing',
          'Avoid braking while on the bump',
        ];
      case 'rotation':
        return [
          'Reduce speed before the turn',
          'Stay in your lane',
          'Accelerate gently after the turn',
        ];
      default:
        return [
          'Reduce speed when approaching',
          'Stay alert and focused',
          'Maintain safe following distance',
        ];
    }
  }
}

