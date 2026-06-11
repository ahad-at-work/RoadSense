import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_webservice/places.dart';
import '../services/places_service.dart';
import '../services/location_service.dart';

/// Blazing-fast search bar with instant feedback
class SearchBarWidget extends StatefulWidget {
  final VoidCallback onClear;

  const SearchBarWidget({super.key, required this.onClear});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _showSuggestions = false;
  bool _isSelectingPlace = false;

  @override
  void initState() {
    super.initState();

    // Faster animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150), // Reduced from 200ms
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut, // Faster curve
    );

    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && !_isSelectingPlace) {
      _hideSuggestions();
    }
  }

  void _onTextChanged(String value) {
    if (_isSelectingPlace) return;

    final placesService = context.read<PlacesService>();
    final locationService = context.read<LocationService>();

    if (value.isNotEmpty) {
      placesService.searchPlaces(
        value,
        userLocation: locationService.currentLocation,
      );
      _showSuggestionsPanel();
    } else {
      _clearSearch();
    }
  }

  void _showSuggestionsPanel() {
    if (!_showSuggestions) {
      setState(() {
        _showSuggestions = true;
      });
      _animationController.forward();
    }
  }

  void _hideSuggestions() {
    if (_showSuggestions) {
      _animationController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _showSuggestions = false;
          });
        }
      });
    }
  }

  ///  OPTIMIZED: Instant place selection with immediate UI feedback
  void _onPredictionSelected(Prediction prediction) async {
    _isSelectingPlace = true;

    // 1. Update UI IMMEDIATELY - don't wait for anything
    setState(() {
      _controller.text = prediction.structuredFormatting?.mainText ??
          prediction.description ??
          '';
    });

    _hideSuggestions();
    _focusNode.unfocus();

    // 2. Trigger place selection with optimized method (immediate + background fetch)
    final placesService = context.read<PlacesService>();

    //  This notifies listeners immediately, then fetches details in background
    placesService.selectPlaceOptimized(prediction).catchError((e) {
      debugPrint(' selectPlaceOptimized failed: $e');
    });

    _isSelectingPlace = false;

    debugPrint(' Place selected in UI - details loading in background');
  }

  void _clearSearch() {
    setState(() {
      _controller.clear();
      _showSuggestions = false;
    });

    final placesService = context.read<PlacesService>();
    placesService.clearAll();

    widget.onClear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search input
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Search places...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                suffixIcon: _buildSuffixIcon(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              style: const TextStyle(fontSize: 16),
              onChanged: _onTextChanged,
              onTap: () {
                if (_controller.text.isNotEmpty) {
                  _showSuggestionsPanel();
                }
              },
            ),
          ),
        ),

        // Suggestions panel
        if (_showSuggestions)
          FadeTransition(
            opacity: _fadeAnimation,
            child: _buildSuggestionsPanel(),
          ),
      ],
    );
  }

  Widget _buildSuffixIcon() {
    final placesService = context.watch<PlacesService>();

    if (placesService.isSearching) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
          ),
        ),
      );
    }

    if (_controller.text.isNotEmpty) {
      return IconButton(
        icon: Icon(Icons.clear, color: Colors.grey[600]),
        onPressed: _clearSearch,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSuggestionsPanel() {
    final placesService = context.watch<PlacesService>();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 300),
      child: _buildSuggestionsContent(placesService),
    );
  }

  Widget _buildSuggestionsContent(PlacesService placesService) {
    if (placesService.searchError != null) {
      return _buildErrorState(placesService);
    }

    if (!placesService.isSearching && !placesService.hasResults) {
      return _buildEmptyState();
    }

    if (placesService.hasResults) {
      return _buildResultsList(placesService.searchResults);
    }

    return _buildLoadingState();
  }

  Widget _buildResultsList(List<Prediction> predictions) {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4), // Reduced padding
      itemCount: predictions.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 56,
        color: Colors.grey[200],
      ),
      itemBuilder: (context, index) {
        final prediction = predictions[index];
        return _buildPredictionTile(prediction);
      },
    );
  }

  Widget _buildPredictionTile(Prediction prediction) {
    final mainText = prediction.structuredFormatting?.mainText ??
        prediction.description ??
        '';
    final secondaryText = prediction.structuredFormatting?.secondaryText ?? '';

    final icon = _getPlaceIcon(prediction.types);
    final distance = _getDistanceText(prediction);

    return InkWell(
      onTap: () => _onPredictionSelected(prediction),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 10), // Reduced from 12
        child: Row(
          children: [
            // Icon
            Container(
              width: 36, // Reduced from 40
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  color: Colors.grey[700], size: 18), // Reduced from 20
            ),
            const SizedBox(width: 12),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mainText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (secondaryText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      secondaryText,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            if (distance != null) ...[
              const SizedBox(width: 8),
              Text(
                distance,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(24), // Reduced from 32
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20, // Reduced from 24
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Searching...',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'No places found',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(PlacesService placesService) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
            const SizedBox(height: 8),
            Text(
              'Search failed',
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                placesService.retrySearch();
                _onTextChanged(_controller.text);
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPlaceIcon(List<String>? types) {
    if (types == null || types.isEmpty) return Icons.place;
    final type = types.first.toLowerCase();

    if (type.contains('restaurant') || type.contains('food')) {
      return Icons.restaurant;
    }
    if (type.contains('cafe') || type.contains('coffee')) {
      return Icons.local_cafe;
    }
    if (type.contains('hospital') || type.contains('health')) {
      return Icons.local_hospital;
    }
    if (type.contains('store') || type.contains('shopping')) {
      return Icons.shopping_bag;
    }
    if (type.contains('hotel') || type.contains('lodging')) {
      return Icons.hotel;
    }
    if (type.contains('gas') || type.contains('fuel')) {
      return Icons.local_gas_station;
    }
    if (type.contains('bank') || type.contains('atm')) {
      return Icons.account_balance;
    }
    if (type.contains('school') || type.contains('university')) {
      return Icons.school;
    }
    if (type.contains('park')) {
      return Icons.park;
    }
    if (type.contains('airport')) {
      return Icons.flight;
    }
    if (type.contains('bus') || type.contains('transit')) {
      return Icons.directions_bus;
    }

    return Icons.place;
  }

  String? _getDistanceText(Prediction prediction) {
    if (prediction.distanceMeters == null) return null;

    final meters = prediction.distanceMeters!;
    if (meters < 1000) {
      return '${meters.round()}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }
}
