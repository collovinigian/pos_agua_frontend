import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendManager {
  static Process? _procesoBackend;
  static bool get isBackendSpawnedByApp => _procesoBackend != null;

  /// Busca la carpeta que contiene el archivo server.js del backend.
  static String? findBackendDirectory() {
    // 1. Buscar hacia arriba desde la ubicación del ejecutable
    try {
      final exeFile = File(Platform.resolvedExecutable);
      var current = exeFile.parent;
      for (int i = 0; i < 8; i++) {
        final candidate = Directory('${current.path}${Platform.pathSeparator}facturacion-agua-api');
        if (candidate.existsSync()) {
          final serverFile = File('${candidate.path}${Platform.pathSeparator}server.js');
          if (serverFile.existsSync()) {
            return candidate.path;
          }
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    } catch (e) {
      debugPrint('Error buscando backend desde exe: $e');
    }

    // 2. Buscar hacia arriba desde el directorio de trabajo actual
    try {
      var current = Directory.current;
      for (int i = 0; i < 8; i++) {
        final candidate = Directory('${current.path}${Platform.pathSeparator}facturacion-agua-api');
        if (candidate.existsSync()) {
          final serverFile = File('${candidate.path}${Platform.pathSeparator}server.js');
          if (serverFile.existsSync()) {
            return candidate.path;
          }
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    } catch (e) {
      debugPrint('Error buscando backend desde cwd: $e');
    }

    // 3. Ruta fija de desarrollo en este equipo
    const devPath = r'C:\Users\gianf\OneDrive\Desktop\Programa facturacion\facturacion-agua-api';
    if (Directory(devPath).existsSync() &&
        File('$devPath${Platform.pathSeparator}server.js').existsSync()) {
      return devPath;
    }

    return null;
  }

  /// Busca el ejecutable de Node.js en el sistema.
  static String findNodeExecutable() {
    if (Platform.isWindows) {
      const knownPaths = [
        r'C:\Program Files\nodejs\node.exe',
        r'C:\Program Files (x86)\nodejs\node.exe',
      ];
      for (final p in knownPaths) {
        if (File(p).existsSync()) {
          return p;
        }
      }
    }
    return 'node';
  }

  /// Verifica si el endpoint /api/health responde con 200 OK.
  static Future<bool> verificarHealth({
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:3000/api/health'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Inicia el backend si no está corriendo actualmente.
  static Future<bool> iniciarBackendSiEsNecesario({
    void Function(String message)? onStatusUpdate,
  }) async {
    onStatusUpdate?.call('Verificando conexión con el servidor...');

    // 1. Si ya está corriendo y responde, continuamos de inmediato
    if (await verificarHealth()) {
      debugPrint('✅ Backend ya está en ejecución en http://127.0.0.1:3000');
      onStatusUpdate?.call('Servidor listo');
      return true;
    }

    // 2. Localizar la carpeta del backend
    onStatusUpdate?.call('Localizando archivos del servidor...');
    final backendDir = findBackendDirectory();
    if (backendDir == null) {
      debugPrint('❌ Error: No se encontró la carpeta del backend facturacion-agua-api');
      return false;
    }

    final nodeExe = findNodeExecutable();
    debugPrint('🚀 Iniciando backend desde: $backendDir con: $nodeExe');
    onStatusUpdate?.call('Iniciando servicios del sistema...');

    try {
      // Se lanza el proceso sin terminal visible (runInShell: false para evitar ventana CMD)
      _procesoBackend = await Process.start(
        nodeExe,
        ['server.js'],
        workingDirectory: backendDir,
        runInShell: false,
      );

      _procesoBackend?.stdout.listen((data) {
        final text = utf8.decode(data, allowMalformed: true).trim();
        if (text.isNotEmpty) debugPrint('[Backend] $text');
      });

      _procesoBackend?.stderr.listen((data) {
        final text = utf8.decode(data, allowMalformed: true).trim();
        if (text.isNotEmpty) debugPrint('[Backend ERR] $text');
      });

      _procesoBackend?.exitCode.then((code) {
        debugPrint('[Backend] Proceso finalizado con código $code');
        _procesoBackend = null;
      });
    } catch (e) {
      debugPrint('❌ Error al iniciar proceso de Node.js: $e');
      return false;
    }

    // 3. Polling de espera: cada 500ms, máximo 15 intentos
    const maxAttempts = 15;
    for (int i = 1; i <= maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      onStatusUpdate?.call('Iniciando servicios del sistema ($i/$maxAttempts)...');
      if (await verificarHealth(timeout: const Duration(milliseconds: 400))) {
        debugPrint('✅ Backend conectado exitosamente en el intento $i.');
        onStatusUpdate?.call('Servicios listos');
        return true;
      }
    }

    debugPrint('❌ Tiempo de espera agotado al conectar con el backend.');
    return false;
  }

  /// Detiene el servidor backend de forma segura y limpia.
  static Future<void> detenerBackend() async {
    debugPrint('🛑 Solicitando apagado del backend...');

    // 1. Enviar orden de apagado limpio vía HTTP
    try {
      await http
          .post(Uri.parse('http://127.0.0.1:3000/api/sistema/apagar'))
          .timeout(const Duration(seconds: 1));
      debugPrint('✅ Orden de apagado enviada con éxito');
    } catch (e) {
      debugPrint('⚠️ Nota al enviar orden de apagado: $e');
    }

    // 2. Si nosotros iniciamos el proceso, nos aseguramos de que no quede colgado
    if (_procesoBackend != null) {
      try {
        await Future.delayed(const Duration(milliseconds: 250));
        _procesoBackend?.kill();
      } catch (e) {
        debugPrint('⚠️ Error terminando proceso backend: $e');
      }
      _procesoBackend = null;
    }
  }
}
