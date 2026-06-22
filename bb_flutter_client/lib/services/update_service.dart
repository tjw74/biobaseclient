import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const String _updateFeedUrl = 'https://cs2.clarionlab.dev/client/latest.yml';
const String _downloadBaseUrl = 'https://cs2.clarionlab.dev/client/';
const String currentVersion = '0.2.1';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final bool available;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.available,
  });
}

class UpdateService {
  Future<UpdateInfo> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(_updateFeedUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return UpdateInfo(
            version: currentVersion, downloadUrl: '', available: false);
      }

      final body = response.body;
      final versionMatch = RegExp(r'version:\s*(.+)').firstMatch(body);
      final pathMatch = RegExp(r'path:\s*(.+)').firstMatch(body);

      if (versionMatch == null) {
        return UpdateInfo(
            version: currentVersion, downloadUrl: '', available: false);
      }

      final remoteVersion = versionMatch.group(1)!.trim();
      final fileName = pathMatch?.group(1)?.trim() ?? '';
      final downloadUrl =
          fileName.isNotEmpty ? '$_downloadBaseUrl$fileName' : '';

      return UpdateInfo(
        version: remoteVersion,
        downloadUrl: downloadUrl,
        available: _isNewer(remoteVersion, currentVersion),
      );
    } catch (_) {
      return UpdateInfo(
          version: currentVersion, downloadUrl: '', available: false);
    }
  }

  Future<String?> downloadAndInstall(String url) async {
    if (!Platform.isWindows) return 'Auto-update is Windows-only';

    try {
      final tempDir = Directory.systemTemp;
      final installerPath =
          p.join(tempDir.path, 'biobase-client-setup.exe');

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return 'Download failed';

      final file = File(installerPath);
      await file.writeAsBytes(response.bodyBytes);

      await Process.start(installerPath, ['/SILENT'], mode: ProcessStartMode.detached);
      exit(0);
    } catch (e) {
      return e.toString();
    }
  }

  bool _isNewer(String remote, String local) {
    final rParts = remote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final lParts = local.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < rParts.length && i < lParts.length; i++) {
      if (rParts[i] > lParts[i]) return true;
      if (rParts[i] < lParts[i]) return false;
    }
    return rParts.length > lParts.length;
  }
}
