import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sms/receive_sms.dart';

import 'data/sms_store.dart';
import 'models/sms_entry.dart';
import 'services/inbox_syncer.dart';
import 'services/permission_service.dart';

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

class _SmsInboxPageState extends State<SmsInboxPage>
    with WidgetsBindingObserver {
  final ReceiveSms _receiveSms = ReceiveSms();
  final SmsStore _store = SmsStore();
  final InboxSyncer _syncer = InboxSyncer();
  final PermissionService _permission = PermissionService();
  List<SmsEntry> _messages = [];

  late final Future<void> _storeFuture;
  StreamSubscription<SmsMessage>? _subscription;

  String _status = 'Belum ada izin SMS';
  bool _granted = false;
  bool _canRequest = true;
  bool _storeReady = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storeFuture = _openStore();
    _start();
    _subscription = _receiveSms.incomingSmsStream.listen(
      _onIncomingSms,
      onError: _onStreamError,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _granted) {
      _syncAndReload();
    }
  }

  Future<void> _openStore() async {
    try {
      await _store.init();
      _storeReady = true;
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Gagal buka database: $e');
      }
    }
  }

  Future<void> _start() async {
    await _storeFuture;
    if (!_storeReady) return;
    await _reload();

    final status = await _permission.check();
    if (!mounted) return;
    setState(() {
      _granted = status.granted;
      _canRequest = status.canRequest;
      if (status.granted) {
        _status = 'Izin SMS diberikan';
      } else if (status.canRequest) {
        _status = 'Belum ada izin SMS';
      } else {
        _status = 'Izin SMS ditolak permanen';
      }
    });
    if (status.granted) {
      await _syncAndReload();
    }
  }

  Future<void> _onIncomingSms(SmsMessage message) async {
    await _storeFuture;
    if (!_storeReady || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final timestamp = int.tryParse(message.timestamp) ?? now;
    await _store.insert(SmsEntry(
      address: message.address,
      body: message.body,
      timestamp: timestamp,
      receivedAt: now,
    ));
    await _reload();
  }

  void _onStreamError(Object error) {
    if (!mounted || _granted) return;
    setState(() => _status = 'Stream error: $error');
  }

  Future<void> _reload() async {
    if (!_storeReady) return;
    final messages = await _store.getAll();
    if (!mounted) return;
    setState(() => _messages = messages);
  }

  Future<void> _syncAndReload() async {
    if (!_storeReady || _syncing) return;
    _syncing = true;
    try {
      await _syncer.sync(_store);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Sinkron inbox gagal: $e');
      }
    } finally {
      _syncing = false;
    }
    await _reload();
  }

  Future<void> _requestPermission() async {
    try {
      final status = await _permission.request();
      if (!mounted) return;
      setState(() {
        _granted = status.granted;
        _canRequest = status.canRequest;
        if (status.granted) {
          _status = 'Izin SMS diberikan';
        } else if (status.canRequest) {
          _status = 'Izin SMS ditolak';
        } else {
          _status = 'Izin SMS ditolak permanen';
        }
      });
      if (status.granted) {
        await _syncAndReload();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Gagal meminta izin: $e');
    }
  }

  void _openSettings() {
    try {
      _permission.openSettings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Gagal membuka pengaturan: $e');
    }
  }

  Future<void> _deleteEntry(SmsEntry entry) async {
    final id = entry.id;
    if (id == null) return;
    await _store.deleteById(id);
    if (!mounted) return;
    setState(() => _messages = _messages.where((m) => m.id != id).toList());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          entry.address.isEmpty
              ? 'SMS dihapus'
              : 'SMS dari ${entry.address} dihapus',
        ),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () => _restoreEntry(entry),
        ),
      ),
    );
  }

  Future<void> _restoreEntry(SmsEntry entry) async {
    if (!_storeReady) return;
    await _store.insert(SmsEntry(
      address: entry.address,
      body: entry.body,
      timestamp: entry.timestamp,
      receivedAt: entry.receivedAt,
    ));
    await _reload();
  }

  Future<void> _clearAll() async {
    if (_storeReady) {
      await _store.clearAll();
    }
    if (!mounted) return;
    setState(() => _messages.clear());
  }

  String _formatTimestamp(int millis) {
    if (millis <= 0) return '-';
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
            onPressed: _messages.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Bersihkan semua',
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
                    const SizedBox(height: 4),
                    Text(
                      '${_messages.length} SMS tersimpan',
                      style: Theme.of(context).textTheme.labelLarge,
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
                      final entry = _messages[index];
                      return Dismissible(
                        key: ValueKey<int>(
                          entry.id ?? entry.timestamp,
                        ),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red.shade100,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Icon(Icons.delete, color: Colors.red.shade700),
                        ),
                        onDismissed: (_) => _deleteEntry(entry),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.message),
                          ),
                          title: Text(
                            entry.address.isEmpty
                                ? 'Nomor tidak diketahui'
                                : entry.address,
                          ),
                          subtitle: Text(entry.body),
                          trailing: Text(
                            _formatTimestamp(entry.timestamp),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
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
