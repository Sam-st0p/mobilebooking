// lib/services/update_checker.dart
//
// Checks GitHub Releases for a newer APK than the one currently installed,
// for an app that is side-loaded (not on the Play Store) and distributed as
// an APK attached to a GitHub Release.
//
// No new native dependency is used on purpose: this only needs `http`
// (already a dependency) plus a version string YOU keep up to date — see
// kAppVersion below. Using a package like package_info_plus would read the
// version automatically, but this project already hit real trouble from a
// plugin's API changing between major versions (see document_upload_tile.dart's
// file_picker notes), so a plain constant is the safer choice for something
// this simple.

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Bump this with every release you publish, to match the version you set
/// in `pubspec.yaml`'s `version:` line (the part before the `+`). If you
/// forget to bump it, the app will just keep "finding" the same update.
const String kAppVersion = '1.3.0';

/// Your GitHub repo, as `owner/name` — the two parts of the URL when you
/// visit your repo, e.g. https://github.com/OWNER/REPO.
/// TODO: double-check these match your actual repo before shipping —
/// they were inferred from a screenshot, not confirmed with you directly.
const String kGithubOwner = 'Sam-stOp';
const String kGithubRepo = 'mobilebooking';

class UpdateInfo {
  final String version;
  final String? releaseNotes;
  final String downloadUrl;
  const UpdateInfo({required this.version, required this.downloadUrl, this.releaseNotes});
}

/// Returns update info if GitHub's latest release is newer than
/// [kAppVersion], or null if not (including on any network/parsing failure —
/// this must never throw, since it runs silently on every app start).
Future<UpdateInfo?> checkForUpdate() async {
  try {
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null; // no releases yet, rate-limited, repo renamed, ...

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (body['tag_name'] as String?) ?? '';
    final latestVersion = tag.replaceFirst(RegExp(r'^[vV]'), '');
    if (!_isNewer(latestVersion, kAppVersion)) return null;

    final assets = (body['assets'] as List?) ?? const [];
    String? apkUrl;
    for (final asset in assets) {
      final name = (asset as Map<String, dynamic>)['name'] as String?;
      if (name != null && name.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        break;
      }
    }
    // No .apk attached to the release (maybe it's still uploading) — send
    // the person to the Releases page instead of failing silently.
    apkUrl ??= (body['html_url'] as String?) ??
        'https://github.com/$kGithubOwner/$kGithubRepo/releases/latest';

    return UpdateInfo(
      version: latestVersion,
      downloadUrl: apkUrl,
      releaseNotes: (body['body'] as String?)?.trim().isEmpty ?? true ? null : (body['body'] as String).trim(),
    );
  } catch (_) {
    return null; // offline, DNS failure, malformed JSON, etc. — fail quietly
  }
}

/// True if [a] is a higher version than [b] ("1.2.0" > "1.10.0" is handled
/// correctly by comparing components as integers, not as strings).
/// Anything after a `-` or `+` (pre-release/build metadata) is ignored.
bool _isNewer(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();

  final pa = parts(a);
  final pb = parts(b);
  final length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va > vb;
  }
  return false;
}