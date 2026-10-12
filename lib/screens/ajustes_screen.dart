import 'package:flutter/material.dart';

import '../services/base_datos.dart';
import '../services/tasa_service.dart';
import 'bitacora_screen.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _tasaCtrl = TextEditingController();
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _tasaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    _nombreCtrl.text = await BaseDatos.instancia.obtenerNombreNegocio();
    final tasa = await BaseDatos.instancia.obtenerTasa();
    _tasaCtrl.text = tasa.toString();
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final tasa = double.parse(_tasaCtrl.text.replaceAll(',', '.'));
    // Guarda en BD y notifica a todo el sistema al instante (también queda en bitácora)
    await TasaService.guardar(tasa);
    await BaseDatos.instancia.guardarNombreNegocio(_nombreCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✅ Ajustes guardados')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Configuración general',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nombreCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nombre del negocio',
                              prefixIcon: Icon(Icons.store),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requerido'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _tasaCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Tasa: Bs por 1 \$',
                              prefixIcon: Icon(Icons.currency_exchange),
                              suffixText: 'Bs/\$',
                              border: OutlineInputBorder(),
                              helperText:
                                  'Se usa para calcular todas las referencias en Bs',
                            ),
                            validator: (v) {
                              final t = double.tryParse(
                                v?.replaceAll(',', '.') ?? '',
                              );
                              if (t == null || t <= 0) {
                                return 'Ingresa una tasa válida mayor a 0';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _guardar,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Guardar cambios'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // ---------- Bitácora ----------
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Registro de actividad'),
                    subtitle: const Text(
                      'Bitácora de ventas, compras, usuarios y cambios del sistema',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BitacoraScreen()),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Los precios se definen y registran en dólares (\$). '
                    'Los montos en Bs son referencia calculada con la tasa actual. '
                    'La tasa de cada venta queda guardada en el histórico.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }
}
