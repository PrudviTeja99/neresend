import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/main_scaffold_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: NeReSendApp()));
}

class NeReSendApp extends StatelessWidget {
  const NeReSendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeReSend',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScaffoldScreen(),
    );
  }
}

