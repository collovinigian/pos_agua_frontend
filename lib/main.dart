import 'package:flutter/material.dart';
import 'main_layout.dart';

void main() {
  runApp(const POSAguaApp());
}

class POSAguaApp extends StatelessWidget {
  const POSAguaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema de Facturación',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // Esto le da un toque moderno a toda la app
        scaffoldBackgroundColor: Colors.white, 
      ),
      home: const MainLayout(),
    );
  }
}