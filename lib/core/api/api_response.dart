import 'package:flutter_riverpod/flutter_riverpod.dart';

/// API状态
enum ApiStatus { idle, loading, success, error }

/// 统一API响应包装
class ApiResponse<T> {
  final ApiStatus status;
  final T? data;
  final String? errorMessage;
  final int? errorCode;

  const ApiResponse({
    required this.status,
    this.data,
    this.errorMessage,
    this.errorCode,
  });

  factory ApiResponse.idle() => const ApiResponse(status: ApiStatus.idle);
  factory ApiResponse.loading() => const ApiResponse(status: ApiStatus.loading);
  factory ApiResponse.success(T data) => ApiResponse(status: ApiStatus.success, data: data);
  factory ApiResponse.error(String message, {int? code}) => 
      ApiResponse(status: ApiStatus.error, errorMessage: message, errorCode: code);

  bool get isIdle => status == ApiStatus.idle;
  bool get isLoading => status == ApiStatus.loading;
  bool get isSuccess => status == ApiStatus.success;
  bool get isError => status == ApiStatus.error;
  bool get hasData => data != null;
}

/// 通用API Provider State
class ApiStateNotifier<T> extends StateNotifier<ApiResponse<T>> {
  ApiStateNotifier() : super(ApiResponse.idle());

  Future<void> execute(Future<T> Function() apiCall) async {
    state = ApiResponse.loading();
    try {
      final result = await apiCall();
      state = ApiResponse.success(result);
    } catch (e) {
      state = ApiResponse.error(e.toString());
    }
  }

  void reset() {
    state = ApiResponse.idle();
  }
}
