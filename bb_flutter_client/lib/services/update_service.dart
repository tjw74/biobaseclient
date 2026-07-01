import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const String _downloadBaseUrl =
    'https://github.com/tjw74/biobaseclient/releases/download/flutter-latest/';
const String currentVersion = '0.11.31';

String get _updateFeedUrl {
  if (Platform.isMacOS) return '${_downloadBaseUrl}latest-mac.yml';
  return '${_downloadBaseUrl}latest.yml';
}

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
          version: currentVersion,
          downloadUrl: '',
          available: false,
        );
      }

      final body = response.body;
      final versionMatch = RegExp(r'version:\s*(.+)').firstMatch(body);
      final pathMatch = RegExp(r'path:\s*(.+)').firstMatch(body);

      if (versionMatch == null) {
        return UpdateInfo(
          version: currentVersion,
          downloadUrl: '',
          available: false,
        );
      }

      final remoteVersion = versionMatch.group(1)!.trim();
      final fileName = pathMatch?.group(1)?.trim() ?? '';
      final downloadUrl = fileName.isNotEmpty
          ? '$_downloadBaseUrl$fileName'
          : '';

      return UpdateInfo(
        version: remoteVersion,
        downloadUrl: downloadUrl,
        available: _isNewer(remoteVersion, currentVersion),
      );
    } catch (_) {
      return UpdateInfo(
        version: currentVersion,
        downloadUrl: '',
        available: false,
      );
    }
  }

  Future<String?> downloadAndInstall(String url) async {
    try {
      if (Platform.isWindows) {
        return _installWindows(url);
      } else if (Platform.isMacOS) {
        return _installMac(url);
      }
      return 'Auto-update not supported on this platform';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> _installWindows(String url) async {
    final tempDir = Directory.systemTemp;
    final installerPath = p.join(tempDir.path, 'biobase-client-setup.exe');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return 'Download failed';

    final file = File(installerPath);
    await file.writeAsBytes(response.bodyBytes);

    final script = p.join(tempDir.path, 'biobase_update.cmd');
    await File(script).writeAsString(
      '@echo off\r\n'
      '"$installerPath" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART\r\n'
      'del "%~f0"\r\n',
    );

    await Process.start('cmd', ['/c', script], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<String?> _installMac(String url) async {
    final tempDir = Directory.systemTemp;
    final zipPath = p.join(tempDir.path, 'biobase-client-mac.zip');
    final extractDir = p.join(tempDir.path, 'biobase-update');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return 'Download failed';

    final file = File(zipPath);
    await file.writeAsBytes(response.bodyBytes);

    final extract = Directory(extractDir);
    if (extract.existsSync()) extract.deleteSync(recursive: true);
    extract.createSync();

    final appPath = Platform.resolvedExecutable;
    final appBundle = File(appPath).parent.parent.parent.path;

    await Process.run('unzip', ['-o', zipPath, '-d', extractDir]);

    final newApp = p.join(extractDir, 'biobase_client.app');
    if (!Directory(newApp).existsSync()) return 'Extracted app not found';

    await Process.run('rm', ['-rf', appBundle]);
    await Process.run('mv', [newApp, appBundle]);

    await Process.start('open', [
      '-n',
      appBundle,
    ], mode: ProcessStartMode.detached);
    exit(0);
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
