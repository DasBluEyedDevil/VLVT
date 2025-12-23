import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';

/// Standardized API result wrapper for consistent error handling
class ApiResult<T> {
  final T? data;
  final Map<String, dynamic>? rawData;
  final String? error;
  final dynamic details;
  final int statusCode;
  final bool isSuccess;

  ApiResult._({
    this.data,
    this.rawData,
    this.error,
    this.details,
    required this.statusCode,
    required this.isSuccess,
  });

  factory ApiResult.success(T data, int statusCode) => ApiResult._(
        data: data,
        statusCode: statusCode,
        isSuccess: true,
      );

  factory ApiResult.successRaw(Map<String, dynamic> data, int statusCode) =>
      ApiResult._(
        rawData: data,
        statusCode: statusCode,
        isSuccess: true,
      );

  factory ApiResult.error(String error, {int statusCode = 0, dynamic details}) =>
      ApiResult._(
        error: error,
        details: details,
        statusCode: statusCode,
        isSuccess: false,
      );

  /// Get data or throw exception if error
  T getOrThrow() {
    if (isSuccess && data != null) {
      return data as T;
    }
    throw Exception(error ?? 'Request failed');
  }

  /// Get raw data or throw exception if error
  Map<String, dynamic> getRawOrThrow() {
    if (isSuccess && rawData != null) {
      return rawData!;
    }
    throw Exception(error ?? 'Request failed');
  }
}

/// Base class for all API services with standardized auth, error handling, and retry logic
abstract class BaseApiService extends ChangeNotifier {
  final AuthService authService;

  BaseApiService(this.authService);

  /// Override in subclass to provide service-specific base URL
  String get baseUrl;

  /// Get authorization headers with JWT token
  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (authService.token != null) 'Authorization': 'Bearer ${authService.token}',
      };

  /// Standardized GET with 401 retry and error parsing
  Future<ApiResult<T>> get<T>(
    String path, {
    T Function(Map<String, dynamic>)? parser,
    Map<String, String>? queryParameters,
    Duration? timeout,
  }) async {
    return _executeWithRetry(() async {
      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: queryParameters?.isNotEmpty == true ? queryParameters : null,
      );

      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(timeout ?? const Duration(seconds: 30));
      return _parseResponse(response, parser);
    });
  }

  /// Standardized POST with 401 retry
  Future<ApiResult<T>> post<T>(
    String path, {
    Object? body,
    T Function(Map<String, dynamic>)? parser,
    Duration? timeout,
  }) async {
    return _executeWithRetry(() async {
      final response = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _authHeaders,
            body: body is String ? body : json.encode(body),
          )
          .timeout(timeout ?? const Duration(seconds: 30));
      return _parseResponse(response, parser);
    });
  }

  /// Standardized PUT with 401 retry
  Future<ApiResult<T>> put<T>(
    String path, {
    Object? body,
    T Function(Map<String, dynamic>)? parser,
    Duration? timeout,
  }) async {
    return _executeWithRetry(() async {
      final response = await http
          .put(
            Uri.parse('$baseUrl$path'),
            headers: _authHeaders,
            body: body is String ? body : json.encode(body),
          )
          .timeout(timeout ?? const Duration(seconds: 30));
      return _parseResponse(response, parser);
    });
  }

  /// Standardized DELETE with 401 retry
  Future<ApiResult<T>> delete<T>(
    String path, {
    T Function(Map<String, dynamic>)? parser,
    Duration? timeout,
  }) async {
    return _executeWithRetry(() async {
      final response = await http
          .delete(Uri.parse('$baseUrl$path'), headers: _authHeaders)
          .timeout(timeout ?? const Duration(seconds: 30));
      return _parseResponse(response, parser);
    });
  }

  /// Execute request with automatic 401 retry after token refresh
  Future<ApiResult<T>> _executeWithRetry<T>(
    Future<ApiResult<T>> Function() request,
  ) async {
    var result = await request();

    if (result.statusCode == 401) {
      debugPrint('BaseApiService: 401 received, attempting token refresh');
      final refreshed = await authService.refreshToken();
      if (refreshed) {
        debugPrint('BaseApiService: Token refreshed, retrying request');
        result = await request();
      } else {
        debugPrint('BaseApiService: Token refresh failed, signing out');
        await authService.signOut();
        return ApiResult.error('Session expired. Please sign in again.',
            statusCode: 401);
      }
    }

    return result;
  }

  /// Standardized response parsing with error extraction
  ApiResult<T> _parseResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic>)? parser,
  ) {
    try {
      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (data['success'] == true && parser != null) {
          return ApiResult.success(parser(data), response.statusCode);
        }
        return ApiResult.successRaw(data, response.statusCode);
      }

      // Standardized error extraction
      final error = data['error'] ?? data['message'] ?? 'Request failed';
      final details = data['details'] ?? data['errors'];
      return ApiResult.error(error.toString(),
          statusCode: response.statusCode, details: details);
    } catch (e) {
      debugPrint('Error parsing response: $e');
      return ApiResult.error('Failed to parse response',
          statusCode: response.statusCode);
    }
  }

  // ===== Legacy methods for backward compatibility =====
  // These wrap the new methods to maintain existing API contracts

  /// Make a GET request with automatic 401 retry after token refresh
  /// Returns the raw http.Response for legacy compatibility
  @protected
  Future<http.Response> authenticatedGet(Uri uri) async {
    var response = await http.get(uri, headers: _authHeaders);

    if (response.statusCode == 401) {
      debugPrint('Got 401, attempting token refresh...');
      final refreshed = await authService.refreshToken();
      if (refreshed) {
        debugPrint('Token refreshed, retrying request...');
        response = await http.get(uri, headers: _authHeaders);
      }
    }

    return response;
  }

  /// Make a POST request with automatic 401 retry after token refresh
  @protected
  Future<http.Response> authenticatedPost(Uri uri, {Object? body}) async {
    final encodedBody = body is String ? body : json.encode(body);
    var response = await http.post(uri, headers: _authHeaders, body: encodedBody);

    if (response.statusCode == 401) {
      debugPrint('Got 401, attempting token refresh...');
      final refreshed = await authService.refreshToken();
      if (refreshed) {
        debugPrint('Token refreshed, retrying request...');
        response = await http.post(uri, headers: _authHeaders, body: encodedBody);
      }
    }

    return response;
  }

  /// Make a PUT request with automatic 401 retry after token refresh
  @protected
  Future<http.Response> authenticatedPut(Uri uri, {Object? body}) async {
    final encodedBody = body is String ? body : json.encode(body);
    var response = await http.put(uri, headers: _authHeaders, body: encodedBody);

    if (response.statusCode == 401) {
      debugPrint('Got 401, attempting token refresh...');
      final refreshed = await authService.refreshToken();
      if (refreshed) {
        debugPrint('Token refreshed, retrying request...');
        response = await http.put(uri, headers: _authHeaders, body: encodedBody);
      }
    }

    return response;
  }

  /// Make a DELETE request with automatic 401 retry after token refresh
  @protected
  Future<http.Response> authenticatedDelete(Uri uri) async {
    var response = await http.delete(uri, headers: _authHeaders);

    if (response.statusCode == 401) {
      debugPrint('Got 401, attempting token refresh...');
      final refreshed = await authService.refreshToken();
      if (refreshed) {
        debugPrint('Token refreshed, retrying request...');
        response = await http.delete(uri, headers: _authHeaders);
      }
    }

    return response;
  }
}
