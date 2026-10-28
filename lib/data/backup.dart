import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'repo.dart';

/// Backs up personal data (custom items, notes, trips, budget) plus photos
/// into one zip so a phone swap never loses your own list.
class Backup {
  static Future<File> export(Repo repo, String photoDir) async {
    final ar = Archive();
    final json = utf8.encode(repo.encode(await repo.exportData()));
    ar.addFile(ArchiveFile('data.json', json.length, json));
    final dir = Directory(photoDir);
    if (await dir.exists()) {
      for (final f in dir.listSync().whereType<File>()) {
        final bytes = await f.readAsBytes();
        ar.addFile(ArchiveFile('photos/${p.basename(f.path)}', bytes.length, bytes));
      }
    }
    final out = ZipEncoder().encode(ar);
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File(p.join(tmp.path, 'budget-basket-backup-$stamp.zip'));
    await file.writeAsBytes(out);
    return file;
  }

  static Future<void> restore(Repo repo, String photoDir, File zip) async {
    final ar = ZipDecoder().decodeBytes(await zip.readAsBytes());
    for (final f in ar.files) {
      if (!f.isFile) continue;
      final bytes = f.content as List<int>;
      if (f.name == 'data.json') {
        await repo.importData(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
      } else if (f.name.startsWith('photos/')) {
        await File(p.join(photoDir, p.basename(f.name))).writeAsBytes(bytes);
      }
    }
  }
}
