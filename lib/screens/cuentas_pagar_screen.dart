import 'package:flutter/material.dart';

import '../models/venta.dart';
import '../services/base_datos.dart';

class CuentasPagarScreen extends StatefulWidget {
  const CuentasPagarScreen({super.key});

  @override
  State<CuentasPagarScreen> createState() => _CuentasPagarScreenState();
}

class _CuentasPagarScreenState extends State<CuentasPagarScreen> {
  List<Map<String, dynamic>> _compras = [];
  double _tasa = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _compras = await BaseDatos.instancia.comprasConSaldo();
    _tasa = await BaseDatos.instancia.obtenerTasa();
    if (mounted) setState(() {});
  }

  double get _totalPendiente => _compras.fold<double>(
    0,
    (s, c) => s + ((c['saldo_usd'] as num?)?.toDouble() ?? 0),
  );

  Future<void> _pagar(Map<String, dynamic> compra) async {
    final compraId = compra['compra_id'] as int;
    final saldo = (compra['saldo_usd'] as num?)?.toDouble() ?? 0;

    final montoCtrl = TextEditingController(text: saldo.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    var metodo = metodosPagoAbono.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setEstado) => AlertDialog(
          title: const Text('Pagar a proveedor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Proveedor: ${compra['proveedor']}\n'
                'Saldo pendiente: ${formatoUsd(saldo)} · ${formatoBs(saldo * _tasa)}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: metodosPagoAbono
                    .map(
                      (m) => ChoiceChip(
                        avatar: Icon(m.icono, size: 18),
                        label: Text(
                          m.nombre,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: metodo.id == m.id,
                        onSelected: (_) => setEstado(() => metodo = m),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Monto en \$',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Referencia (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar pago'),
            ),
          ],
        ),
      ),
    );

    final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
    final referencia = refCtrl.text.trim();
    montoCtrl.dispose();
    refCtrl.dispose();

    if (ok != true || monto <= 0) return;

    await BaseDatos.instancia.registrarPagoCompra(
      compraId: compraId,
      montoUsd: monto,
      tasa: _tasa,
      metodo: metodo.id,
      referencia: referencia,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Pago de ${formatoUsd(monto)} a ${compra['proveedor']} registrado',
        ),
      ),
    );
    _cargar();
  }

  Future<void> _detalleCompra(Map<String, dynamic> compra) async {
    final compraId = compra['compra_id'] as int;
    final det = await BaseDatos.instancia.detalleCompra(compraId);
    final pagos = await BaseDatos.instancia.pagosDeCompra(compraId);
    if (!mounted || det == null) return;
    final items = (det['items'] as List).cast<Map<String, dynamic>>();
    final saldo = (compra['saldo_usd'] as num?)?.toDouble() ?? 0;
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
                'Total de la compra',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(formatoUsd((compra['total_usd'] as num).toDouble())),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pagado',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(formatoUsd((compra['pagado_usd'] as num?)?.toDouble() ?? 0)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Saldo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                formatoUsd(saldo),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          const Text(
            'Pagos realizados',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (pagos.isEmpty)
            const Text(
              'Aún no hay pagos',
              style: TextStyle(color: Colors.grey),
            ),
          ...pagos.map((p) {
            final m = metodoPorId(p['metodo'] as String);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(m?.icono ?? Icons.payments, size: 20),
              title: Text(formatoUsd((p['monto_usd'] as num).toDouble())),
              subtitle: Text(
                '${p['fecha'].toString().substring(0, 16).replaceAll('T', ' ')} · ${m?.nombre ?? p['metodo']}',
              ),
            );
          }),
          const SizedBox(height: 12),
          if (saldo > 0.005)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _pagar(compra);
              },
              icon: const Icon(Icons.payment),
              label: const Text('Registrar pago'),
            )
          else
            const Center(
              child: Text(
                '✅ Compra saldada',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cuentas por pagar (${_compras.length} · ${formatoUsd(_totalPendiente)})',
        ),
      ),
      body: _compras.isEmpty
          ? const Center(
              child: Text(
                'No hay compras a crédito pendientes ✅\n\n'
                'En "Compras" activa la opción "A crédito" para\n'
                'que aparezcan aquí.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _compras.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = _compras[i];
                final saldo = (c['saldo_usd'] as num?)?.toDouble() ?? 0;
                return ListTile(
                  leading: Text(
                    '#${c['compra_id']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  title: Text(c['proveedor'] as String),
                  subtitle: Text(
                    c['fecha'].toString().substring(0, 16).replaceAll('T', ' '),
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatoUsd(saldo),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      Text(
                        formatoBs(saldo * _tasa),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _detalleCompra(c),
                );
              },
            ),
    );
  }
}
