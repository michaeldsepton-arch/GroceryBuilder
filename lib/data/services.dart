import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const repoOwner = 'michaeldsepton-arch';
const repoName = 'GroceryBuilder';
const catalogUrl =
    'https://github.com/$repoOwner/$repoName/releases/download/catalog/catalog.json.gz';
const _latestReleaseApi =
    'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

Map<String, dynamic> _decodeCatalog(List<int> bytes) =>
    jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;

class CatalogService {
  /// Downloads the latest scraped catalog. Returns null on failure.
  static Future<Map<String, dynamic>?> download() async {
    final res = await http.get(Uri.parse(catalogUrl));
    if (res.statusCode != 200) return null;
    return compute(_decodeCatalog, res.bodyBytes);
  }
}

class UpdateInfo {
  UpdateInfo(this.build, this.version, this.notes, this.apkUrl, this.size);
  final int build;
  final String version;
  final String notes;
  final String apkUrl;
  final int size;
}

/// In-app updates: checks the newest GitHub Release, downloads the APK and
/// hands it to Android's installer. The APK is always signed with the same
/// key and application id, so Android updates in place and keeps all data.
class UpdateService {
  static Future<int> currentBuild() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  static Future<String> currentVersion() async {
    final i = await PackageInfo.fromPlatform();
    return '${i.version} (${i.buildNumber})';
  }

  /// Returns info on a newer release, or null when up to date.
  static Future<UpdateInfo?> check() async {
    final res = await http.get(Uri.parse(_latestReleaseApi),
        headers: {'Accept': 'application/vnd.github+json'});
    if (res.statusCode != 200) {
      throw Exception('GitHub returned ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String? ?? '');
    final build = int.tryParse(tag.split('.').last) ?? 0;
    if (build <= await currentBuild()) return null;
    final assets = (j['assets'] as List).cast<Map<String, dynamic>>();
    final apk = assets.firstWhere(
        (a) => (a['name'] as String).endsWith('.apk'),
        orElse: () => {});
    if (apk.isEmpty) return null;
    return UpdateInfo(build, tag.replaceFirst('v', ''), (j['body'] as String?) ?? '',
        apk['browser_download_url'] as String, (apk['size'] as num?)?.toInt() ?? 0);
  }

  static Future<void> downloadAndInstall(
      UpdateInfo info, void Function(double) onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/budget-basket-${info.build}.apk');
    final req = http.Request('GET', Uri.parse(info.apkUrl));
    final res = await req.send();
    if (res.statusCode != 200) throw Exception('Download failed (${res.statusCode})');
    final total = res.contentLength ?? info.size;
    var got = 0;
    final sink = file.openWrite();
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got / total);
    }
    await sink.close();
    final r = await OpenFilex.open(file.path,
        type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) {
      throw Exception(r.message);
    }
  }
}
