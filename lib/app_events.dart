import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ConfigData {
  final String razonSocial;
  final String rif;
  final String direccion;
  final String telefono;
  final String? logoBase64;
  final ThemeMode themeMode;
  final Color seedColor;
  final String colorTemaKey;

  const ConfigData({
    this.razonSocial = 'MI EMPRESA, C.A.',
    this.rif = 'J-00000000-0',
    this.direccion = 'DIRECCIÓN FISCAL DE LA EMPRESA',
    this.telefono = '',
    this.logoBase64,
    this.themeMode = ThemeMode.light,
    this.seedColor = Colors.blue,
    this.colorTemaKey = 'blue',
  });

  ConfigData copyWith({
    String? razonSocial,
    String? rif,
    String? direccion,
    String? telefono,
    String? logoBase64,
    bool clearLogo = false,
    ThemeMode? themeMode,
    Color? seedColor,
    String? colorTemaKey,
  }) {
    return ConfigData(
      razonSocial: razonSocial ?? this.razonSocial,
      rif: rif ?? this.rif,
      direccion: direccion ?? this.direccion,
      telefono: telefono ?? this.telefono,
      logoBase64: clearLogo ? null : (logoBase64 ?? this.logoBase64),
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      colorTemaKey: colorTemaKey ?? this.colorTemaKey,
    );
  }
}

class AppEvents {
  // Este es el "Timbre" que todas las pantallas escucharán
  static final ValueNotifier<bool> refreshNotifier = ValueNotifier(false);

  // Notificador global de configuración y tema
  static final ValueNotifier<ConfigData> configNotifier = ValueNotifier(const ConfigData());

  // Mapa de colores disponibles
  static const Map<String, Color> coloresDisponibles = {
    'blue': Colors.blue,
    'indigo': Colors.indigo,
    'teal': Colors.teal,
    'green': Colors.green,
    'purple': Colors.purple,
    'orange': Colors.orange,
    'red': Colors.red,
  };

  // Mapa de nombres en español para UI
  static const Map<String, String> nombresColores = {
    'blue': 'Azul',
    'indigo': 'Índigo',
    'teal': 'Turquesa',
    'green': 'Verde',
    'purple': 'Morado',
    'orange': 'Naranja',
    'red': 'Rojo',
  };

  // Función para tocar el timbre
  static void dispararActualizacion() {
    refreshNotifier.value = !refreshNotifier.value;
  }

  // Cargar configuración desde el API
  static Future<void> cargarConfiguracion() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/configuracion'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String colorKey = data['color_tema'] ?? 'blue';
        final Color seedColor = coloresDisponibles[colorKey] ?? Colors.blue;
        final String modoTema = data['tema_modo'] ?? 'light';

        configNotifier.value = ConfigData(
          razonSocial: data['razon_social'] ?? 'MI EMPRESA, C.A.',
          rif: data['rif'] ?? 'J-00000000-0',
          direccion: data['direccion'] ?? 'DIRECCIÓN FISCAL DE LA EMPRESA',
          telefono: data['telefono'] ?? '',
          logoBase64: data['logo_base64'],
          themeMode: modoTema == 'dark' ? ThemeMode.dark : ThemeMode.light,
          seedColor: seedColor,
          colorTemaKey: colorKey,
        );
      }
    } catch (e) {
      // Silently use defaults if API is not available
      debugPrint('Error cargando configuración: $e');
    }
  }
}