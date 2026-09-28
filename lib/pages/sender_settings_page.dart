import 'package:flutter/material.dart';

import '../data/sms_store.dart';
import '../models/allowed_sender.dart';
import '../services/sender_allowlist.dart';

class SenderSettingsPage extends StatefulWidget {
  const SenderSettingsPage({super.key, required this.store});

  final SmsStore store;

  @override
  State<SenderSettingsPage> createState() => _SenderSettingsPageState();
}

class _SenderSettingsPageState extends State<SenderSettingsPage> {
  final TextEditingController _controller = TextEditingController();
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
    super.dispose();
  }

  Future<void> _load() async {
    final senders = await widget.store.getAllowedSenders();
    if (!mounted) return;
    setState(() => _senders = senders);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Nomor Diizinkan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Cuma SMS dari nomor di daftar ini yang diproses (disimpan '
            'dan diteruskan ke backend).\n\n'
            'Daftar kosong = semua nomor dibaca.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Nomor HP',
                    hintText: '0812xxxx / 62812xxxx',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _add,
                child: const Text('Tambah'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_senders.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Belum ada nomor → semua SMS dibaca.'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final sender in _senders)
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: Text(sender.number),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Hapus',
                        onPressed: () => _remove(sender),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
