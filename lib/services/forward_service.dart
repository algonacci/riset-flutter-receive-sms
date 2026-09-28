import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/sms_entry.dart';

enum ForwardOutcome { saved, rejected, failed }

class ForwardService {
  ForwardService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  Uri? _endpoint(String baseUrl, String path) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    final uri = Uri.tryParse('$base$path');
    if (uri == null || !uri.hasScheme) return null;
    if (uri.host == '0.0.0.0') return null; // bukan alamat tujuan yang valid
    return uri;
  }

  Future<ForwardOutcome> forward({
    required String baseUrl,
    required SmsEntry entry,
    String gatewayId = '',
  }) async {
    final uri = _endpoint(baseUrl, '/api/sms');
    if (uri == null) return ForwardOutcome.failed;
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sender': entry.address,
              'message': entry.body,
              'timestamp': entry.timestamp,
              if (gatewayId.isNotEmpty) 'gateway_id': gatewayId,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return ForwardOutcome.saved;
      }
      if (response.statusCode == 400) {
        return ForwardOutcome.rejected;
      }
      return ForwardOutcome.failed;
    } catch (_) {
      return ForwardOutcome.failed;
    }
  }

  Future<bool> testConnection(String baseUrl) async {
    final uri = _endpoint(baseUrl, '/api/health');
    if (uri == null) return false;
    try {
      final response = await _client.get(uri).timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
