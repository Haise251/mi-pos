import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../models/venta.dart';
import '../services/base_datos.dart';

class ComprasScreen extends StatefulWidget {
  const ComprasScreen({super.key});

  @override
  State<ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends State<ComprasScreen> {
  final _proveedorCtrl = TextEditingController();
  final _cantCtrl = TextEditingController();
  final _costoCtrl = TextEditingController();
  Producto? _productoSel;
  final List<ItemCompra> _items = [];
  List<Producto> _productos = [];
  List<Map<String, dynamic>> _compras = [];
  double _tasa = 0;
  bool _aCredito = false; // ← vive AQUÍ, en el State (no en el widget)

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _proveedorCtrl.dispose();
    _cantCtrl.dispose();
    _costoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    _productos = await BaseDatos.instancia.listar();
    _compras = await BaseDatos.instancia.listarCompras();
    _tasa = await BaseDatos.instancia.obtenerTasa();
    if (mounted) setState(() {});
  }

  double get _totalItems => _items.fold<double>(0, (s, i) => s + i.subtotalUsd);

  void _agregarItem() {
    final p = _productoSel;
    final cant = int.tryParse(_cantCtrl.text) ?? 0;
    final costo = double.tryParse(_costoCtrl.text.replaceAll(',', '.')) ?? 0;
    if (p == null || cant <= 0 || costo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Completa producto, cantidad y costo')),
      );
      return;
    }
    setState(() {
      _items.add(
        ItemCompra(
          productoId: p.id!,
          nombre: p.nombre,
          cantidad: cant,
          costoUsd: costo,
        ),
      );
      _productoSel = null;
      _cantCtrl.clear();
      _costoCtrl.clear();
    });
  }

  Future<void> _registrar() async {
    if (_proveedorCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('⚠️ Escribe el proveedor')));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Agrega al menos un producto')),
      );
      return;
    }
    final compraId = await BaseDatos.instancia.registrarCompra(
      proveedor: _proveedorCtrl.text.trim(),
      items: List.of(_items),
      tasa: _tasa,
      aCredito: _aCredito,
    );
    setState(() {
      _items.clear();
      _proveedorCtrl.clear();
      _aCredito = false;
    });
    await _cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _aCredito
              ? '✅ Compra #$compraId registrada a crédito. Stock actualizado'
              : '✅ Compra #$compraId registrada. Stock actualizado',
        ),
      ),
    );
  }

  Future<void> _detalleCompra(int compraId) async {
    final det = await BaseDatos.instancia.detalleCompra(compraId);
    if (det == null || !mounted) return;
    final compra = det['compra'] as Map<String, dynamic>;
    final items = (det['items'] as List).cast<Map<String, dynamic>>();
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Compra #$compraId · ${compra['proveedor']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            compra['fecha'].toString().substring(0, 16).replaceAll('T', ' '),
          ),
          const Divider(height: 24),
          ...items.map(
            (i) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${i['cantidad']} × ${i['nombre_producto']}'),
              subtitle: Text(
                'Costo: ${formatoUsd((i['costo_usd'] as num).toDouble())} c/u',
              ),
              trailing: Text(formatoUsd((i['subtotal_usd'] as num).toDouble())),
            ),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '${formatoUsd((compra['total_usd'] as num).toDouble())} · ${formatoBs((compra['total_bs'] as num).toDouble())}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras a proveedores')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ---------- Nueva compra ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nueva compra',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _proveedorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor',
                      prefixIcon: Icon(Icons.store_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<Producto>(
                          initialValue: _productoSel,
                          isExpanded: true,
                          hint: const Text('Producto'),
                          items: _productos
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p.nombre,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _productoSel = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _cantCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Cant.',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _costoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Costo \$',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: _agregarItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                  ),
                  if (_items.isNotEmpty) ...[
                    const Divider(),
                    ..._items.map(
                      (i) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${i.cantidad} × ${i.nombre}'),
                        subtitle: Text(
                          '${formatoUsd(i.costoUsd)} c/u · ${formatoBs(i.costoUsd * _tasa)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatoUsd(i.subtotalUsd)),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _items.remove(i)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total compra',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${formatoUsd(_totalItems)} · ${formatoBs(_totalItems * _tasa)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  SwitchListTile(
                    title: const Text('Compra a crédito'),
                    subtitle: const Text(
                      'Quedará pendiente en Cuentas por pagar',
                    ),
                    value: _aCredito,
                    onChanged: (v) => setState(() => _aCredito = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  FilledButton.icon(
                    onPressed: _registrar,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Registrar compra'),
                  ),
                ],
              ),
            ),
          ),
          // ---------- Historial ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Historial de compras',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_compras.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Sin compras registradas',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ..._compras.map((c) {
                    final credito = c['estado_pago'] == 'credito';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text(
                        '#${c['id']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      title: Text(c['proveedor'] as String),
                      subtitle: Text(
                        '${c['fecha'].toString().substring(0, 16).replaceAll('T', ' ')}'
                        '${credito ? ' · 📄 A crédito' : ''}',
                      ),
                      trailing: Text(
                        formatoUsd((c['total_usd'] as num).toDouble()),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => _detalleCompra(c['id'] as int),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
