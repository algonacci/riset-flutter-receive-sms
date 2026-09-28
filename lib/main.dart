import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sms/receive_sms.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riset Receive SMS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SmsInboxPage(),
    );
  }
}

class SmsInboxPage extends StatefulWidget {
  const SmsInboxPage({super.key});

  @override
  State<SmsInboxPage> createState() => _SmsInboxPageState();
}

class _SmsInboxPageState extends State<SmsInboxPage> {
  final ReceiveSms _receiveSms = ReceiveSms();
  final List<SmsMessage> _messages = [];

  StreamSubscription<SmsMessage>? _subscription;
  String _status = 'Belum ada izin SMS';
  bool _granted = false;
  bool _canRequest = true;

  @override
  void initState() {
    super.initState();
    _subscription = _receiveSms.incomingSmsStream.listen(
      (message) {
        if (!mounted) return;
        setState(() => _messages.insert(0, message));
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _status = 'Stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    try {
      final result = await _receiveSms.requestPermission();
      if (!mounted) return;
      setState(() {
        _granted = result.granted;
        _canRequest = result.canRequest;
        if (result.granted) {
          _status = 'Izin SMS diberikan, menunggu SMS masuk...';
        } else if (result.canRequest) {
          _status = 'Izin SMS ditolak';
        } else {
          _status = 'Izin SMS ditolak permanen';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Gagal meminta izin: $e');
    }
  }

  Future<void> _openSettings() async {
    try {
      await _receiveSms.openAppSettings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Gagal membuka pengaturan: $e');
    }
  }

  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return '-';
    final millis = int.tryParse(raw);
    if (millis == null) return raw;
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    return '${dt.day.toString().padLeft(2, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Riset Receive SMS'),
        actions: [
          IconButton(
            onPressed: _messages.isEmpty
                ? null
                : () => setState(() => _messages.clear()),
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Bersihkan',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _granted ? null : _requestPermission,
                          icon: const Icon(Icons.sms),
                          label: const Text('Minta Izin SMS'),
                        ),
                        if (_granted || !_canRequest)
                          OutlinedButton.icon(
                            onPressed: _openSettings,
                            icon: const Icon(Icons.settings),
                            label: const Text('Pengaturan'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada SMS masuk.\nKirim SMS ke perangkat ini untuk mencoba.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: _messages.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.message),
                        ),
                        title: Text(
                          message.address.isEmpty
                              ? 'Nomor tidak diketahui'
                              : message.address,
                        ),
                        subtitle: Text(message.body),
                        trailing: Text(
                          _formatTimestamp(message.timestamp),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
