import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:geolocator/geolocator.dart';

/// Ultra-fast Places Service with parallel operations
class PlacesService extends ChangeNotifier {
  final _places = GoogleMapsPlaces(
    apiKey: 'AIzaSyAmr6QANQ42SFt-o5XyVN0jlYlmuMV_dgQ',
  );

  // Search results
  List<Prediction> _searchResults = [];
  PlaceDetails? _selectedPlace;

  // Loading & error states
  bool _isSearching = false;
  bool _isLoadingDetails = false;
  String? _searchError;

  // Cache management
  final Map<String, List<Prediction>> _searchCache = {};
  final Map<String, PlaceDetails> _detailsCache = {};

  // Debouncing
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 250);
  // Simple search id to ignore stale responses
  int _searchId = 0;

  // Session token
  String? _sessionToken;
  DateTime? _sessionStartTime;

  // Getters
  List<Prediction> get searchResults => _searchResults;
  PlaceDetails? get selectedPlace => _selectedPlace;
  bool get isSearching => _isSearching;
  bool get isLoadingDetails => _isLoadingDetails;
  String? get searchError => _searchError;
  bool get hasResults => _searchResults.isNotEmpty;

  /// Fast search with immediate response
  Future<void> searchPlaces(String query, {Position? userLocation}) async {
    _debounceTimer?.cancel();
    _searchError = null;

    if (query.isEmpty) {
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    // Check cache IMMEDIATELY
    final cacheKey = _getCacheKey(query, userLocation);
    if (_searchCache.containsKey(cacheKey)) {
      _searchResults = _searchCache[cacheKey]!;
      _isSearching = false;
      notifyListeners();
      debugPrint(' INSTANT cached results for "$query"');
      return;
    }

    // Show loading state
    _isSearching = true;
    notifyListeners();

    // Debounce - increment search id so we can ignore stale responses
    _searchId++;
    final currentSearchId = _searchId;
    _debounceTimer = Timer(_debounceDuration, () async {
      await _performSearch(query, userLocation, cacheKey, currentSearchId);
    });
  }

  /// Perform search with optimized settings
  Future<void> _performSearch(
    String query,
    Position? userLocation,
    String cacheKey,
    int searchId,
  ) async {
    try {
      _ensureSessionToken();

      final response = await _places
          .autocomplete(
            query,
            language: 'en',
            sessionToken: _sessionToken,
            location: userLocation != null
                ? Location(
                    lat: userLocation.latitude, lng: userLocation.longitude)
                : null,
            radius: userLocation != null ? 30000 : null,
            strictbounds: false,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Search timeout'),
          );

      // Ignore results if a newer search has started
      if (searchId != _searchId) {
        debugPrint(' Ignoring stale search result for "$query"');
        return;
      }

      if (response.isOkay && response.predictions.isNotEmpty) {
        _searchResults = response.predictions;
        _searchCache[cacheKey] = response.predictions;
        _searchError = null;

        debugPrint(' Found ${response.predictions.length} places');

        if (_searchCache.length > 30) {
          _searchCache.remove(_searchCache.keys.first);
        }
      } else {
        _searchResults = [];
        _searchError = response.errorMessage ?? 'No results';
      }
    } catch (e) {
      _searchResults = [];
      _searchError = 'Search failed';
      debugPrint(' Search error: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  ///  FIXED: Select place and fetch full details immediately
  Future<void> selectPlaceOptimized(Prediction prediction) async {
    if (prediction.placeId == null) {
      debugPrint(' Prediction has no placeId');
      return;
    }

    // Clear previous selection
    _selectedPlace = null;
    notifyListeners();

    // Small delay to ensure UI clears
    await Future.delayed(const Duration(milliseconds: 50));

    //  Fetch full details FIRST before setting selected place
    await _fetchPlaceDetails(prediction.placeId!);
  }

  ///  FIXED: Fetch complete place details before notifying
  Future<void> _fetchPlaceDetails(String placeId) async {
    try {
      // Check cache first
      if (_detailsCache.containsKey(placeId)) {
        _selectedPlace = _detailsCache[placeId];
        notifyListeners();
        debugPrint(' Using cached place details');
        return;
      }

      _isLoadingDetails = true;
      notifyListeners();

      _ensureSessionToken();

      final response = await _places
          .getDetailsByPlaceId(
            placeId,
            sessionToken: _sessionToken,
            language: 'en',
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Details timeout'),
          );

      if (response.isOkay) {
        final details = response.result;

        //  Verify coordinates exist
        if (details.geometry?.location.lat == null ||
            details.geometry?.location.lng == null) {
          debugPrint(' Place has no valid coordinates');
          _searchError = 'Place location not available';
          _isLoadingDetails = false;
          notifyListeners();
          return;
        }

        _selectedPlace = details;
        _detailsCache[placeId] = details;
        _invalidateSession();

        debugPrint(' Place details loaded: ${details.name}');
        debugPrint(
            ' Coordinates: ${details.geometry!.location.lat}, ${details.geometry!.location.lng}');

        // Limit cache
        if (_detailsCache.length > 15) {
          _detailsCache.remove(_detailsCache.keys.first);
        }
      } else {
        debugPrint(' Failed to get place details: ${response.errorMessage}');
        _searchError = 'Failed to load place details';
      }
    } catch (e) {
      debugPrint(' Error fetching place details: $e');
      _searchError = 'Failed to load place';
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  /// Legacy method for compatibility
  Future<void> selectPlace(String placeId) async {
    await _fetchPlaceDetails(placeId);
  }

  String _getCacheKey(String query, Position? location) {
    if (location == null) return query.toLowerCase();
    final lat = location.latitude.toStringAsFixed(2);
    final lon = location.longitude.toStringAsFixed(2);
    return '${query.toLowerCase()}_${lat}_$lon';
  }

  void _ensureSessionToken() {
    if (_sessionToken == null || _isSessionExpired()) {
      _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
      _sessionStartTime = DateTime.now();
    }
  }

  bool _isSessionExpired() {
    if (_sessionStartTime == null) return true;
    return DateTime.now().difference(_sessionStartTime!).inMinutes >= 3;
  }

  void _invalidateSession() {
    _sessionToken = null;
    _sessionStartTime = null;
  }

  void clearSelectedPlace() {
    _selectedPlace = null;
    notifyListeners();
  }

  void clearSearchResults() {
    _searchResults = [];
    _searchError = null;
    notifyListeners();
  }

  void clearAll() {
    _searchResults = [];
    _selectedPlace = null;
    _searchError = null;
    _debounceTimer?.cancel();
    notifyListeners();
  }

  void clearCache() {
    _searchCache.clear();
    _detailsCache.clear();
    debugPrint(' Cache cleared');
  }

  void retrySearch() {
    _searchError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCache.clear();
    _detailsCache.clear();
    super.dispose();
  }
}
