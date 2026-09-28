import 'package:permission_handler/permission_handler.dart';

class SmsPermissionStatus {
  const SmsPermissionStatus({
    required this.granted,
    required this.canRequest,
  });

  final bool granted;
  final bool canRequest;
}

class PermissionService {
  Future<SmsPermissionStatus> check() async {
    try {
      final status = await Permission.sms.status;
      return _from(status);
    } catch (_) {
      return const SmsPermissionStatus(granted: false, canRequest: true);
    }
  }

  Future<SmsPermissionStatus> request() async {
    final results = await [Permission.sms].request();
    return _from(results[Permission.sms] ?? PermissionStatus.denied);
  }

  SmsPermissionStatus _from(PermissionStatus status) {
    return SmsPermissionStatus(
      granted: status.isGranted,
      canRequest: !status.isPermanentlyDenied,
    );
  }

  void openSettings() {
    openAppSettings();
  }
}
