import 'package:dio/dio.dart';
import '../constants.dart';
import '../errors/exceptions.dart';

/// Dio HTTP client wrapper with Bearer token auth.
///
/// Automatically injects `Authorization: Bearer <token>` into every request.
/// Maps Dio errors to typed exceptions for repository layer consumption.
class ApiClient {
  late final Dio _dio;
  String? _token;

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

  /// Perform a GET request and return decoded JSON.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Perform a POST request with optional body.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
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
