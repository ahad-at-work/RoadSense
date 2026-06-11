import 'package:flutter/material.dart';

/// Google Maps-style category buttons with vibrant colors
class CategoryButtonsWidget extends StatelessWidget {
  final bool isRoadMonitoringActive;
  final bool isPollutionMonitoringActive;
  final bool isPollutionHeatmapActive;
  final VoidCallback onRoadMonitoringTap;
  final VoidCallback onPollutionMonitoringTap;
  final VoidCallback onPollutionHeatmapTap;

  const CategoryButtonsWidget({
    super.key,
    required this.isRoadMonitoringActive,
    required this.isPollutionMonitoringActive,
    required this.isPollutionHeatmapActive,
    required this.onRoadMonitoringTap,
    required this.onPollutionMonitoringTap,
    required this.onPollutionHeatmapTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildCategoryButton(
            icon: Icons.sensors_outlined,
            label: 'Road Monitoring',
            isActive: isRoadMonitoringActive,
            onTap: onRoadMonitoringTap,
            activeGradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00C853), Color(0xFFB2FF59)],
            ),
            inactiveTint: const Color(0xFF00C853),
          ),
          const SizedBox(width: 10),
          _buildCategoryButton(
            icon: Icons.air,
            label: 'Pollution Monitoring',
            isActive: isPollutionMonitoringActive,
            onTap: onPollutionMonitoringTap,
            activeGradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E88E5), Color(0xFF90CAF9)],
            ),
            inactiveTint: const Color(0xFF1E88E5),
          ),
          const SizedBox(width: 10),
          _buildCategoryButton(
            icon: Icons.gradient,
            label: 'Pollution Heatmap',
            isActive: isPollutionHeatmapActive,
            onTap: onPollutionHeatmapTap,
            activeGradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6F00), Color(0xFFFFD180)],
            ),
            inactiveTint: const Color(0xFFFF6F00),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required LinearGradient activeGradient,
    required Color inactiveTint,
  }) {
    final baseTint = inactiveTint.withValues(alpha: 0.12);
    final edgeTint = inactiveTint.withValues(alpha: 0.28);
    const activeTextColor = Colors.white;
    final inactiveTextColor = inactiveTint.withValues(alpha: 0.95);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: isActive
                ? activeGradient
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [baseTint.withValues(alpha: 0.9), Colors.white],
                  ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isActive ? Colors.white.withValues(alpha: 0.45) : edgeTint,
              width: isActive ? 1.8 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: isActive
                    ? inactiveTint.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.12),
                blurRadius: isActive ? 14 : 8,
                spreadRadius: isActive ? 0.5 : 0,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? activeTextColor : inactiveTextColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.15,
                  color: isActive ? activeTextColor : inactiveTextColor,
                  shadows: isActive
                      ? [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
