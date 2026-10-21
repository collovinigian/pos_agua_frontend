import 'dart:ui';
import 'package:flutter/material.dart';
import 'main_layout.dart';
import 'app_events.dart';
import 'backend_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const POSAguaApp());
}

class POSAguaApp extends StatefulWidget {
  const POSAguaApp({super.key});

  @override
  State<POSAguaApp> createState() => _POSAguaAppState();
}

class _POSAguaAppState extends State<POSAguaApp> {
  late final AppLifecycleListener _lifecycleListener;
  bool _isBackendReady = false;
  String _statusMessage = 'Iniciando servicios del sistema...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await BackendManager.detenerBackend();
        return AppExitResponse.exit;
      },
    );
    _iniciarApp();
  }


  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _iniciarApp() async {
    setState(() {
      _isBackendReady = false;
      _errorMessage = null;
      _statusMessage = 'Iniciando servicios del sistema...';
    });

    final exito = await BackendManager.iniciarBackendSiEsNecesario(
      onStatusUpdate: (msg) {
        if (mounted) {
          setState(() {
            _statusMessage = msg;
          });
        }
      },
    );

    if (exito) {
      await AppEvents.cargarConfiguracion();
      if (mounted) {
        setState(() {
          _isBackendReady = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _errorMessage =
              'No se pudo conectar con el servidor backend.\nVerifica que Node.js esté instalado y que PostgreSQL esté en ejecución.';
        });
      }
    }
  }

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
          home: _isBackendReady
              ? const MainLayout()
              : _SplashScreen(
                  statusMessage: _statusMessage,
                  errorMessage: _errorMessage,
                  onRetry: _iniciarApp,
                ),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final String statusMessage;
  final String? errorMessage;
  final VoidCallback onRetry;

  const _SplashScreen({
    required this.statusMessage,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo / Icono
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.water_drop_rounded,
                  size: 48,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SISTEMA DE FACTURACIÓN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Control de Ventas & Inventario',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 36),
              if (errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: colorScheme.error,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar Conexión'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 20),
                Text(
                  statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}