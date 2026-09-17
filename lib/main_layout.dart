import 'package:flutter/material.dart';
import 'inventario_screen.dart'; 
import 'tasa_screen.dart';
import 'dashboard_screen.dart';
import 'clientes_screen.dart';
import 'pos_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(), // 0
    const PosScreen(),       // 1
    const InventarioScreen(), // 2
    const ClientesScreen(),  // 3
    const TasaBCVScreen(),   // 4
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: const Color(0xFFF8F9FA), 
            elevation: 1,
            useIndicator: true,
            indicatorColor: Colors.blue.withValues(alpha: 0.2),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard, color: Colors.blue), label: Text('Inicio')),
              NavigationRailDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale, color: Colors.blue), label: Text('Facturar')),
              NavigationRailDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory, color: Colors.blue), label: Text('Inventario')),
              NavigationRailDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people, color: Colors.blue), label: Text('Clientes')),
              NavigationRailDestination(icon: Icon(Icons.currency_exchange_outlined), selectedIcon: Icon(Icons.currency_exchange, color: Colors.blue), label: Text('Tasa BCV')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Color(0xFFEEEEEE)),
          
          Expanded(
            child: Container(
              color: Colors.white, 
              child: IndexedStack(
                index: _selectedIndex,
                children: _screens,
              ),
            ),
          ),
        ],
      ),
    );
  }
}