import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TasaBCVScreen extends StatefulWidget {
  const TasaBCVScreen({super.key});

  @override
  State<TasaBCVScreen> createState() => _TasaBCVScreenState();
}

class _TasaBCVScreenState extends State<TasaBCVScreen> {
  final TextEditingController _tasaController = TextEditingController();
  bool _isLoading = false;
  
  // 1. Variable para guardar la tasa actual
  double _tasaActual = 0.0;

  // 2. Se ejecuta automáticamente al abrir la pantalla
  @override
  void initState() {
    super.initState();
    _obtenerTasaActual();
  }

  // 3. Función para buscar la tasa en la base de datos
  Future<void> _obtenerTasaActual() async {
    try {
      // Revisa que esta URL coincida con tu ruta GET del backend
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/tasas/actual'));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            // Asume que tu backend devuelve un JSON como { "tasa_bcv": 36.50 }
            _tasaActual = double.tryParse(data['tasa_bcv'].toString()) ?? 0.0;
          });
        }
      }
    } catch (e) {
      debugPrint("No se pudo cargar la tasa actual: $e");
    }
  }

  Future<void> _guardarTasa() async {
    if (_tasaController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse('http://127.0.0.1:3000/api/tasas/manual');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tasa_bcv": double.parse(_tasaController.text.replaceAll(',', '.')) // Seguridad por si usan comas
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ ¡Tasa guardada exitosamente en PostgreSQL!'),
              backgroundColor: Colors.green,
            ),
          );
          _tasaController.clear();
          
          // Actualizamos la vista de la tasa actual
          _obtenerTasaActual();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error del servidor: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Error de conexión: No se pudo conectar a la API.')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración - Tasa BCV'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ingrese la tasa BCV del día:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                
                // 4. Actualizamos el TextField
                TextField(
                  controller: _tasaController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    // 🔥 Aquí ocurre la magia: Si hay tasa, la muestra. Si no, muestra el ejemplo.
                    labelText: _tasaActual > 0 ? 'Tasa actual: $_tasaActual Bs' : 'Ej: 36.50',
                    hintText: _tasaActual > 0 ? 'Ej: ${_tasaActual.toStringAsFixed(2)}' : '',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.currency_exchange),
                  ),
                ),
                
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _isLoading ? null : _guardarTasa,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Guardar Tasa Manual', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}