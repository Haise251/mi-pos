import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../models/venta.dart';
import '../services/base_datos.dart';

class CuentasCobrarScreen extends StatefulWidget {
  const CuentasCobrarScreen({super.key});

  @override
  State<CuentasCobrarScreen> createState() => _CuentasCobrarScreenState();
}

class _CuentasCobrarScreenState extends State<CuentasCobrarScreen> {
  List<Map<String, dynamic>> _clientes = [];
  double _tasa = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _clientes = await BaseDatos.instancia.clientesConSaldo();
    _tasa = await BaseDatos.instancia.obtenerTasa();
    if (mounted) setState(() {});
  }

  Future<void> _nuevoCliente() async {
    final nombreCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo cliente'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombreCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: telCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await BaseDatos.instancia.insertarCliente(
        Cliente(nombre: nombreCtrl.text.trim(), telefono: telCtrl.text.trim()),
      );
      _cargar();
    }
  }

  Future<void> _abonar(
    Map<String, dynamic> credito,
    Map<String, dynamic> cliente,
  ) async {
    final ventaId = credito['venta_id'] as int;
    final total = (credito['total_usd'] as num).toDouble();
    final pagado = (credito['pagado_usd'] as num?)?.toDouble() ?? 0;
    final saldo = total - pagado;

    final montoCtrl = TextEditingController(text: saldo.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    var metodo = metodosPagoAbono.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setEstado) => AlertDialog(
          title: const Text('Registrar abono'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Saldo pendiente: ${formatoUsd(saldo)} · ${formatoBs(saldo * _tasa)}',
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
              child: const Text('Abonar'),
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

    await BaseDatos.instancia.registrarAbono(
      ventaId: ventaId,
      clienteId: cliente['cliente_id'] as int,
      montoUsd: monto,
      tasa: _tasa,
      metodo: metodo.id,
      referencia: referencia,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Abono de ${formatoUsd(monto)} registrado')),
    );
    Navigator.of(context).pop(); // cierra el detalle del cliente
    _cargar();
  }

  Future<void> _detalleCliente(Map<String, dynamic> cliente) async {
    final creditos = await BaseDatos.instancia.creditosDeCliente(
      cliente['cliente_id'] as int,
    );
    final abonos = await BaseDatos.instancia.abonosDeCliente(
      cliente['cliente_id'] as int,
    );
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            cliente['nombre'] as String,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (((cliente['telefono'] ?? '') as String).isNotEmpty)
            Text('📞 ${cliente['telefono']}'),
          const Divider(height: 24),
          const Text(
            'Créditos pendientes',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (creditos.isEmpty)
            const Text(
              'Sin créditos pendientes ✅',
              style: TextStyle(color: Colors.green),
            ),
          ...creditos.map((c) {
            final total = (c['total_usd'] as num).toDouble();
            final pagado = (c['pagado_usd'] as num?)?.toDouble() ?? 0;
            final saldo = total - pagado;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text(
                  'Venta #${c['venta_id']} · ${c['fecha'].toString().substring(0, 10)}',
                ),
                subtitle: Text(
                  'Total ${formatoUsd(total)} · Pagado ${formatoUsd(pagado)}',
                ),
                trailing: Text(
                  'Saldo ${formatoUsd(saldo)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                onTap: () => _abonar(c, cliente),
              ),
            );
          }),
          const Divider(height: 24),
          const Text(
            'Últimos abonos',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (abonos.isEmpty)
            const Text(
              'Sin abonos registrados',
              style: TextStyle(color: Colors.grey),
            ),
          ...abonos.map((a) {
            final m = metodoPorId(a['metodo'] as String);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(m?.icono ?? Icons.payments, size: 20),
              title: Text(
                'Venta #${a['venta_id']} · ${formatoUsd((a['monto_usd'] as num).toDouble())}',
              ),
              subtitle: Text(
                '${a['fecha'].toString().substring(0, 16).replaceAll('T', ' ')} · ${m?.nombre ?? a['metodo']}',
              ),
            );
          }),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Toca un crédito para registrar un abono',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conDeuda = _clientes
        .where((c) => ((c['saldo_usd'] as num?)?.toDouble() ?? 0) > 0.005)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text('Cuentas por cobrar ($conDeuda con saldo)')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoCliente,
        icon: const Icon(Icons.person_add),
        label: const Text('Cliente'),
      ),
      body: _clientes.isEmpty
          ? const Center(
              child: Text(
                'No hay clientes.\nCrea uno con el botón "Cliente" 👆',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _clientes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = _clientes[i];
                final saldo = (c['saldo_usd'] as num?)?.toDouble() ?? 0;
                final debe = saldo > 0.005;
                final nombre = (c['nombre'] ?? '') as String;
                final telefono = (c['telefono'] ?? '') as String;
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      nombre.isEmpty
                          ? '?'
                          : nombre.toUpperCase().substring(0, 1),
                    ),
                  ),
                  title: Text(nombre),
                  subtitle: telefono.isEmpty ? null : Text('📞 $telefono'),
                  trailing: debe
                      ? Column(
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
                        )
                      : const Text(
                          'Al día ✅',
                          style: TextStyle(fontSize: 12, color: Colors.green),
                        ),
                  onTap: () => _detalleCliente(c),
                );
              },
            ),
    );
  }
}
