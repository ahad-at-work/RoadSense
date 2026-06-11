import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navigation_service.dart';

///  ENHANCED: Widget showing turn-by-turn instructions with lane guidance during navigation
class TurnInstructionsWidget extends StatelessWidget {
  const TurnInstructionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final navigationService = context.watch<NavigationService>();

    if (!navigationService.isNavigating) {
      return const SizedBox.shrink();
    }

    final currentStep = navigationService.currentStep;
    final nextStep = navigationService.nextStep;

    if (currentStep == null) {
      return const SizedBox.shrink();
    }

    final distanceToTurn = navigationService.getFormattedDistanceToNextTurn();

    //  Show rerouting indicator
    if (navigationService.isRerouting) {
      return _buildReroutingIndicator();
    }

    //  Show off-track warning
    if (navigationService.isOffTrack && !navigationService.isRerouting) {
      return _buildOffTrackWarning(currentStep, distanceToTurn);
    }

    return Positioned(
      top: 180,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[800]!, Colors.blue[600]!],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Current instruction
            _buildCurrentInstruction(currentStep, distanceToTurn),

            //  NEW: Lane guidance (if available)
            if (currentStep.lanes != null && currentStep.lanes!.isNotEmpty)
              _buildLaneGuidance(currentStep.lanes!),

            // Next instruction preview (if available)
            if (nextStep != null) _buildNextInstructionPreview(nextStep),
          ],
        ),
      ),
    );
  }

  ///  NEW: Rerouting indicator
  Widget _buildReroutingIndicator() {
    return Positioned(
      top: 180,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange[700]!, Colors.orange[500]!],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Calculating new route...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///  NEW: Off-track warning
  Widget _buildOffTrackWarning(NavigationStep step, String? distance) {
    return Positioned(
      top: 180,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red[700]!, Colors.red[500]!],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Warning header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Off Route - Rerouting...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Current instruction (dimmed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      step.maneuverIcon,
                      color: Colors.white70,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (distance != null)
                          Text(
                            distance,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          step.instruction,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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

  Widget _buildCurrentInstruction(NavigationStep step, String? distance) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Maneuver icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              step.maneuverIcon,
              color: Colors.white,
              size: 32,
            ),
          ),

          const SizedBox(width: 16),

          // Instruction text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Distance to turn
                if (distance != null)
                  Text(
                    distance,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                const SizedBox(height: 4),

                // Instruction
                Text(
                  step.instruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ///  NEW: Lane guidance visualization
  Widget _buildLaneGuidance(List<LaneInfo> lanes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'USE LANE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: lanes.map((lane) => _buildLaneIndicator(lane)).toList(),
          ),
        ],
      ),
    );
  }

  ///  NEW: Individual lane indicator
  Widget _buildLaneIndicator(LaneInfo lane) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          // Lane direction arrow(s)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: lane.isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: lane.isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: _buildLaneArrow(lane.directions, lane.isActive),
          ),
        ],
      ),
    );
  }

  ///  NEW: Lane arrow based on direction
  Widget _buildLaneArrow(List<String> directions, bool isActive) {
    // Handle multiple directions (e.g., left + through)
    if (directions.contains('left') && directions.contains('through')) {
      return Icon(
        Icons.north_west,
        color:
            isActive ? Colors.blue[800] : Colors.white.withValues(alpha: 0.6),
        size: 24,
      );
    } else if (directions.contains('right') && directions.contains('through')) {
      return Icon(
        Icons.north_east,
        color:
            isActive ? Colors.blue[800] : Colors.white.withValues(alpha: 0.6),
        size: 24,
      );
    } else if (directions.contains('left')) {
      return Icon(
        Icons.turn_left,
        color:
            isActive ? Colors.blue[800] : Colors.white.withValues(alpha: 0.6),
        size: 24,
      );
    } else if (directions.contains('right')) {
      return Icon(
        Icons.turn_right,
        color:
            isActive ? Colors.blue[800] : Colors.white.withValues(alpha: 0.6),
        size: 24,
      );
    } else {
      return Icon(
        Icons.arrow_upward,
        color:
            isActive ? Colors.blue[800] : Colors.white.withValues(alpha: 0.6),
        size: 24,
      );
    }
  }

  Widget _buildNextInstructionPreview(NavigationStep nextStep) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          // Small icon
          Icon(
            nextStep.maneuverIcon,
            color: Colors.white.withValues(alpha: 0.8),
            size: 18,
          ),

          const SizedBox(width: 12),

          // Preview text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Then ${nextStep.distance}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nextStep.instruction,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
