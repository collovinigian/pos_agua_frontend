import 'package:flutter/material.dart';

class AppEvents {
  // Este es el "Timbre" que todas las pantallas escucharán
  static final ValueNotifier<bool> refreshNotifier = ValueNotifier(false);

  // Función para tocar el timbre
  static void dispararActualizacion() {
    refreshNotifier.value = !refreshNotifier.value;
  }
}