import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../data/services.dart';
import '../models/units.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String version = '';
  double? progress;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    UpdateService.currentVersion().then((v) => mounted ? setState(() => version = v) : null);
  }

  void _msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _check() async {
    final s = context.read<AppState>();
    setState(() => checking = true);
    try {
      await s.checkForUpdate();
      if (s.update == null) _msg('You have the latest version');
    } catch (e) {
      _msg('Could not check for updates: $e');
    }
    if (mounted) setState(() => checking = false);
  }

  Future<void> _install() async {
    final u = context.read<AppState>().update!;
    setState(() => progress = 0);
    try {
      await UpdateService.downloadAndInstall(u, (p) => setState(() => progress = p));
    } catch (e) {
      _msg('Update failed: $e');
    }
    if (mounted) setState(() => progress = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final u = s.update;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('More', style: serif(28)),
        const SizedBox(height: 12),
        if (u != null)
          Card(
            color: BB.green100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Update available · v${u.version}', style: serif(18)),
                if (u.notes.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(u.notes.trim(), maxLines: 6, overflow: TextOverflow.ellipsis),
                  ),
                const SizedBox(height: 10),
                if (progress != null)
                  LinearProgressIndicator(value: progress)
                else
                  FilledButton.icon(
                      onPressed: _install,
                      icon: const Icon(Icons.system_update),
                      label: Text('Download & install'
                          '${u.size > 0 ? ' (${(u.size / 1048576).toStringAsFixed(1)} MB)' : ''}')),
                const SizedBox(height: 4),
                const Text('Your items, cart and settings are kept.',
                    style: TextStyle(color: BB.muted, fontSize: 12)),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: SwitchListTile(
            secondary: const Icon(Icons.verified_outlined, color: BB.green700),
            title: const Text('Halal meat only', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text(
                'Hides supermarket meat that is not halal-certified. Pork, alcohol and gelatin are always hidden.'),
            value: s.halalMeatOnly,
            onChanged: s.setHalalMeatOnly,
          ),
        ),
        _Tile(
          icon: Icons.savings_outlined,
          title: 'Weekly budget',
          subtitle: '${money(s.weekBudget)} · tap to change (default \$100)',
          onTap: () => editBudget(context),
        ),
        _Tile(
          icon: Icons.sync,
          title: 'Refresh prices',
          subtitle: s.syncing
              ? 'Downloading…'
              : s.catalogCount == 0
                  ? (s.syncError ?? 'No catalog yet')
                  : '${s.catalogCount} store items · updated ${_fmt(s.catalogStamp)}',
          trailing: s.syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: s.syncing
              ? null
              : () async {
                  await s.syncCatalog();
                  if (mounted) _msg(s.syncError ?? 'Prices refreshed');
                },
        ),
        _Tile(
          icon: Icons.system_update_alt,
          title: 'Check for app updates',
          subtitle: 'Version $version',
          trailing: checking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: checking ? null : _check,
        ),
        const Divider(height: 32),
        _Tile(
          icon: Icons.ios_share,
          title: 'Back up my data',
          subtitle: 'Custom items, photos, aisles, budget & trips',
          onTap: () async {
            final f = await Backup.export(s.repo, s.photoDir);
            await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Budget Basket backup'));
          },
        ),
        _Tile(
          icon: Icons.restore,
          title: 'Restore from backup',
          subtitle: 'Pick a backup .zip',
          onTap: () async {
            final r = await FilePicker.pickFiles(type: FileType.any);
            final path = r.isEmpty ? null : r.first.path;
            if (path == null) return;
            try {
              await Backup.restore(s.repo, s.photoDir, File(path));
              await s.reload();
              _msg('Backup restored');
            } catch (e) {
              _msg('Could not restore: $e');
            }
          },
        ),
        const SizedBox(height: 16),
        Center(
          child: Text('Budget Basket · Red Deer, AB\nPrices in CAD · GST 5% on taxable items',
              textAlign: TextAlign.center,
              style: const TextStyle(color: BB.muted, fontSize: 12)),
        ),
      ]),
    );
  }

  String _fmt(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return 'unknown';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, this.onTap, this.trailing});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: BB.green700),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
