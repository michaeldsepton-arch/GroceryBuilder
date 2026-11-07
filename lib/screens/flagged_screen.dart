import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// Items flagged as not needed. They are hidden on this phone only; the list can be sent
/// so similar items get removed from the shared price list. Undo brings an item back.
class FlaggedScreen extends StatefulWidget {
  const FlaggedScreen({super.key});
  @override
  State<FlaggedScreen> createState() => _FlaggedScreenState();
}

class _FlaggedScreenState extends State<FlaggedScreen> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.read<AppState>().repo.flags();
    if (mounted) setState(() => rows = r);
  }

  Future<void> _send() async {
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final f = File('${Directory.systemTemp.path}/budget-basket-flagged-$stamp.json');
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert({'flagged': rows}));
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Budget Basket flagged items'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Flagged items')),
      body: rows.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                  'Nothing flagged. Open an item and tap "Not needed here? Flag it" to hide it and add it to this list.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BB.muted)),
            ))
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  Expanded(
                      child: Text('${rows.length} flagged. Send the list so similar items can be removed for everyone.',
                          style: const TextStyle(color: BB.muted, fontSize: 13))),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                      onPressed: _send, icon: const Icon(Icons.ios_share, size: 18), label: const Text('Send')),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final id = '${r['item_id']}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r['name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(s.storeById('${r['store_id']}').name),
                      trailing: TextButton(
                        onPressed: () async {
                          await s.unflagItem(id);
                          _load();
                        },
                        child: const Text('Undo'),
                      ),
                    );
                  },
                ),
              ),
            ]),
    );
  }
}
