import 'package:flutter/material.dart';
import 'inventario_screen.dart'; // <--- Importamos la nueva pantalla de la tabla
import 'tasa_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  // Esta variable controla qué pantalla estamos viendo (0 = Inicio, 1 = Productos, etc.)
  int _selectedIndex = 0;

  // Lista de las pantallas de tu sistema
  final List<Widget> _screens = [
    const Center(
      child: Text(
        'Dashboard / Inicio\n(Aquí pondremos las ventas del día)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 24, color: Colors.grey),
      ),
    ),
    const InventarioScreen(), // <--- Aquí mostramos la tabla de Inventario
    const TasaBCVScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Menú Lateral Moderno
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: const Color(0xFFF8F9FA), // Un gris muy clarito y moderno
            elevation: 1,
            useIndicator: true,
            indicatorColor: Colors.blue.withValues(alpha: 0.2), // Corrección para Flutter nuevo
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: Colors.blue),
                label: Text('Inicio'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory, color: Colors.blue),
                label: Text('Inventario'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.currency_exchange_outlined),
                selectedIcon: Icon(Icons.currency_exchange, color: Colors.blue),
                label: Text('Tasa BCV'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Color(0xFFEEEEEE)),
          // El área donde se muestra la pantalla seleccionada
          Expanded(
            child: Container(
              color: Colors.white, // Fondo blanco limpio
              child: _screens[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }
}