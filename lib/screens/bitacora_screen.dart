import 'package:flutter/material.dart';

import '../services/base_datos.dart';

class BitacoraScreen extends StatefulWidget {
  const BitacoraScreen({super.key});

  @override
  State<BitacoraScreen> createState() => _BitacoraScreenState();
}

class _BitacoraScreenState extends State<BitacoraScreen> {
  List<Map<String, dynamic>> _registros = [];
  String _filtro = 'todos';
  bool _cargando = true;

  static const Map<String, String> _grupos = {
    'todos': 'Todos',
    'venta': 'Ventas',
    'compras': 'Compras y pagos',
    'cobros': 'Abonos de clientes',
    'inventario': 'Inventario',
    'usuarios': 'Usuarios',
    'sesion': 'Sesiones',
    'sistema': 'Sistema',
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _registros = await BaseDatos.instancia.listarBitacora(limite: 500);
    if (mounted) setState(() => _cargando = false);
  }

  String _grupoDe(String accion) {
    switch (accion) {
      case 'venta':
        return 'venta';
      case 'compra':
      case 'pago_compra':
        return 'compras';
      case 'abono':
        return 'cobros';
      case 'producto_crear':
      case 'producto_editar':
      case 'producto_eliminar':
      case 'producto_vaciar':
      case 'stock_ajuste':
        return 'inventario';
      case 'usuario_crear':
      case 'usuario_editar':
      case 'usuario_eliminar':
        return 'usuarios';
      case 'login':
      case 'login_fallido':
        return 'sesion';
      default:
        return 'sistema'; // config, licencia
    }
  }

  // Clase simple en lugar de records: máxima compatibilidad
  String _etiquetaDe(String accion) {
    switch (accion) {
      case 'venta':
        return 'Venta';
      case 'compra':
        return 'Compra';
      case 'pago_compra':
        return 'Pago a proveedor';
      case 'abono':
        return 'Abono de cliente';
      case 'producto_crear':
        return 'Producto creado';
      case 'producto_editar':
        return 'Producto editado';
      case 'producto_eliminar':
        return 'Producto eliminado';
      case 'producto_vaciar':
        return 'Catálogo vaciado';
      case 'stock_ajuste':
        return 'Ajuste de stock';
      case 'usuario_crear':
        return 'Usuario creado';
      case 'usuario_editar':
        return 'Usuario editado';
      case 'usuario_eliminar':
        return 'Usuario eliminado';
      case 'login':
        return 'Inicio de sesión';
      case 'login_fallido':
        return 'Intento fallido de sesión';
      case 'config':
        return 'Configuración';
      case 'licencia':
        return 'Licencia';
      default:
        return accion;
    }
  }

  IconData _iconoDe(String accion) {
    switch (accion) {
      case 'venta':
        return Icons.point_of_sale;
      case 'compra':
        return Icons.local_shipping;
      case 'pago_compra':
        return Icons.payment;
      case 'abono':
        return Icons.savings;
      case 'producto_crear':
        return Icons.add_box;
      case 'producto_editar':
        return Icons.edit;
      case 'producto_eliminar':
        return Icons.delete_outline;
      case 'producto_vaciar':
        return Icons.delete_sweep_outlined;
      case 'stock_ajuste':
        return Icons.tune;
      case 'usuario_crear':
        return Icons.person_add;
      case 'usuario_editar':
        return Icons.manage_accounts;
      case 'usuario_eliminar':
        return Icons.person_remove;
      case 'login':
        return Icons.login;
      case 'login_fallido':
        return Icons.warning_amber_rounded;
      case 'config':
        return Icons.settings;
      case 'licencia':
        return Icons.key;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _colorDe(String accion) {
    switch (accion) {
      case 'venta':
        return Colors.teal;
      case 'compra':
      case 'pago_compra':
        return Colors.orange;
      case 'abono':
        return Colors.green;
      case 'producto_crear':
      case 'producto_editar':
        return Colors.blue;
      case 'producto_eliminar':
      case 'producto_vaciar':
      case 'usuario_eliminar':
      case 'login_fallido':
        return Colors.red;
      case 'stock_ajuste':
        return Colors.purple;
      case 'usuario_crear':
      case 'usuario_editar':
        return Colors.indigo;
      case 'login':
        return Colors.teal;
      case 'config':
        return Colors.blueGrey;
      case 'licencia':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  List<Map<String, dynamic>> get _filtrados => _filtro == 'todos'
      ? _registros
      : _registros
            .where((r) => _grupoDe(r['accion'] as String) == _filtro)
            .toList();

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de actividad')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: DropdownButtonFormField<String>(
              initialValue: _filtro,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.filter_list),
                labelText: 'Filtrar por tipo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _grupos.entries
                  .map(
                    (g) => DropdownMenuItem<String>(
                      value: g.key,
                      child: Text(g.value),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _filtro = v ?? 'todos'),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : lista.isEmpty
                ? const Center(
                    child: Text(
                      'Sin registros todavía',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = lista[i];
                      final accion = r['accion'] as String;
                      final etiqueta = _etiquetaDe(accion);
                      final icono = _iconoDe(accion);
                      final color = _colorDe(accion);
                      final detalle = (r['detalle'] ?? '') as String;
                      final usuario = (r['usuario'] ?? 'sistema') as String;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: color.withOpacity(0.15),
                          child: Icon(icono, size: 18, color: color),
                        ),
                        title: Text(
                          detalle.isEmpty ? etiqueta : '$etiqueta · $detalle',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${r['fecha'].toString().substring(0, 16).replaceAll('T', ' ')} · $usuario',
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Mostrando los últimos ${_registros.length} registros',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
