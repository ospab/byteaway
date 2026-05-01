import 'package:dio/dio.dart';
import '../constants.dart';
import '../errors/exceptions.dart';

/// Dio HTTP client wrapper with Bearer token auth and retry logic.
///
/// Automatically injects `Authorization: Bearer <token>` into every request.
/// Maps Dio errors to typed exceptions for repository layer consumption.
class ApiClient {
  late final Dio _dio;
  String? _token;
  
  static const int _maxRetries = 3;
  static const int _initialDelayMs = 500;

  ApiClient({String? token}) : _token = token {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null && _token!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );
  }

  /// Update the bearer token (e.g. after login).
  void setToken(String token) {
    _token = token;
  }

  /// Clear the stored token (e.g. on logout).
  void clearToken() {
    _token = null;
  }

  /// Perform a GET request with retry logic.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _executeWithRetry(() => _dio.get(
      path,
      queryParameters: queryParameters,
    ));
  }

  /// Perform a POST request with retry logic.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    return _executeWithRetry(() => _dio.post(path, data: data));
  }

  Future<Map<String, dynamic>> _executeWithRetry(
    Future<Response> Function() request,
  ) async {
    int attempts = 0;
    int delayMs = _initialDelayMs;

    while (true) {
      try {
        final response = await request();
        return response.data as Map<String, dynamic>;
      } on DioException catch (e) {
        // Retry only on network errors or 5xx server errors
        final shouldRetry = _shouldRetry(e);
        
        if (!shouldRetry || attempts >= _maxRetries) {
          throw _mapDioError(e);
        }

        attempts++;
        await Future.delayed(Duration(milliseconds: delayMs));
        delayMs *= 2; // Exponential backoff
      }
    }
  }

  bool _shouldRetry(DioException e) {
    // Retry on connection errors
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    // Retry on server errors (5xx)
    final statusCode = e.response?.statusCode;
    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      return true;
    }
    return false;
  }

  /// Maps [DioException] to domain exceptions.
  Exception _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkException('Сервер недоступен');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 401 || statusCode == 403) {
          return const AuthException('Неверный или просроченный токен');
        }
        return ServerException(
          message: e.response?.statusMessage ?? 'Ошибка сервера',
          statusCode: statusCode,
        );
      default:
        return const NetworkException('Ошибка сети');
    }
  }
}
