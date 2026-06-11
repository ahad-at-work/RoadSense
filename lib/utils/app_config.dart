import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

// ============================================================================
//  SECURE CONFIGURATION MANAGER
// Handles API endpoints, authentication, and security
// ============================================================================

class AppConfig {
  static const String _apiEndpointKey = 'api_endpoint';
  static const String _apiKeyKey = 'api_key';
  static const String _hmacSecretKey = 'hmac_secret';
  
  // 
  // INITIALIZATION
  // 
  
  /// Initialize app configuration
  /// 
  /// For development:
  /// ```dart
  /// await AppConfig.initialize(
  ///   apiEndpoint: 'https://your-dev-endpoint.com/api',
  ///   apiKey: 'dev-api-key-12345',
  /// );
  /// ```
  /// 
  /// For production (use Firebase Remote Config):
  /// ```dart
  /// final remoteConfig = FirebaseRemoteConfig.instance;
  /// await remoteConfig.fetchAndActivate();
  /// 
  /// await AppConfig.initialize(
  ///   apiEndpoint: remoteConfig.getString('api_endpoint'),
  ///   apiKey: remoteConfig.getString('api_key'),
  /// );
  /// ```
  static Future<void> initialize({
    String? apiEndpoint,
    String? apiKey,
    String? hmacSecret,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (apiEndpoint != null && apiEndpoint.isNotEmpty) {
      await prefs.setString(_apiEndpointKey, apiEndpoint);
      debugPrint(" API endpoint configured");
    }
    
    if (apiKey != null && apiKey.isNotEmpty) {
      await prefs.setString(_apiKeyKey, apiKey);
      debugPrint(" API key configured");
    }
    
    if (hmacSecret != null && hmacSecret.isNotEmpty) {
      await prefs.setString(_hmacSecretKey, hmacSecret);
      debugPrint(" HMAC secret configured");
    }
    
    // Validate configuration
    final isValid = await validateConfiguration();
    if (!isValid) {
      debugPrint(" WARNING: App configuration is incomplete!");
      debugPrint(" Set API endpoint and keys before using the app");
    }
  }
  
  /// Check if configuration is valid
  static Future<bool> validateConfiguration() async {
    final endpoint = await getApiEndpoint();
    return endpoint != null && endpoint.isNotEmpty;
  }
  
  // 
  // GETTERS
  // 
  
  static Future<String?> getApiEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiEndpointKey);
  }
  
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }
  
  static Future<String?> getHmacSecret() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hmacSecretKey);
  }
  
  // 
  // SECURITY HELPERS
  // 
  
  /// Generate HMAC signature for request authentication
  /// 
  /// Usage:
  /// ```dart
  /// final requestBody = jsonEncode(eventData);
  /// final signature = await AppConfig.generateHmacSignature(requestBody);
  /// 
  /// final response = await http.post(
  ///   uri,
  ///   headers: {
  ///     'X-HMAC-Signature': signature,
  ///     'Content-Type': 'application/json',
  ///   },
  ///   body: requestBody,
  /// );
  /// ```
  static Future<String?> generateHmacSignature(String data) async {
    final secret = await getHmacSecret();
    if (secret == null || secret.isEmpty) {
      debugPrint(" HMAC secret not configured");
      return null;
    }
    
    final key = utf8.encode(secret);
    final bytes = utf8.encode(data);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    
    return digest.toString();
  }
  
  /// Get headers for authenticated requests
  static Future<Map<String, String>> getAuthHeaders({String? body}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'RoadSense/3.0',
    };
    
    final apiKey = await getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    if (body != null && body.isNotEmpty) {
      final signature = await generateHmacSignature(body);
      if (signature != null && signature.isNotEmpty) {
        headers['X-HMAC-Signature'] = signature;
      }
    }
    
    return headers;
  }
  
  // 
  // ADMIN FUNCTIONS
  // 
  
  /// Update API endpoint (admin only)
  static Future<void> updateApiEndpoint(String newEndpoint) async {
    if (!newEndpoint.startsWith('https://')) {
      throw ArgumentError('API endpoint must use HTTPS');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiEndpointKey, newEndpoint);
    debugPrint(" API endpoint updated to: $newEndpoint");
  }
  
  /// Update API key (admin only)
  static Future<void> updateApiKey(String newKey) async {
    if (newKey.length < 20) {
      throw ArgumentError('API key must be at least 20 characters');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, newKey);
    debugPrint(" API key updated");
  }
  
  /// Clear all configuration (use with caution!)
  static Future<void> clearConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiEndpointKey);
    await prefs.remove(_apiKeyKey);
    await prefs.remove(_hmacSecretKey);
    debugPrint(" Configuration cleared");
  }
  
  /// Get configuration status (for debugging)
  static Future<Map<String, dynamic>> getConfigurationStatus() async {
    final endpoint = await getApiEndpoint();
    final hasApiKey = (await getApiKey())?.isNotEmpty ?? false;
    final hasHmacSecret = (await getHmacSecret())?.isNotEmpty ?? false;
    
    return {
      'hasEndpoint': endpoint != null && endpoint.isNotEmpty,
      'endpoint': endpoint != null 
          ? '${endpoint.substring(0, min(30, endpoint.length))}...' 
          : null,
      'hasApiKey': hasApiKey,
      'hasHmacSecret': hasHmacSecret,
      'isValid': endpoint != null && endpoint.isNotEmpty,
    };
  }
}

// ============================================================================
//  SECURITY BEST PRACTICES
// ============================================================================
/*
CRITICAL SECURITY GUIDELINES:


1.  NEVER HARDCODE API ENDPOINTS OR KEYS IN SOURCE CODE
    Bad:  static const apiUrl = "https://script.google.com/...";
    Good: Load from Firebase Remote Config or environment variables

2.  USE HTTPS ONLY
   - Enforce HTTPS in updateApiEndpoint()
   - Never send data over HTTP

3.  IMPLEMENT SERVER-SIDE AUTHENTICATION
   - Validate X-API-Key on backend
   - Rotate API keys periodically
   - Rate limit by API key (100 requests/hour per user)

4.  USE HMAC SIGNATURES FOR REQUEST INTEGRITY
   - Sign request body with HMAC-SHA256
   - Verify signature on server
   - Prevents request tampering

5.  STORE SECRETS SECURELY
   - Use Flutter Secure Storage for production
   - Never commit secrets to Git
   - Use environment variables for CI/CD

6.  IMPLEMENT CERTIFICATE PINNING (Advanced)
   - Pin your server's SSL certificate
   - Prevents man-in-the-middle attacks


RECOMMENDED SETUP:


1. Use Firebase Remote Config:
   ```dart
   // In main.dart
   await Firebase.initializeApp();
   final remoteConfig = FirebaseRemoteConfig.instance;
   
   await remoteConfig.setDefaults({
     'api_endpoint': 'https://your-api.com/v1',
     'api_key': '', // Will be set remotely
   });
   
   await remoteConfig.fetchAndActivate();
   
   await AppConfig.initialize(
     apiEndpoint: remoteConfig.getString('api_endpoint'),
     apiKey: remoteConfig.getString('api_key'),
   );
   ```

2. Backend Implementation (Google Apps Script example):
   ```javascript
   function doPost(e) {
     // 1. Verify API key
     const apiKey = e.parameter.headers['X-API-Key'];
     if (!isValidApiKey(apiKey)) {
       return ContentService.createTextOutput(
         JSON.stringify({error: 'Invalid API key'})
       ).setMimeType(ContentService.MimeType.JSON);
     }
     
     // 2. Rate limiting
     if (isRateLimited(apiKey)) {
       return ContentService.createTextOutput(
         JSON.stringify({error: 'Rate limit exceeded'})
       ).setMimeType(ContentService.MimeType.JSON);
     }
     
     // 3. Verify HMAC signature (optional but recommended)
     const signature = e.parameter.headers['X-HMAC-Signature'];
     if (!verifyHmacSignature(e.postData.contents, signature)) {
       return ContentService.createTextOutput(
         JSON.stringify({error: 'Invalid signature'})
       ).setMimeType(ContentService.MimeType.JSON);
     }
     
     // 4. Process request
     // ... your logic here
   }
   ```

3. Environment Variables (.env):
   ```
   API_ENDPOINT=https://your-api.com/v1
   API_KEY=your-secure-api-key-min-32-chars
   HMAC_SECRET=your-hmac-secret-min-32-chars
   ```

4. .gitignore:
   ```
   .env
   *.key
   secrets/
   ```


MIGRATION FROM OLD CODE:


Old code (INSECURE):
```dart
static const String scriptUrl = "https://script.google.com/macros/s/...";
```

New code (SECURE):
```dart
// In main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize configuration
  await AppConfig.initialize(
    apiEndpoint: 'YOUR_ENDPOINT_HERE',  // Replace with actual endpoint
    apiKey: 'YOUR_API_KEY_HERE',        // Replace with actual key
  );
  
  // Initialize services
  await SensorData.initialize();
  await EventService.initialize();
  
  runApp(MyApp());
}
```


*/
