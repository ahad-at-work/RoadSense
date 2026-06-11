import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pollution_model.dart';
import '../services/pollution_service.dart';
import '../utils/pollution_constants.dart';

class PollutionDetailsSheet extends StatefulWidget {
  const PollutionDetailsSheet({super.key});

  @override
  State<PollutionDetailsSheet> createState() => _PollutionDetailsSheetState();
}

class _PollutionDetailsSheetState extends State<PollutionDetailsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pollutionService = context.watch<PollutionService>();
    final pollution = pollutionService.currentPollution;

    if (pollution == null) {
      return const SizedBox.shrink();
    }

    final aqiColor = AQIColors.getColor(pollution.aqi);
    final category = AQIColors.getCategory(pollution.aqi);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Center(
            child: Container(
              height: 5,
              width: 40,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: aqiColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.air,
                    color: aqiColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Air Quality Index',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$category (${pollution.aqi})',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: aqiColor,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: aqiColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: aqiColor,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Pollutants'),
              Tab(text: 'Health'),
            ],
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(pollution, aqiColor),
                _buildPollutantsTab(pollution),
                _buildHealthTab(pollution),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(PollutionData pollution, Color aqiColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AQI Gauge
          Center(
            child: Column(
              children: [
                Text(
                  pollution.aqi.toString(),
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    color: aqiColor,
                  ),
                ),
                Text(
                  AQIColors.getCategory(pollution.aqi),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: aqiColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // AQI Scale
          _buildAQIScale(pollution.aqi),

          const SizedBox(height: 24),

          // Location & Time
          _buildInfoCard(
            icon: Icons.location_on,
            title: 'Location',
            value: '${pollution.location.latitude.toStringAsFixed(4)}, ${pollution.location.longitude.toStringAsFixed(4)}',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.access_time,
            title: 'Last Updated',
            value: PollutionFormatters.getTimeAgo(pollution.timestamp),
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.science,
            title: 'Dominant Pollutant',
            value: PollutantInfo.getDisplayName(pollution.dominantPollutant),
          ),

          // Forecast if available
          if (pollution.forecasts != null && pollution.forecasts!.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Forecast',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildForecastList(pollution.forecasts!),
          ],
        ],
      ),
    );
  }

  //  FIXED: Pollutants tab with proper overflow handling
  Widget _buildPollutantsTab(PollutionData pollution) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Pollutant Levels',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          //  FIX: Wrap in Column instead of spreading into ListView
          ...pollution.pollutants.entries.map((entry) {
            final pollutant = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPollutantCard(pollutant),
            );
          }).toList(),
          
          // Add bottom padding to prevent cutoff
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHealthTab(PollutionData pollution) {
    final healthRec = pollution.healthRecommendation;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildHealthRecommendationCard(
            icon: Icons.people,
            title: 'General Population',
            recommendation: healthRec.general,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildHealthRecommendationCard(
            icon: Icons.health_and_safety,
            title: 'Sensitive Groups',
            recommendation: healthRec.sensitive,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildHealthRecommendationCard(
            icon: Icons.directions_run,
            title: 'Activity Recommendations',
            recommendation: healthRec.activity,
            color: Colors.green,
          ),
          const SizedBox(height: 24),
          _buildSensitiveGroupsInfo(),
          
          // Add bottom padding
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAQIScale(int currentAqi) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AQI Scale',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildAQIScaleRow(0, 50, 'Good', currentAqi),
          _buildAQIScaleRow(51, 100, 'Moderate', currentAqi),
          _buildAQIScaleRow(101, 150, 'Unhealthy for Sensitive', currentAqi),
          _buildAQIScaleRow(151, 200, 'Unhealthy', currentAqi),
          _buildAQIScaleRow(201, 300, 'Very Unhealthy', currentAqi),
          _buildAQIScaleRow(301, 500, 'Hazardous', currentAqi),
        ],
      ),
    );
  }

  Widget _buildAQIScaleRow(int min, int max, String label, int currentAqi) {
    final isInRange = currentAqi >= min && currentAqi <= max;
    final color = AQIColors.getColor((min + max) ~/ 2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$min-$max: $label',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isInRange ? FontWeight.bold : FontWeight.normal,
                color: isInRange ? color : Colors.black87,
              ),
            ),
          ),
          if (isInRange)
            Icon(
              Icons.arrow_left,
              color: color,
              size: 16,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  //  FIXED: Pollutant card with better text wrapping
  Widget _buildPollutantCard(PollutantConcentration pollutant) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PollutantInfo.getIcon(pollutant.code),
                color: Colors.blue,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pollutant.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      pollutant.fullName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                PollutionFormatters.formatConcentration(
                  pollutant.concentration,
                  pollutant.unit,
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            PollutantInfo.getDescription(pollutant.code),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHealthRecommendationCard({
    required IconData icon,
    required String title,
    required String recommendation,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            recommendation,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensitiveGroupsInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text(
                'Sensitive Groups',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...HealthCategories.sensitiveGroupsInfo.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(' ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                        children: [
                          TextSpan(
                            text: '${entry.key}: ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: entry.value),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildForecastList(List<HourlyForecast> forecasts) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: forecasts.length > 8 ? 8 : forecasts.length,
        itemBuilder: (context, index) {
          final forecast = forecasts[index];
          final color = AQIColors.getColor(forecast.aqi);

          return Container(
            width: 80,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  PollutionFormatters.formatDateTime(forecast.dateTime),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  forecast.aqi.toString(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  AQIColors.getCategoryIcon(forecast.aqi),
                  color: color,
                  size: 16,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

