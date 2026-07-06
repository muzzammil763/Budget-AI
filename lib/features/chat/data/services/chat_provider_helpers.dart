part of 'chat_provider.dart';

/// Exception thrown when a request is cancelled by the user
class CancelledException implements Exception {
  @override
  String toString() => 'Request Cancelled';
}

class ChatProviderException implements Exception {
  final String providerName;
  final String userMessage;
  final String debugMessage;
  final String? diagnosticMessage;
  final int? statusCode;

  ChatProviderException({
    required this.providerName,
    required this.userMessage,
    required this.debugMessage,
    this.diagnosticMessage,
    this.statusCode,
  });

  @override
  String toString() => userMessage;
}

String _stringifyProviderPayload(dynamic data) {
  if (data == null) return '';
  if (data is ResponseBody) {
    return 'ResponseBody(status=${data.statusCode})';
  }
  if (data is String) return data.trim();
  try {
    return jsonEncode(data);
  } catch (_) {
    return data.toString().trim();
  }
}

Future<dynamic> _normalizeErrorResponseData(dynamic data) async {
  if (data is! ResponseBody) {
    return data;
  }

  try {
    final bytes = <int>[];
    await for (final chunk in data.stream) {
      bytes.addAll(chunk);
    }

    if (bytes.isEmpty) {
      return {'status': data.statusCode};
    }

    final decoded = utf8.decode(bytes, allowMalformed: true).trim();
    if (decoded.isEmpty) {
      return {'status': data.statusCode};
    }

    try {
      return jsonDecode(decoded);
    } catch (_) {
      return decoded;
    }
  } catch (_) {
    return {'status': data.statusCode};
  }
}

dynamic _firstChoice(dynamic data) {
  if (data is! Map) return null;
  final choices = data['choices'];
  if (choices is! List || choices.isEmpty) return null;
  return choices.first;
}

String? _extractProviderErrorMessage(dynamic data) {
  if (data == null) return null;
  if (data is String) {
    final trimmed = data.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  String? fallbackMessage;
  if (data is Map) {
    for (final key in const [
      'message',
      'error_message',
      'detail',
      'reason',
      'description',
      'provider_message',
      'provider_error',
    ]) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        final message = value.trim();
        if (!_isGenericProviderErrorMessage(message)) {
          return message;
        }
        fallbackMessage ??= message;
      }
    }

    for (final key in const ['error', 'errors', 'details', 'cause']) {
      final nestedMessage = _extractProviderErrorMessage(data[key]);
      if (nestedMessage != null && nestedMessage.isNotEmpty) {
        if (!_isGenericProviderErrorMessage(nestedMessage)) {
          return nestedMessage;
        }
        fallbackMessage ??= nestedMessage;
      }
    }

    for (final key in const ['code', 'type', 'status']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        fallbackMessage ??= value;
      }
    }
  }
  if (data is List && data.isNotEmpty) {
    for (final item in data) {
      final nestedMessage = _extractProviderErrorMessage(item);
      if (nestedMessage != null && nestedMessage.isNotEmpty) {
        if (!_isGenericProviderErrorMessage(nestedMessage)) {
          return nestedMessage;
        }
        fallbackMessage ??= nestedMessage;
      }
    }
  }
  return fallbackMessage;
}

bool _isGenericProviderErrorMessage(String message) {
  final normalized = message.toLowerCase().trim();
  return normalized == 'provider returned error' ||
      normalized == 'the provider returned an error' ||
      normalized == 'upstream provider returned error';
}

String? _buildProviderDiagnosticMessage({
  int? statusCode,
  Object? error,
  dynamic responseData,
}) {
  final details = <String>[];
  if (statusCode != null) {
    details.add('HTTP status: $statusCode');
  }
  if (error != null) {
    details.add('Client error: $error');
  }
  final responseText = _stringifyProviderPayload(responseData);
  if (responseText.isNotEmpty) {
    const maxResponseLength = 1800;
    final trimmedResponse = responseText.length > maxResponseLength
        ? '${responseText.substring(0, maxResponseLength)}...'
        : responseText;
    details.add('Provider response: $trimmedResponse');
  }

  return details.isEmpty ? null : details.join('\n');
}

ChatProviderException _providerException(
  String providerName,
  String userMessage, {
  int? statusCode,
  Object? error,
  dynamic responseData,
  bool log = true,
}) {
  final debugDetails = <String>[];
  if (statusCode != null) {
    debugDetails.add('status=$statusCode');
  }
  if (error != null) {
    debugDetails.add('error=$error');
  }
  final responseText = _stringifyProviderPayload(responseData);
  if (responseText.isNotEmpty) {
    debugDetails.add('response=$responseText');
  }
  final diagnosticMessage = _buildProviderDiagnosticMessage(
    statusCode: statusCode,
    error: error,
    responseData: responseData,
  );

  final debugMessage = debugDetails.isEmpty
      ? userMessage
      : '$userMessage | ${debugDetails.join(' | ')}';
  if (log) {
    debugPrint('[$providerName] $debugMessage');
  }

  return ChatProviderException(
    providerName: providerName,
    userMessage: userMessage,
    debugMessage: debugMessage,
    diagnosticMessage: diagnosticMessage,
    statusCode: statusCode,
  );
}

ChatProviderException _mapHttpFailure(
  String providerName, {
  required int statusCode,
  dynamic responseData,
  bool log = true,
}) {
  final apiMessage = _extractProviderErrorMessage(responseData);

  switch (statusCode) {
    case 400:
      return _providerException(
        providerName,
        apiMessage != null && apiMessage.isNotEmpty
            ? '$providerName rejected the request: $apiMessage'
            : '$providerName rejected the request. Check the selected model, message format, or tool-call settings.',
        statusCode: statusCode,
        responseData: responseData,
        log: log,
      );
    case 401:
    case 403:
      return _providerException(
        providerName,
        '$providerName authentication failed. Check your API key and confirm it has access to the selected model.',
        statusCode: statusCode,
        responseData: responseData,
        log: log,
      );
    case 402:
      return _providerException(
        providerName,
        apiMessage != null && apiMessage.isNotEmpty
            ? '$providerName quota or credits were exhausted: $apiMessage'
            : '$providerName quota or credits were exhausted. Check billing and usage limits.',
        statusCode: statusCode,
        responseData: responseData,
        log: log,
      );
    case 404:
      return _providerException(
        providerName,
        '$providerName could not find the requested model or endpoint. Verify the selected model and provider configuration.',
        statusCode: statusCode,
        responseData: responseData,
        log: log,
      );
    case 408:
      return _providerException(
        providerName,
        '$providerName timed out before completing the request. Please try again.',
        statusCode: statusCode,
        responseData: responseData,
        log: log,
      );
    case 429:
      return _providerException(
        providerName,
        '$providerName rate limit or quota was reached. Wait a moment or check your billing and usage limits.',
        statusCode: statusCode,
        responseData: responseData,
        log: log,
      );
    default:
      if (statusCode >= 500) {
        return _providerException(
          providerName,
          '$providerName is having server issues right now (HTTP $statusCode). Please try again shortly.',
          statusCode: statusCode,
          responseData: responseData,
          log: log,
        );
      }

      return _providerException(
        providerName,
        apiMessage != null && apiMessage.isNotEmpty
            ? '$providerName request failed: $apiMessage'
            : '$providerName request failed with HTTP $statusCode.',
        statusCode: statusCode,
        responseData: responseData,
        log: log,
      );
  }
}

bool _shouldTryNextApiKeyStatus(int? statusCode) {
  return statusCode == 400 ||
      statusCode == 401 ||
      statusCode == 402 ||
      statusCode == 403 ||
      statusCode == 429;
}

void _promoteApiKeyForSession(List<String> apiKeys, String apiKey) {
  final index = apiKeys.indexOf(apiKey);
  if (index <= 0) return;
  apiKeys
    ..removeAt(index)
    ..insert(0, apiKey);
}

String _maskApiKeyForLogs(String apiKey) {
  final trimmed = apiKey.trim();
  if (trimmed.isEmpty) return '<empty>';
  if (trimmed.length <= 10) {
    return '${trimmed.substring(0, 2)}***${trimmed.substring(trimmed.length - 2)}';
  }
  return '${trimmed.substring(0, 6)}...${trimmed.substring(trimmed.length - 4)}';
}

Future<ChatProviderException> _mapDioException(
  String providerName,
  DioException error, {
  bool log = true,
}) async {
  final statusCode = error.response?.statusCode;
  final responseData = await _normalizeErrorResponseData(error.response?.data);

  if (statusCode != null) {
    return _mapHttpFailure(
      providerName,
      statusCode: statusCode,
      responseData: responseData,
      log: log,
    );
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return _providerException(
        providerName,
        '$providerName timed out while waiting for a response.',
        error: error.message,
        responseData: responseData,
        log: log,
      );
    case DioExceptionType.connectionError:
      return _providerException(
        providerName,
        'Could not connect to $providerName. Check your internet connection and provider endpoint.',
        error: error.message,
        responseData: responseData,
        log: log,
      );
    case DioExceptionType.badCertificate:
      return _providerException(
        providerName,
        '$providerName connection failed because of an invalid certificate.',
        error: error.message,
        responseData: responseData,
        log: log,
      );
    case DioExceptionType.cancel:
      return _providerException(
        providerName,
        '$providerName request was cancelled.',
        error: error.message,
        responseData: responseData,
        log: log,
      );
    case DioExceptionType.unknown:
    case DioExceptionType.badResponse:
      return _providerException(
        providerName,
        _extractProviderErrorMessage(responseData) ??
            error.message ??
            '$providerName request failed unexpectedly.',
        error: error.message,
        responseData: responseData,
        log: log,
      );
  }
}

Future<Response<ResponseBody>> _postStreamWithApiKeyFallback({
  required Dio dio,
  required String url,
  required List<String> apiKeys,
  required String providerName,
  required Object? data,
  required CancelToken? cancelToken,
  required void Function(String apiKey) onKeySelected,
}) async {
  if (apiKeys.isEmpty) {
    throw _providerException(
      providerName,
      '$providerName API key is missing. Add it in Settings > API Keys.',
    );
  }

  Object? lastError;

  for (var index = 0; index < apiKeys.length; index++) {
    final apiKey = apiKeys[index];
    final keyLabel = 'key ${index + 1}/${apiKeys.length}';
    final maskedKey = _maskApiKeyForLogs(apiKey);
    var retryCount = 0;
    const max429Retries = 1;

    requestKey:
    while (true) {
      debugPrint(
        '[$providerName] Attempting request with $keyLabel ($maskedKey)${retryCount > 0 ? ' (retry $retryCount/$max429Retries)' : ''}',
      );
      try {
        final response = await dio.post<ResponseBody>(
          url,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            responseType: ResponseType.stream,
          ),
          data: data,
          cancelToken: cancelToken,
        );

        if (response.statusCode != 200) {
          final errorData = await _normalizeErrorResponseData(response.data);
          final is429 = response.statusCode == 429;
          final canTryNextKey =
              _shouldTryNextApiKeyStatus(response.statusCode) &&
              index < apiKeys.length - 1;
          final mappedError = _mapHttpFailure(
            providerName,
            statusCode: response.statusCode ?? 0,
            responseData: errorData,
            log: !canTryNextKey && !(is429 && retryCount < max429Retries),
          );

          if (is429 && retryCount < max429Retries) {
            retryCount++;
            debugPrint(
              '[$providerName] 429 received, retrying same key in 3s...',
            );
            await Future.delayed(const Duration(seconds: 3));
            continue requestKey;
          }

          if (canTryNextKey) {
            debugPrint(
              '[$providerName] $keyLabel ($maskedKey) failed with HTTP ${response.statusCode}. Falling back to next key.',
            );
            lastError = mappedError;
            break requestKey;
          }

          throw mappedError;
        }

        debugPrint(
          '[$providerName] Request succeeded with $keyLabel ($maskedKey)',
        );
        _promoteApiKeyForSession(apiKeys, apiKey);
        onKeySelected(apiKey);
        return response;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          throw CancelledException();
        }

        final statusCode = error.response?.statusCode;
        final is429 = statusCode == 429;
        final canTryNextKey =
            _shouldTryNextApiKeyStatus(statusCode) &&
            index < apiKeys.length - 1;
        final mappedError = await _mapDioException(
          providerName,
          error,
          log: !canTryNextKey && !(is429 && retryCount < max429Retries),
        );

        if (is429 && retryCount < max429Retries) {
          retryCount++;
          debugPrint(
            '[$providerName] 429 received, retrying same key in 3s...',
          );
          await Future.delayed(const Duration(seconds: 3));
          continue requestKey;
        }

        if (canTryNextKey) {
          debugPrint(
            '[$providerName] $keyLabel ($maskedKey) failed with ${mappedError.statusCode ?? 'request error'}. Falling back to next key.',
          );
          lastError = mappedError;
          break requestKey;
        }

        throw mappedError;
      }
    }
  }

  debugPrint(
    '[$providerName] All configured API keys failed. Total tried: ${apiKeys.length}',
  );
  throw lastError ??
      _providerException(
        providerName,
        '$providerName request failed for all configured API keys.',
      );
}

Future<Response<dynamic>> _postJsonWithApiKeyFallback({
  required Dio dio,
  required String url,
  required List<String> apiKeys,
  required String providerName,
  required Object? data,
  required void Function(String apiKey) onKeySelected,
}) async {
  if (apiKeys.isEmpty) {
    throw _providerException(
      providerName,
      '$providerName API key is missing. Add it in Settings > API Keys.',
    );
  }

  Object? lastError;

  for (var index = 0; index < apiKeys.length; index++) {
    final apiKey = apiKeys[index];
    final keyLabel = 'key ${index + 1}/${apiKeys.length}';
    final maskedKey = _maskApiKeyForLogs(apiKey);
    var retryCount = 0;
    const max429Retries = 1;

    requestKey:
    while (true) {
      debugPrint(
        '[$providerName] Attempting JSON request with $keyLabel ($maskedKey)${retryCount > 0 ? ' (retry $retryCount/$max429Retries)' : ''}',
      );
      try {
        final response = await dio.post(
          url,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
          ),
          data: data,
        );

        if (response.statusCode != 200) {
          final is429 = response.statusCode == 429;
          final canTryNextKey =
              _shouldTryNextApiKeyStatus(response.statusCode) &&
              index < apiKeys.length - 1;
          final mappedError = _mapHttpFailure(
            providerName,
            statusCode: response.statusCode ?? 0,
            responseData: response.data,
            log: !canTryNextKey && !(is429 && retryCount < max429Retries),
          );

          if (is429 && retryCount < max429Retries) {
            retryCount++;
            debugPrint(
              '[$providerName] 429 received, retrying same key in 3s...',
            );
            await Future.delayed(const Duration(seconds: 3));
            continue requestKey;
          }

          if (canTryNextKey) {
            debugPrint(
              '[$providerName] $keyLabel ($maskedKey) failed with HTTP ${response.statusCode}. Falling back to next key.',
            );
            lastError = mappedError;
            break requestKey;
          }

          throw mappedError;
        }

        debugPrint(
          '[$providerName] JSON request succeeded with $keyLabel ($maskedKey)',
        );
        _promoteApiKeyForSession(apiKeys, apiKey);
        onKeySelected(apiKey);
        return response;
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        final is429 = statusCode == 429;
        final canTryNextKey =
            _shouldTryNextApiKeyStatus(statusCode) &&
            index < apiKeys.length - 1;
        final mappedError = await _mapDioException(
          providerName,
          error,
          log: !canTryNextKey && !(is429 && retryCount < max429Retries),
        );

        if (is429 && retryCount < max429Retries) {
          retryCount++;
          debugPrint(
            '[$providerName] 429 received, retrying same key in 3s...',
          );
          await Future.delayed(const Duration(seconds: 3));
          continue requestKey;
        }

        if (canTryNextKey) {
          debugPrint(
            '[$providerName] $keyLabel ($maskedKey) failed with ${mappedError.statusCode ?? 'request error'}. Falling back to next key.',
          );
          lastError = mappedError;
          break requestKey;
        }

        throw mappedError;
      }
    }
  }

  debugPrint(
    '[$providerName] All configured API keys failed for JSON request. Total tried: ${apiKeys.length}',
  );
  throw lastError ??
      _providerException(
        providerName,
        '$providerName request failed for all configured API keys.',
      );
}

/// Tracks tool-call budget, deduplication, and loop detection for a single
/// agentic turn (the `do…while` loop inside `sendMessageStreamWithThinking`).
