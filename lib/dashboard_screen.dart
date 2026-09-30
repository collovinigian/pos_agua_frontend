import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'app_events.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _jornadaActiva;
  Map<String, dynamic>? _resumen;
  
  final TextEditingController _fondoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _verificarEstadoCaja();
  }

  Future<void> _verificarEstadoCaja() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/reportes/actual'));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _jornadaActiva = data['jornada'];
          _resumen = data['resumen'];
        });
      } else {
        setState(() {
          _jornadaActiva = null;
          _resumen = null;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error conectando: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _abrirCaja() async {
  
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:3000/api/jornadas'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"fondo_inicial_usd": double.tryParse(_fondoController.text) ?? 0.0}),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Caja Abierta Exitosamente'), backgroundColor: Colors.green));
        await _verificarEstadoCaja(); 
        AppEvents.dispararActualizacion();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error del servidor: ${response.body}')));
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error de conexión: $e')));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _ejecutarCierreZ() async {
    setState(() => _isLoading = true); 
    try {
      final response = await http.post(Uri.parse('http://127.0.0.1:3000/api/facturas/reporte-z'));
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Cierre Z ejecutado. Caja cerrada.'), backgroundColor: Colors.green));
          await _verificarEstadoCaja(); 
          AppEvents.dispararActualizacion();
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: ${response.body}')));
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error al cerrar caja: $e')));
      setState(() => _isLoading = false);
    }
  }

  // --- NUEVO: MENÚ DE OPCIONES DE CIERRE ---
  void _mostrarOpcionesDeCierre() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Opciones de Cuadre de Caja', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // BOTÓN REPORTE X (Conectado a la impresora)
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.blue, size: 40),
              title: const Text('Imprimir Reporte X', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Lectura de caja para cambio de turno. No cierra la jornada actual.'),
              onTap: () {
                Navigator.pop(ctx);
                _imprimirReporteX(); 
              },
            ),
            const Divider(height: 30),
            // BOTÓN CIERRE Z
            ListTile(
              leading: const Icon(Icons.lock, color: Colors.red, size: 40),
              title: const Text('Ejecutar Cierre Z', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              subtitle: const Text('Cierre definitivo fiscal. La caja quedará bloqueada hasta el próximo turno.'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmarCierreZ(); 
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))
        ],
      ),
    );
  }

  void _confirmarCierreZ() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Advertencia: Cierre Z', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text('¿Estás 100% seguro de ejecutar el Cierre Z?\n\nEsto finalizará la jornada y cerrará la caja. No podrás facturar más el día de hoy hasta abrir un turno nuevo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _ejecutarCierreZ();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sí, Ejecutar Cierre Z'),
          )
        ],
      ),
    );
  }

  // --- INTERFACES VISUALES ---
  
  Widget _buildPantallaAbrirCaja() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.point_of_sale, size: 100, color: Colors.grey),
            const SizedBox(height: 20),
            const Text('Turno Cerrado', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.grey)),
            const Text('Ingresa el fondo de caja chica para iniciar a facturar.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            TextField(
              controller: _fondoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Fondo Inicial en USD', 
                hintText: '0.00', // <--- ¡Esto es lo que lo pone en gris!
                border: OutlineInputBorder(), 
                prefixIcon: Icon(Icons.attach_money)
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _abrirCaja,
                icon: const Icon(Icons.lock_open),
                label: const Text('ABRIR CAJA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPantallaReportes() {
    final double fondoApertura = double.tryParse(_jornadaActiva!['fondo_inicial_usd'].toString()) ?? 0.0;
    final Map<String, dynamic> pagos = _resumen!['desglose_pagos'] ?? {};

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ESTADO DE CAJA', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(20)), child: Text('ABIERTA', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const Divider(height: 32, thickness: 2),
                  
                  // Info de Cabecera
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Jornada ID:', style: TextStyle(fontWeight: FontWeight.bold)), Text('#${_jornadaActiva!['id']}')]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Apertura:', style: TextStyle(fontWeight: FontWeight.bold)), Text(DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.parse(_jornadaActiva!['fecha_inicio'] ?? DateTime.now().toString()).toLocal()))]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Facturas Emitidas:', style: TextStyle(fontWeight: FontWeight.bold)), Text('${_resumen!['cantidad_facturas']}')]),
                  const Divider(height: 32),

                  // Desglose de ingresos
                  const Text('INGRESOS (PAGADOS)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Fondo de Apertura (Caja Chica):'), Text('\$${fondoApertura.toStringAsFixed(2)}')]),
                  ...pagos.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Ventas en ${entry.key}:'), Text('\$${double.parse(entry.value.toString()).toStringAsFixed(2)}')]),
                  )),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.green.shade50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL EFECTIVO/BANCOS:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('\$${(_resumen!['total_pagado_usd'] + fondoApertura).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                      ],
                    ),
                  ),
                  const Divider(height: 32),

                  // Otros datos
                  const Text('OTROS MOVIMIENTOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Ventas a Crédito (Por Cobrar):', style: TextStyle(color: Colors.orange)), Text('\$${double.parse(_resumen!['total_pendiente_usd'].toString()).toStringAsFixed(2)}')]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Facturas Devueltas (Anuladas):', style: TextStyle(color: Colors.red)), Text('\$${double.parse(_resumen!['total_anulado_usd'].toString()).toStringAsFixed(2)}')]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Impuestos (IVA Recaudado):', style: TextStyle(color: Colors.grey)), Text('\$${double.parse(_resumen!['total_iva_usd'].toString()).toStringAsFixed(2)}')]),
                  const Divider(height: 40, thickness: 2),

                  // BOTÓN ÚNICO DE CIERRE
                  SizedBox(
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _mostrarOpcionesDeCierre,
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('OPCIONES DE CIERRE / CUADRE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de Control (Caja)'),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _verificarEstadoCaja, tooltip: 'Actualizar',)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _jornadaActiva == null 
              ? _buildPantallaAbrirCaja() 
              : _buildPantallaReportes(),
    );
  }

  Future<void> _imprimirReporteX() async {
    try {
      final response = await http.post(Uri.parse('http://127.0.0.1:3000/api/facturas/reporte-x'));
      
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🖨️ Reporte X impreso con éxito'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error al imprimir Reporte X: ${response.body}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error de conexión: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}