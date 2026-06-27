import 'dart:io';
import 'dart:typed_data';

class DemoInfo {
  final String? mapName;
  final String? serverName;
  final String? clientName;
  final String? demoVersionName;
  final int? networkProtocol;
  final int? buildNum;
  final double? playbackTime;
  final int? playbackTicks;
  final int fileSize;

  const DemoInfo({
    this.mapName,
    this.serverName,
    this.clientName,
    this.demoVersionName,
    this.networkProtocol,
    this.buildNum,
    this.playbackTime,
    this.playbackTicks,
    required this.fileSize,
  });

  String get mapDisplay {
    if (mapName == null) return 'Unknown';
    return mapName!.replaceFirst('de_', '').replaceFirst('cs_', '');
  }

  String get durationDisplay {
    if (playbackTime == null) return '--:--';
    final total = playbackTime!.round();
    final mins = total ~/ 60;
    final secs = total % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String get sizeDisplay {
    if (fileSize >= 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  String get tickrateDisplay {
    if (playbackTime == null || playbackTicks == null || playbackTime! <= 0) {
      return '--';
    }
    return '${(playbackTicks! / playbackTime!).round()} tick';
  }
}

class DemoParser {
  static Future<DemoInfo?> parse(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final fileSize = await file.length();
    final raf = await file.open(mode: FileMode.read);

    try {
      final header = Uint8List(2048);
      final headerRead = await raf.readInto(header);
      if (headerRead < 20) return null;

      if (String.fromCharCodes(header.sublist(0, 7)) != 'PBDEMS2') return null;

      final bd = ByteData.sublistView(header);
      final fileinfoOffset = bd.getInt32(8, Endian.little);

      // First message starts at byte 16: varint(cmd), varint(tick), varint(size), data
      var pos = 16;
      final cmd = _readVarint(header, pos);
      pos = cmd.end;
      final tick = _readVarint(header, pos);
      pos = tick.end;
      final msgSize = _readVarint(header, pos);
      pos = msgSize.end;

      String? mapName, serverName, clientName, versionName;
      int? networkProtocol, buildNum;

      if (cmd.value == 1 && pos + msgSize.value <= headerRead) {
        final data = header.sublist(pos, pos + msgSize.value);
        var dp = 0;
        while (dp < data.length) {
          final tag = data[dp++];
          final fieldNum = tag >> 3;
          final wireType = tag & 7;

          if (wireType == 0) {
            final v = _readVarint(data, dp);
            dp = v.end;
            if (fieldNum == 2) networkProtocol = v.value;
            if (fieldNum == 13) buildNum = v.value;
          } else if (wireType == 2) {
            final len = _readVarint(data, dp);
            dp = len.end;
            if (dp + len.value > data.length) break;
            final str = String.fromCharCodes(
                data.sublist(dp, dp + len.value));
            dp += len.value;
            if (fieldNum == 3) serverName = str;
            if (fieldNum == 4) clientName = str;
            if (fieldNum == 5) mapName = str;
            if (fieldNum == 11) versionName = str;
          } else if (wireType == 5) {
            dp += 4;
          } else if (wireType == 1) {
            dp += 8;
          } else {
            break;
          }
        }
      }

      double? playbackTime;
      int? playbackTicks;

      if (fileinfoOffset > 0 && fileinfoOffset < fileSize) {
        await raf.setPosition(fileinfoOffset);
        final info = Uint8List(512);
        final infoRead = await raf.readInto(info);
        if (infoRead > 10) {
          var ip = 0;
          final ic = _readVarint(info, ip);
          ip = ic.end;
          final it = _readVarint(info, ip);
          ip = it.end;
          final is_ = _readVarint(info, ip);
          ip = is_.end;

          if (ic.value == 2 && ip + is_.value <= infoRead) {
            final end = ip + is_.value;
            while (ip < end) {
              if (ip >= info.length) break;
              final tag = info[ip++];
              final fn = tag >> 3;
              final wt = tag & 7;
              if (wt == 5 && fn == 1) {
                if (ip + 4 <= info.length) {
                  playbackTime = ByteData.sublistView(info)
                      .getFloat32(ip, Endian.little);
                }
                ip += 4;
              } else if (wt == 0) {
                final v = _readVarint(info, ip);
                ip = v.end;
                if (fn == 2) playbackTicks = v.value;
              } else if (wt == 2) {
                final len = _readVarint(info, ip);
                ip = len.end + len.value;
              } else if (wt == 1) {
                ip += 8;
              } else {
                break;
              }
            }
          }
        }
      }

      return DemoInfo(
        mapName: mapName,
        serverName: serverName,
        clientName: clientName,
        demoVersionName: versionName,
        networkProtocol: networkProtocol,
        buildNum: buildNum,
        playbackTime: playbackTime,
        playbackTicks: playbackTicks,
        fileSize: fileSize,
      );
    } catch (_) {
      return null;
    } finally {
      await raf.close();
    }
  }

  static _Varint _readVarint(Uint8List data, int pos) {
    var result = 0;
    var shift = 0;
    while (pos < data.length) {
      final b = data[pos];
      result |= (b & 0x7f) << shift;
      pos++;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return _Varint(result, pos);
  }
}

class _Varint {
  final int value;
  final int end;
  const _Varint(this.value, this.end);
}
