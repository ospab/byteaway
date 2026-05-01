import 'package:dio/dio.dart';
import '../constants.dart';

class ApiClient {
  ApiClient() : _dio = Dio(BaseOptions(baseUrl: AppConstants.baseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null && _token!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  String? _token;

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) async {
    final response = await _dio.get(path, queryParameters: query);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> postJson(String path, {Map<String, dynamic>? data}) async {
    final response = await _dio.post(path, data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }
}
