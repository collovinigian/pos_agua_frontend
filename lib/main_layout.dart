import 'package:flutter/material.dart';
import 'inventario_screen.dart';
import 'tasa_screen.dart';
import 'dashboard_screen.dart';
import 'clientes_screen.dart';
import 'pos_screen.dart';
import 'ajustes_screen.dart';
import 'historial_ventas_screen.dart';
import 'cuaderno_screen.dart';
import 'compras_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(), // 0
    const PosScreen(), // 1
    const HistorialVentasScreen(), // 2
    const ComprasScreen(), // 3
    const CuadernoScreen(), // 4
    const InventarioScreen(), // 5
    const ClientesScreen(), // 6
    const TasaBCVScreen(), // 7
    const AjustesScreen(), // 8
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: (int index) {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                      labelType: NavigationRailLabelType.all,
                      elevation: 1,
                      useIndicator: true,
                      indicatorColor: colorScheme.primary.withValues(alpha: 0.15),
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Icons.dashboard_outlined),
                          selectedIcon: Icon(Icons.dashboard, color: colorScheme.primary),
                          label: const Text('Inicio'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.point_of_sale_outlined),
                          selectedIcon: Icon(Icons.point_of_sale, color: colorScheme.primary),
                          label: const Text('Facturar'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.history_outlined),
                          selectedIcon: Icon(Icons.history, color: colorScheme.primary),
                          label: const Text('Ventas'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.shopping_cart_outlined),
                          selectedIcon: Icon(Icons.shopping_cart, color: colorScheme.primary),
                          label: const Text('Compras'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.menu_book_outlined),
                          selectedIcon: Icon(Icons.menu_book, color: Colors.orange),
                          label: const Text('Cuaderno'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.inventory_2_outlined),
                          selectedIcon: Icon(Icons.inventory, color: colorScheme.primary),
                          label: const Text('Inventario'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.people_alt_outlined),
                          selectedIcon: Icon(Icons.people, color: colorScheme.primary),
                          label: const Text('Clientes'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.currency_exchange_outlined),
                          selectedIcon: Icon(Icons.currency_exchange, color: colorScheme.primary),
                          label: const Text('Tasa BCV'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings, color: colorScheme.primary),
                          label: const Text('Ajustes'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(
            child: Container(
              color: colorScheme.surface,
              child: IndexedStack(index: _selectedIndex, children: _screens),
            ),
          ),
        ],
      ),
    );
  }
}
