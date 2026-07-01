import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const int cs2DemoTickrate = 64;
const int defaultRenderFps = 60;
const int defaultRenderWidth = 1920;
const int defaultRenderHeight = 1080;
const int defaultPreviewSeconds = 60;
const int safeDemoStartTick = 96;

class RenderJob {
  final String jobId;
  final String demoPath;
  final int startTick;
  final int endTick;
  final String outputDir;
  final int width;
  final int height;
  final int fps;
  final String recordingSystem;
  final String outputType;
  final String encoder;

  const RenderJob({
    required this.jobId,
    required this.demoPath,
    required this.startTick,
    required this.endTick,
    required this.outputDir,
    this.width = defaultRenderWidth,
    this.height = defaultRenderHeight,
    this.fps = defaultRenderFps,
    this.recordingSystem = 'CS',
    this.outputType = 'images-and-video',
    this.encoder = 'FFmpeg',
  });

  List<String> validate() {
    final issues = <String>[];
    if (demoPath.trim().isEmpty) issues.add('Demo path is empty.');
    if (!demoPath.toLowerCase().endsWith('.dem')) {
      issues.add('Demo path must end with .dem.');
    }
    if (startTick < 0) issues.add('Start tick must be >= 0.');
    if (endTick <= startTick) issues.add('End tick must be greater than start tick.');
    if (fps <= 0) issues.add('Frame rate must be greater than zero.');
    if (width <= 0 || height <= 0) issues.add('Render dimensions must be greater than zero.');
    if (outputDir.trim().isEmpty) issues.add('Output directory is empty.');
    return issues;
  }
}

class RenderJobResult {
  final bool success;
  final String message;
  final String? outputPath;
  final int? exitCode;
  final List<String> diagnostics;

  const RenderJobResult({
    required this.success,
    required this.message,
    required this.diagnostics,
    this.outputPath,
    this.exitCode,
  });
}

class CsdmRenderService {
  bool _running = false;

  bool get running => _running;

  static RenderJob createPreviewJob({
    required String demoPath,
    int? playbackTicks,
    String? outputRoot,
  }) {
    final jobId = buildJobId();
    final startTick = choosePreviewStartTick(playbackTicks);
    final endTick = choosePreviewEndTick(startTick, playbackTicks);
    final root = outputRoot ?? defaultRenderRoot();
    return RenderJob(
      jobId: jobId,
      demoPath: demoPath,
      startTick: startTick,
      endTick: endTick,
      outputDir: p.join(root, jobId),
    );
  }

  static String buildJobId({DateTime? now}) {
    final timestamp = (now ?? DateTime.now().toUtc())
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .padRight(14, '0')
        .substring(0, 14);
    return 'job_$timestamp';
  }

  static int choosePreviewStartTick(int? playbackTicks) {
    if (playbackTicks == null || playbackTicks <= safeDemoStartTick + cs2DemoTickrate) {
      return 0;
    }
    return safeDemoStartTick;
  }

  static int choosePreviewEndTick(int startTick, int? playbackTicks) {
    final desiredEnd = startTick + (defaultPreviewSeconds * cs2DemoTickrate);
    if (playbackTicks == null || playbackTicks <= 0) return desiredEnd;
    if (playbackTicks <= startTick) return startTick + cs2DemoTickrate;
    return desiredEnd < playbackTicks ? desiredEnd : playbackTicks;
  }

  static String defaultRenderRoot() {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return p.join(base, 'BioBase', 'renders');
  }

  static List<String> buildAnalyzeArgs(RenderJob job) => [
        'analyze',
        job.demoPath,
        '--force',
      ];

  static List<String> buildVideoArgs(RenderJob job) => [
        'video',
        job.demoPath,
        '${job.startTick}',
        '${job.endTick}',
        '--output',
        job.outputDir,
        '--framerate',
        '${job.fps}',
        '--width',
        '${job.width}',
        '--height',
        '${job.height}',
        '--recording-system',
        job.recordingSystem,
        '--recording-output',
        job.outputType,
        '--encoder-software',
        job.encoder,
        '--close-game-after-recording',
      ];

  static Future<String?> findCsdmExecutable({
    Map<String, String>? environment,
    List<String>? extraCandidates,
  }) async {
    final env = environment ?? Platform.environment;
    final candidates = <String>[
      if ((env['BIOBASE_CSDM_PATH'] ?? '').trim().isNotEmpty)
        env['BIOBASE_CSDM_PATH']!.trim(),
      ...?extraCandidates,
      if (Platform.isWindows) ...[
        p.join(env['LOCALAPPDATA'] ?? '', 'Programs', 'CS Demo Manager', 'csdm.exe'),
        p.join(env['LOCALAPPDATA'] ?? '', 'Programs', 'cs-demo-manager', 'csdm.exe'),
        p.join(env['ProgramFiles'] ?? r'C:\Program Files', 'CS Demo Manager', 'csdm.exe'),
        p.join(env['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)', 'CS Demo Manager', 'csdm.exe'),
      ],
    ];

    for (final candidate in candidates) {
      if (candidate.trim().isEmpty) continue;
      if (await File(candidate).exists()) return candidate;
    }

    final pathEnv = env['PATH'] ?? env['Path'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';
    final executableNames = Platform.isWindows
        ? ['csdm.exe', 'csdm.cmd', 'csdm.bat', 'csdm']
        : ['csdm'];
    for (final dir in pathEnv.split(separator)) {
      if (dir.trim().isEmpty) continue;
      for (final name in executableNames) {
        final candidate = p.join(dir.trim(), name);
        if (await File(candidate).exists()) return candidate;
      }
    }

    return null;
  }

  static String formatCommand(String executable, List<String> args) {
    return [executable, ...args].map(_quoteForDisplay).join(' ');
  }

  Future<RenderJobResult> render(
    RenderJob job, {
    void Function(String line)? onLog,
    String? csdmExecutable,
  }) async {
    final diagnostics = <String>[
      'Render job ${job.jobId}',
      'Demo: ${job.demoPath}',
      'Tick range: ${job.startTick} → ${job.endTick}',
      'Output: ${job.outputDir}',
      'Pipeline: csdm analyze → csdm video (${job.recordingSystem}/${job.encoder})',
    ];

    void log(String line) {
      diagnostics.add(line);
      onLog?.call(line);
    }

    if (_running) {
      return RenderJobResult(
        success: false,
        message: 'A BioBase render job is already running. Wait for it to finish before starting another one.',
        diagnostics: diagnostics,
      );
    }

    final validationIssues = job.validate();
    if (validationIssues.isNotEmpty) {
      return RenderJobResult(
        success: false,
        message: validationIssues.join(' '),
        diagnostics: [...diagnostics, ...validationIssues],
      );
    }

    final demoFile = File(job.demoPath);
    if (!await demoFile.exists()) {
      return RenderJobResult(
        success: false,
        message: 'Demo file does not exist: ${job.demoPath}',
        diagnostics: [...diagnostics, 'Demo file was not found on disk.'],
      );
    }

    final executable = csdmExecutable ?? await findCsdmExecutable();
    if (executable == null) {
      return RenderJobResult(
        success: false,
        message: 'CS Demo Manager CLI was not found. Install CS Demo Manager CLI, put `csdm` on PATH, or set BIOBASE_CSDM_PATH to csdm.exe.',
        diagnostics: [
          ...diagnostics,
          'CS Demo Manager CLI not found.',
          'Expected command: csdm analyze <demo> --force, then csdm video <demo> <startTick> <endTick> ...',
        ],
      );
    }

    _running = true;
    try {
      final outputDir = Directory(job.outputDir);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final analyzeArgs = buildAnalyzeArgs(job);
      log('Running analyze: ${formatCommand(executable, analyzeArgs)}');
      final analyzeCode = await _runProcess(executable, analyzeArgs, log);
      if (analyzeCode != 0) {
        return RenderJobResult(
          success: false,
          message: 'CS Demo Manager analyze failed with exit code $analyzeCode.',
          exitCode: analyzeCode,
          diagnostics: diagnostics,
        );
      }

      final videoArgs = buildVideoArgs(job);
      log('Running render: ${formatCommand(executable, videoArgs)}');
      final videoCode = await _runProcess(executable, videoArgs, log);
      if (videoCode != 0) {
        return RenderJobResult(
          success: false,
          message: 'CS Demo Manager render failed with exit code $videoCode.',
          exitCode: videoCode,
          diagnostics: diagnostics,
        );
      }

      final outputPath = await findBestOutputPath(job.outputDir);
      if (outputPath == null) {
        return RenderJobResult(
          success: false,
          message: 'CS Demo Manager finished, but BioBase did not find an output video in ${job.outputDir}.',
          diagnostics: [...diagnostics, 'No .mp4/.mkv/.avi output file found.'],
        );
      }

      return RenderJobResult(
        success: true,
        message: 'Render complete.',
        outputPath: outputPath,
        diagnostics: [...diagnostics, 'Render output: $outputPath'],
      );
    } catch (e) {
      return RenderJobResult(
        success: false,
        message: 'Render job failed: $e',
        diagnostics: [...diagnostics, 'Render exception: $e'],
      );
    } finally {
      _running = false;
    }
  }

  static Future<String?> findBestOutputPath(String outputDir) async {
    final dir = Directory(outputDir);
    if (!await dir.exists()) return null;

    final files = await dir
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    for (final ext in ['.mp4', '.mkv', '.avi']) {
      for (final file in files) {
        if (file.path.toLowerCase().endsWith(ext)) return file.path;
      }
    }
    for (final ext in ['.wav', '.tga']) {
      for (final file in files) {
        if (file.path.toLowerCase().endsWith(ext)) return file.path;
      }
    }
    return null;
  }

  Future<int> _runProcess(
    String executable,
    List<String> args,
    void Function(String line) log,
  ) async {
    final process = await Process.start(
      executable,
      args,
      mode: ProcessStartMode.normal,
      runInShell: Platform.isWindows,
    );

    final stdoutDone = _pipeLines(process.stdout, (line) => log('[csdm] $line'));
    final stderrDone = _pipeLines(process.stderr, (line) => log('[csdm:err] $line'));
    final code = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    log('csdm exited with code $code');
    return code;
  }

  Future<void> _pipeLines(
    Stream<List<int>> stream,
    void Function(String line) log,
  ) async {
    await for (final line in stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) log(trimmed);
    }
  }

  static String _quoteForDisplay(String value) {
    final normalized = value.replaceAll('\\', '/');
    if (!RegExp(r'\s|"').hasMatch(normalized)) return normalized;
    return '"${normalized.replaceAll('"', r'\"')}"';
  }
}
