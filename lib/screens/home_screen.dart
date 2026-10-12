import 'package:flutter/material.dart';

import '../services/licencia_service.dart';
import '../services/sesion.dart';
import '../services/tasa_service.dart';
import 'ajustes_screen.dart';
import 'compras_screen.dart';
import 'cuentas_cobrar_screen.dart';
import 'cuentas_pagar_screen.dart';
import 'inventario_screen.dart';
import 'licencia_screen.dart';
import 'login_screen.dart';
import 'reportes_screen.dart';
import 'usuarios_screen.dart';
import 'venta_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ventaKey = GlobalKey<VentaScreenState>();
  final _inventarioKey = GlobalKey<InventarioScreenState>();
  int _indice = 0;
  EstadoLicencia? _licencia;

  bool get _esAdmin => SesionActual.esAdmin;
  double get _tasa => TasaService.tasa.value;

  @override
  void initState() {
    super.initState();
    TasaService.tasa.addListener(_alCambiarTasa);
    _refrescarDatos();
  }

  @override
  void dispose() {
    TasaService.tasa.removeListener(_alCambiarTasa);
    super.dispose();
  }

  void _alCambiarTasa() {
    if (mounted) setState(() {});
  }

  Future<void> _refrescarDatos() async {
    _licencia = await LicenciaService().verificar();
    if (mounted) setState(() {});
  }

  String _textoLicencia() {
    final l = _licencia;
    if (l == null) return '';
    if (l.expirada) return '⚠️ Licencia expirada';
    if (l.licenciada) {
      return l.permanente
          ? '✅ Licencia permanente'
          : '✅ Licenciado hasta ${l.vence!.day}/${l.vence!.month}/${l.vence!.year}';
    }
    return '🧪 Prueba: ${l.diasTrialRestantes} días restantes';
  }

  Future<void> _cerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (ok == true) {
      SesionActual.cerrar();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    }
  }

  void _irA(int indice) {
    setState(() => _indice = indice);
    Navigator.pop(context);
    // Refresca la pestaña destino con datos frescos de la BD
    if (indice == 0) _ventaKey.currentState?.recargar();
    if (indice == 1) _inventarioKey.currentState?.recargar();
  }

  Future<void> _abrir(Widget pantalla, {bool refrescarDatos = false}) async {
    Navigator.pop(context);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    // Al volver de cualquier módulo (Compras, CxC, CxP...), refresca
    // ambas pestañas para que ventas e inventario estén al día.
    _ventaKey.currentState?.recargar();
    _inventarioKey.currentState?.recargar();
    if (refrescarDatos) _refrescarDatos();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 🔐 Cajero: SOLO ventas. Admin: todo.
    return _esAdmin ? _scaffoldAdmin() : _scaffoldCajero();
  }

  // ---------- CAJERO ----------

  Widget _scaffoldCajero() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Punto de Venta'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                SesionActual.usuario?.nombre ?? '',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: _cerrarSesion,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: VentaScreen(key: _ventaKey),
    );
  }

  // ---------- ADMIN ----------

  Widget _scaffoldAdmin() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_indice == 0 ? 'Punto de Venta' : 'Inventario'),
      ),
      drawer: _drawerAdmin(),
      body: IndexedStack(
        index: _indice,
        children: [
          VentaScreen(key: _ventaKey),
          InventarioScreen(key: _inventarioKey),
        ],
      ),
    );
  }

  Widget _drawerAdmin() {
    return Drawer(
      child: ListView(
        children: [
          // Container en vez de DrawerHeader: crece según contenido
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_circle, size: 48),
                const SizedBox(height: 8),
                Text(
                  SesionActual.usuario?.nombre ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  label: const Text(
                    'Administrador',
                    style: TextStyle(fontSize: 12),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Text(_textoLicencia(), style: const TextStyle(fontSize: 12)),
                if (_tasa > 0)
                  Text(
                    '💱 Tasa: Bs ${_tasa.toStringAsFixed(2)} / \$1',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.point_of_sale),
            title: const Text('Vender'),
            selected: _indice == 0,
            onTap: () => _irA(0),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Inventario'),
            selected: _indice == 1,
            onTap: () => _irA(1),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Reportes'),
            onTap: () => _abrir(const ReportesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Compras'),
            onTap: () => _abrir(const ComprasScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.request_quote_outlined),
            title: const Text('Cuentas por cobrar'),
            onTap: () => _abrir(const CuentasCobrarScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Cuentas por pagar'),
            onTap: () => _abrir(const CuentasPagarScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.manage_accounts),
            title: const Text('Usuarios'),
            onTap: () => _abrir(const UsuariosScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Ajustes'),
            onTap: () => _abrir(const AjustesScreen(), refrescarDatos: true),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Licencia'),
            onTap: () => _abrir(const LicenciaScreen(), refrescarDatos: true),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            onTap: _cerrarSesion,
          ),
        ],
      ),
    );
  }
}
