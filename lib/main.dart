import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sms/receive_sms.dart';

import 'data/sms_store.dart';
import 'models/allowed_sender.dart';
import 'models/sms_entry.dart';
import 'pages/sender_settings_page.dart';
import 'services/forward_service.dart';
import 'services/inbox_syncer.dart';
import 'services/permission_service.dart';
import 'services/sender_allowlist.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E56)),
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
  final ForwardService _forward = ForwardService();
  List<SmsEntry> _messages = [];

  late final Future<void> _storeFuture;
  StreamSubscription<SmsMessage>? _subscription;

  String _status = 'Belum ada izin SMS';
  bool _granted = false;
  bool _canRequest = true;
  bool _storeReady = false;
  bool _syncing = false;
  bool _forwarding = false;
  String _backendUrl = '';
  String _gatewayId = '';
  String _apiKey = '';
  int _pendingCount = 0;
  List<AllowedSender> _allowedSenders = [];
  SenderAllowlist _allowlist = const SenderAllowlist([]);
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

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
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _granted) {
      _syncAndReload();
      _forwardPending();
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
    await _reloadAllowlist();
    await _loadBackendSettings();
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
    await _forwardPending();
  }

  Future<void> _loadBackendSettings() async {
    if (!_storeReady) return;
    final url = await _store.getSetting('backend_url');
    final gatewayId = await _store.getSetting('gateway_id');
    final apiKey = await _store.getSetting('api_key');
    if (!mounted) return;
    setState(() {
      _backendUrl = url ?? '';
      _gatewayId = gatewayId ?? '';
      _apiKey = apiKey ?? '';
    });
  }

  Future<void> _onIncomingSms(SmsMessage message) async {
    await _storeFuture;
    if (!_storeReady || !mounted) return;
    if (!_allowlist.allows(message.address)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final timestamp = int.tryParse(message.timestamp) ?? now;
    await _store.insert(SmsEntry(
      address: message.address,
      body: message.body,
      timestamp: timestamp,
      receivedAt: now,
    ));
    await _reload();
    await _forwardPending();
  }

  void _onStreamError(Object error) {
    if (!mounted || _granted) return;
    setState(() => _status = 'Stream error: $error');
  }

  Future<void> _reloadAllowlist() async {
    if (!_storeReady) return;
    final senders = await _store.getAllowedSenders();
    if (!mounted) return;
    setState(() {
      _allowedSenders = senders;
      _allowlist = SenderAllowlist(
        senders.map((sender) => sender.number).toList(),
      );
    });
  }

  Future<void> _reload() async {
    if (!_storeReady) return;
    final messages = await _store.getAll();
    final pending = await _store.countUnforwarded();
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _pendingCount = pending;
    });
  }

  Future<void> _forwardPending() async {
    if (!_storeReady || _forwarding) return;
    if (_backendUrl.trim().isEmpty) return;
    _forwarding = true;
    try {
      final pending = await _store.getUnforwarded();
      for (final entry in pending) {
        if (!_allowlist.allows(entry.address)) continue;
        final outcome = await _forward.forward(
          baseUrl: _backendUrl,
          entry: entry,
          gatewayId: _gatewayId,
          apiKey: _apiKey,
        );
        if (outcome == ForwardOutcome.saved) {
          await _store.markForwarded(entry.id!);
          continue;
        }
        if (outcome == ForwardOutcome.rejected) {
          continue;
        }
        break; // server gagal — coba lagi nanti
      }
    } finally {
      _forwarding = false;
    }
    await _reload();
  }

  Future<void> _syncAndReload() async {
    if (!_storeReady || _syncing) return;
    _syncing = true;
    try {
      await _syncer.sync(_store, allowlist: _allowlist);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Sinkron inbox gagal: $e');
      }
    } finally {
      _syncing = false;
    }
    await _reload();
    await _forwardPending();
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

  Future<void> _openSenderSettings() async {
    if (!_storeReady) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SenderSettingsPage(store: _store, forward: _forward),
      ),
    );
    await _reloadAllowlist();
    await _loadBackendSettings();
    await _reload();
    await _forwardPending();
  }

  Future<void> _deleteEntry(SmsEntry entry) async {
    final id = entry.id;
    if (id == null) return;
    await _store.deleteById(id);
    if (!mounted) return;
    setState(() => _messages = _messages.where((m) => m.id != id).toList());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: const Duration(seconds: 4),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus semua SMS?'),
        content: const Text(
          'Semua SMS di aplikasi ini dihapus. Inbox HP tidak ikut terhapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !_storeReady) return;
    await _store.clearAll();
    if (!mounted) return;
    setState(() => _messages.clear());
  }

  List<SmsEntry> get _visible {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _messages;
    return _messages
        .where(
          (entry) =>
              entry.address.toLowerCase().contains(query) ||
              entry.body.toLowerCase().contains(query),
        )
        .toList();
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
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox SMS'),
        actions: [
          IconButton(
            onPressed: _storeReady ? _openSenderSettings : null,
            icon: const Icon(Icons.tune),
            tooltip: 'Pengaturan',
          ),
          IconButton(
            onPressed: _messages.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Bersihkan semua',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _StatusCard(
              granted: _granted,
              canRequest: _canRequest,
              status: _status,
              count: _messages.length,
              filterLabel: _allowedSenders.isEmpty
                  ? 'Semua nomor'
                  : '${_allowedSenders.length} nomor',
              pending: _pendingCount,
              syncing: _syncing,
              forwarding: _forwarding,
              backendReady: _backendUrl.trim().isNotEmpty,
              onRequest: _requestPermission,
              onOpenSettings: _openSettings,
            ),
          ),
          if (_messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Cari nomor atau isi SMS',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? _EmptyInbox(filtered: _query.trim().isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = visible[index];
                      return Dismissible(
                        key: ValueKey<int>(entry.id ?? entry.timestamp),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.delete, color: scheme.onErrorContainer),
                        ),
                        onDismissed: (_) => _deleteEntry(entry),
                        child: _SmsTile(
                          entry: entry,
                          time: _formatTimestamp(entry.timestamp),
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.granted,
    required this.canRequest,
    required this.status,
    required this.count,
    required this.filterLabel,
    required this.pending,
    required this.syncing,
    required this.forwarding,
    required this.backendReady,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final bool granted;
  final bool canRequest;
  final String status;
  final int count;
  final String filterLabel;
  final int pending;
  final bool syncing;
  final bool forwarding;
  final bool backendReady;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = syncing || forwarding;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  granted ? Icons.check_circle : Icons.sms_outlined,
                  color: granted ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(status, style: Theme.of(context).textTheme.titleSmall),
                ),
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(icon: Icons.inbox_outlined, label: '$count tersimpan'),
                _Chip(icon: Icons.filter_alt_outlined, label: filterLabel),
                _Chip(
                  icon: backendReady ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  label: backendReady ? 'Backend siap' : 'Backend kosong',
                ),
                if (pending > 0)
                  _Chip(icon: Icons.schedule, label: '$pending antre'),
              ],
            ),
            if (!granted) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: canRequest ? onRequest : null,
                    icon: const Icon(Icons.sms),
                    label: const Text('Minta Izin SMS'),
                  ),
                  if (!canRequest)
                    OutlinedButton.icon(
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Buka pengaturan'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _SmsTile extends StatelessWidget {
  const _SmsTile({required this.entry, required this.time});

  final SmsEntry entry;
  final String time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sent = entry.forwarded;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.address.isEmpty ? 'Nomor tidak diketahui' : entry.address,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Icon(
                  sent ? Icons.cloud_done : Icons.cloud_upload_outlined,
                  size: 16,
                  color: sent ? scheme.primary : scheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(entry.body),
            const SizedBox(height: 8),
            Text(
              time,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          filtered
              ? 'Tidak ada SMS yang cocok.'
              : 'Belum ada SMS masuk.\nGeser SMS ke kiri untuk menghapus.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
