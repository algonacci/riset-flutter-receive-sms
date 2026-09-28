import 'package:flutter/material.dart';

import '../data/sms_store.dart';
import '../models/allowed_sender.dart';
import '../services/forward_service.dart';
import '../services/sender_allowlist.dart';

class SenderSettingsPage extends StatefulWidget {
  const SenderSettingsPage({
    super.key,
    required this.store,
    required this.forward,
  });

  final SmsStore store;
  final ForwardService forward;

  @override
  State<SenderSettingsPage> createState() => _SenderSettingsPageState();
}

class _SenderSettingsPageState extends State<SenderSettingsPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _gatewayController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  List<AllowedSender> _senders = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _urlController.dispose();
    _gatewayController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final senders = await widget.store.getAllowedSenders();
    final url = await widget.store.getSetting('backend_url');
    final gatewayId = await widget.store.getSetting('gateway_id');
    final apiKey = await widget.store.getSetting('api_key');
    if (!mounted) return;
    setState(() {
      _senders = senders;
      _urlController.text = url ?? '';
      _gatewayController.text = gatewayId ?? '';
      _apiKeyController.text = apiKey ?? '';
    });
  }

  Future<void> _add() async {
    final normalized = SenderAllowlist.normalize(_controller.text.trim());
    if (normalized.isEmpty) {
      setState(() => _error = 'Nomor tidak valid');
      return;
    }
    if (await widget.store.containsAllowedSender(normalized)) {
      setState(() => _error = 'Nomor sudah ada di daftar');
      return;
    }
    await widget.store.addAllowedSender(normalized);
    _controller.clear();
    if (!mounted) return;
    setState(() => _error = null);
    await _load();
  }

  Future<void> _remove(AllowedSender sender) async {
    final id = sender.id;
    if (id == null) return;
    await widget.store.removeAllowedSender(id);
    await _load();
  }

  Future<void> _saveBackend() async {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL tidak valid — contoh: http://192.168.1.5:5000'),
          ),
        );
        return;
      }
      if (uri.host == '0.0.0.0') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '0.0.0.0 bukan alamat tujuan dari HP — pakai IP laptop '
              'di Wi-Fi yang sama, mis. http://192.168.1.5:5000',
            ),
          ),
        );
        return;
      }
    }
    await widget.store.setSetting(
      'backend_url',
      url,
    );
    await widget.store.setSetting(
      'gateway_id',
      _gatewayController.text.trim(),
    );
    await widget.store.setSetting(
      'api_key',
      _apiKeyController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan backend disimpan')),
    );
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    final ok = await widget.forward.testConnection(
      url,
      apiKey: _apiKeyController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Terhubung ke backend ✓'
              : 'Gagal terhubung. Cek URL dan pastikan backend jalan.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Backend', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Pakai IP laptop di Wi-Fi yang sama, bukan 0.0.0.0.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL backend',
              hintText: 'http://192.168.1.5:5000',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gatewayController,
            decoration: const InputDecoration(
              labelText: 'Gateway ID',
              hintText: 'hp-01',
              prefixIcon: Icon(Icons.phone_android),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'API key',
              hintText: 'kosongkan kalau backend tanpa kunci',
              prefixIcon: Icon(Icons.key_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _saveBackend,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Tes koneksi'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Nomor diizinkan',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _senders.isEmpty
                ? 'Daftar kosong: semua SMS disimpan dan dikirim.'
                : 'Hanya ${_senders.length} nomor ini yang disimpan dan dikirim.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Nomor HP',
                    hintText: '0812 atau 62812',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _add,
                child: const Text('Tambah'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_senders.isEmpty)
            Card(
              elevation: 0,
              color: scheme.surfaceContainerLow,
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Belum ada filter nomor'),
              ),
            )
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _senders.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.secondaryContainer,
                        child: const Icon(Icons.phone, size: 18),
                      ),
                      title: Text(_senders[i].number),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Hapus',
                        onPressed: () => _remove(_senders[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
