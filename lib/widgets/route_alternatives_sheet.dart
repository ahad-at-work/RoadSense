import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navigation_service.dart';
import '../utils/route_risk_analyzer.dart';

///  NEW: Bottom sheet to show and select alternative routes
class RouteAlternativesSheet extends StatelessWidget {
  final VoidCallback onRouteSelected;

  const RouteAlternativesSheet({
    super.key,
    required this.onRouteSelected,
  });

  @override
  Widget build(BuildContext context) {
    final navigationService = context.watch<NavigationService>();
    final alternatives = navigationService.alternativeRoutes;
    final selectedRoute = navigationService.selectedRoute;
    final safestRouteId = navigationService.routeRiskAssessments.isNotEmpty
        ? navigationService.routeRiskAssessments.first.route.id
        : null;

    if (alternatives.isEmpty) {
      return const SizedBox.shrink();
    }

    final fastestRoute = alternatives.firstWhere(
      (r) => r.isFastest,
      orElse: () => alternatives.reduce(
        (a, b) => a.durationSeconds <= b.durationSeconds ? a : b,
      ),
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Choose Route',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Loading indicator / skeletons
          Flexible(
            child: SingleChildScrollView(
              child: navigationService.isLoadingAlternatives
                  ? Column(
                      children: List.generate(3, (i) => _buildSkeletonCard()),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: alternatives.length,
                      itemBuilder: (context, index) {
                        final route = alternatives[index];
                        final isSelected = selectedRoute?.id == route.id;

                        return _buildRouteCard(
                          context,
                          route,
                          index,
                          isSelected,
                          navigationService,
                          safestRouteId,
                          fastestRoute,
                        );
                      },
                    ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildRouteCard(
    BuildContext context,
    RouteAlternative route,
    int index,
    bool isSelected,
    NavigationService navigationService,
    String? safestRouteId,
    RouteAlternative fastestRoute,
  ) {
    //  NEW: Get risk assessment for this route
    final riskAssessment = navigationService.routeRiskAssessments
        .cast<RouteRiskAssessment?>()
        .firstWhere(
          (a) => a?.route.id == route.id,
          orElse: () => null,
        );

    return InkWell(
      onTap: () async {
        await navigationService.selectRoute(route);
        onRouteSelected();
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Route number
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.grey[400],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Route info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Distance
                          Flexible(
                            child: Text(
                              route.distanceText,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.blue[900]
                                    : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Duration
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue[100]
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: isSelected
                                      ? Colors.blue[900]
                                      : Colors.grey[700],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  route.durationText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.blue[900]
                                        : Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Route summary
                      Text(
                        route.summary,
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

                // Badges
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (route.isFastest) _buildBadge('Fastest', Colors.green),
                    if (route.isShortest)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _buildBadge('Shortest', Colors.orange),
                      ),
                    //  NEW: Safest badge
                    if (riskAssessment != null && route.id == safestRouteId)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _buildBadge('Safest', Colors.teal),
                      ),
                    if (isSelected)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            //  NEW: Risk assessment display
            if (riskAssessment != null) ...[
              const SizedBox(height: 12),
              _buildRiskIndicator(riskAssessment),
            ],

            // Time comparison
            if (index > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getTimeDifference(route, fastestRoute),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await navigationService.selectRoute(route);
                  onRouteSelected();
                  navigationService.startNavigation(
                    placeName: navigationService.destinationName,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.navigation, size: 18),
                label: const Text(
                  'Start Navigation',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //  NEW: Risk indicator widget
  Widget _buildRiskIndicator(RouteRiskAssessment assessment) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: assessment.riskColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: assessment.riskColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            assessment.riskIcon,
            color: assessment.riskColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${assessment.riskLevel.toString().split('.').last.toUpperCase()} RISK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: assessment.riskColor,
                    letterSpacing: 0.5,
                  ),
                ),
                if (assessment.hazardCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${assessment.hazardCount} hazard${assessment.hazardCount > 1 ? 's' : ''} on route',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Risk score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: assessment.riskColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              assessment.totalRiskScore.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: assessment.riskColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  // Skeleton placeholder while loading alternatives
  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 14, color: Colors.grey[300]),
                    const SizedBox(height: 6),
                    Container(height: 12, width: 120, color: Colors.grey[200]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 10, color: Colors.grey[200]),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Container(height: 36, color: Colors.grey[200])),
            ],
          ),
        ],
      ),
    );
  }

  String _getTimeDifference(RouteAlternative route, RouteAlternative fastest) {
    final diff = route.durationSeconds - fastest.durationSeconds;

    if (diff <= 0) return '';

    final minutes = (diff / 60).round();

    if (minutes < 1) {
      return '+${diff}s';
    } else {
      return '+${minutes}min';
    }
  }
}

///  NEW: Compact route selector (alternative compact design)
class CompactRouteSelectorButton extends StatelessWidget {
  final VoidCallback onTap;

  const CompactRouteSelectorButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final navigationService = context.watch<NavigationService>();
    final alternatives = navigationService.alternativeRoutes;

    if (alternatives.length <= 1) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: FloatingActionButton.small(
          onPressed: onTap,
          backgroundColor: Colors.white,
          child: Stack(
            children: [
              const Center(
                child: Icon(
                  Icons.alt_route,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${alternatives.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
