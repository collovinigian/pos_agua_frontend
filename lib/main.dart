import 'package:flutter/material.dart';
import 'main_layout.dart';
import 'app_events.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppEvents.cargarConfiguracion();
  runApp(const POSAguaApp());
}

class POSAguaApp extends StatelessWidget {
  const POSAguaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConfigData>(
      valueListenable: AppEvents.configNotifier,
      builder: (context, config, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Sistema de Facturación',
          themeMode: config.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: config.seedColor,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: config.seedColor,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const MainLayout(),
        );
      },
    );
  }
}