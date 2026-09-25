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
const String kAppVersion = '1.5.0';

/// Your GitHub repo, as `owner/name` — the two parts of the URL when you
/// visit your repo, e.g. https://github.com/OWNER/REPO.
/// Confirmed against the repo's own Releases page: the username is
/// "Sam-st0p" with a ZERO, not the letter O — the earlier 'Sam-stOp' guess
/// (capital O) pointed at a repo that doesn't exist, which is why every
/// check silently found nothing.
const String kGithubOwner = 'Sam-st0p';
const String kGithubRepo = 'mobilebooking';

class UpdateInfo {
  final String version;
  final String? releaseNotes;
  final String downloadUrl;
  const UpdateInfo({required this.version, required this.downloadUrl, this.releaseNotes});
}

/// Result of a version check. Exactly one of three things happened:
///  - [update] is set        -> a newer release exists
///  - [update] is null and
///    [error] is null        -> checked fine, you're already up to date
///  - [error] is set         -> the check itself failed (wrong repo name,
///                              no internet, GitHub rate limit, ...) — this
///                              is NOT the same as "up to date", and previously
///                              the app couldn't tell the two apart.
class UpdateCheckResult {
  final UpdateInfo? update;
  final String? error;
  const UpdateCheckResult({this.update, this.error});
  bool get hasUpdate => update != null;
}

/// Same check as [checkForUpdate], but reports WHY it found nothing — use this
/// for a manual "Check for updates" button, where a wrong-repo-name or
/// network failure should be visible rather than silently reported as
/// "you're on the latest version".
Future<UpdateCheckResult> checkForUpdateVerbose() async {
  try {
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) {
      return const UpdateCheckResult(
        error: 'Could not find that GitHub repo or it has no releases yet. '
            'Check kGithubOwner/kGithubRepo in update_checker.dart.',
      );
    }
    if (response.statusCode == 403) {
      return const UpdateCheckResult(error: 'GitHub is rate-limiting update checks right now. Try again later.');
    }
    if (response.statusCode != 200) {
      return UpdateCheckResult(error: 'GitHub returned an unexpected error (${response.statusCode}).');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (body['tag_name'] as String?) ?? '';
    final latestVersion = tag.replaceFirst(RegExp(r'^[vV]'), '');
    if (!_isNewer(latestVersion, kAppVersion)) {
      return const UpdateCheckResult(); // genuinely up to date — no error
    }

    final assets = (body['assets'] as List?) ?? const [];
    String? apkUrl;
    for (final asset in assets) {
      final name = (asset as Map<String, dynamic>)['name'] as String?;
      if (name != null && name.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        break;
      }
    }
    // No .apk attached to the release (maybe it's still uploading, or was
    // forgotten) — send the person to the Releases page instead of failing.
    apkUrl ??= (body['html_url'] as String?) ??
        'https://github.com/$kGithubOwner/$kGithubRepo/releases/latest';

    return UpdateCheckResult(
      update: UpdateInfo(
        version: latestVersion,
        downloadUrl: apkUrl,
        releaseNotes: (body['body'] as String?)?.trim().isEmpty ?? true ? null : (body['body'] as String).trim(),
      ),
    );
  } catch (e) {
    return UpdateCheckResult(error: 'Could not reach GitHub: $e');
  }
}

/// Returns update info if GitHub's latest release is newer than
/// [kAppVersion], or null if not — including when the check itself fails.
/// This must never throw, since it runs silently on every app start; use
/// [checkForUpdateVerbose] instead wherever a failure should be visible.
Future<UpdateInfo?> checkForUpdate() async => (await checkForUpdateVerbose()).update;

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