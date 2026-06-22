import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'theme.dart';
import 'app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1100, 720),
    minimumSize: Size(600, 400),
    center: true,
    title: 'Biobase Performance Lab',
    backgroundColor: BiobaseColors.bg,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const BiobaseApp());
}

class BiobaseApp extends StatelessWidget {
  const BiobaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Biobase Performance Lab',
      debugShowCheckedModeBanner: false,
      theme: buildBiobaseTheme(),
      home: const AppShell(),
    );
  }
}
