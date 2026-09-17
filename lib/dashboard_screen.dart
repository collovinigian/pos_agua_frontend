import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  bool _isJornadaAbierta = false;
  Map<String, dynamic>? _jornadaActual;

  final TextEditingController _fondoUsdController = TextEditingController(text: '0');
  final TextEditingController _fondoBsController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _verificarJornada();
  }

  // 1. Pregunta al backend si hay un día activo
  Future<void> _verificarJornada() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/jornadas/actual'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isJornadaAbierta = data['abierta'];
          _jornadaActual = data['abierta'] ? data['data'] : null;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error conectando: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 2. Función para abrir la caja
  Future<void> _abrirCaja() async {
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:3000/api/jornadas/abrir'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fondo_caja_usd": double.tryParse(_fondoUsdController.text) ?? 0,
          "fondo_caja_bs": double.tryParse(_fondoBsController.text) ?? 0
        }),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ ¡Caja abierta con éxito!'), backgroundColor: Colors.green));
          Navigator.pop(context); // Cierra el modal
          _verificarJornada(); // Recarga la pantalla
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: ${response.body}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error al abrir caja.')));
    }
  }

  // 3. Función para cerrar la caja
  Future<void> _cerrarCaja() async {
    if (_jornadaActual == null) return;
    try {
      final response = await http.put(
        Uri.parse('http://127.0.0.1:3000/api/jornadas/cerrar/${_jornadaActual!['id']}'),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔒 Jornada cerrada. ¡Buen trabajo!'), backgroundColor: Colors.orange));
          Navigator.pop(context); // Cierra el modal de confirmación
          _verificarJornada(); // Recarga la pantalla
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error al cerrar caja.')));
    }
  }

  // Ventana flotante para pedir el dinero base al abrir
  void _mostrarDialogoApertura() {
    _fondoUsdController.text = '0';
    _fondoBsController.text = '0';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Abrir Nueva Jornada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa el dinero en efectivo base con el que arrancas el día (sencillo para dar vueltos):'),
            const SizedBox(height: 20),
            TextField(
              controller: _fondoUsdController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Fondo Inicial en USD', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fondoBsController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Fondo Inicial en Bs', border: OutlineInputBorder(), prefixIcon: Text('Bs ', style: TextStyle(fontWeight: FontWeight.bold)), prefixIconConstraints: BoxConstraints(minWidth: 40, minHeight: 0)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: _abrirCaja,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Abrir Caja'),
          ),
        ],
      ),
    );
  }

  // Ventana flotante para confirmar el cierre
  void _mostrarDialogoCierre() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Jornada'),
        content: const Text('¿Estás seguro de que deseas cerrar la caja de hoy? Ya no podrás facturar hasta abrir una nueva.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: _cerrarCaja,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sí, Cerrar Caja'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Control'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icono gigante visual
              Icon(
                _isJornadaAbierta ? Icons.store_outlined : Icons.store_mall_directory_rounded,
                size: 120,
                color: _isJornadaAbierta ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 24),
              Text(
                _isJornadaAbierta ? '¡La Caja está Abierta!' : 'La Caja está Cerrada',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                _isJornadaAbierta 
                    ? 'Listo para facturar. Puedes cerrar el turno al final del día.' 
                    : 'Abre la caja para comenzar a registrar facturas.',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              
              // Si está abierta, mostramos los fondos actuales y el botón rojo. Si no, el botón verde.
              if (_isJornadaAbierta && _jornadaActual != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300)
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Colors.blue),
                      const SizedBox(width: 10),
                      Text('Fondo Inicial: \$${_jornadaActual!['fondo_caja_usd']} | Bs ${_jornadaActual!['fondo_caja_bs']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _mostrarDialogoCierre,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Cerrar Caja (Finalizar Día)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                )
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _mostrarDialogoApertura,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Abrir Caja (Iniciar Día)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}