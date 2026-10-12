import 'package:flutter/material.dart';

import '../services/licencia_service.dart';
import 'login_screen.dart';

class LicenciaScreen extends StatefulWidget {
  final bool modoBloqueo; // true = app bloqueada (desde el arranque)
  const LicenciaScreen({super.key, this.modoBloqueo = false});

  @override
  State<LicenciaScreen> createState() => _LicenciaScreenState();
}

class _LicenciaScreenState extends State<LicenciaScreen> {
  final _claveCtrl = TextEditingController();
  EstadoLicencia? _estado;
  bool _activando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _estado = await LicenciaService().verificar();
    if (mounted) setState(() {});
  }

  Future<void> _activar() async {
    setState(() => _activando = true);
    final ok = await LicenciaService().activar(_claveCtrl.text);
    if (!mounted) return;
    setState(() => _activando = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Licencia activada correctamente')),
      );
      if (widget.modoBloqueo) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } else {
        Navigator.pop(context);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Clave inválida, verifica e intenta de nuevo'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    return PopScope(
      canPop: !widget.modoBloqueo,
      child: Scaffold(
        appBar: widget.modoBloqueo
            ? null
            : AppBar(title: const Text('Licencia')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        e == null
                            ? Icons.autorenew
                            : (e.expirada
                                  ? Icons.block
                                  : (e.licenciada
                                        ? Icons.verified
                                        : Icons.hourglass_bottom)),
                        size: 56,
                        color: e != null && e.expirada
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      if (e == null)
                        const Center(child: CircularProgressIndicator())
                      else if (e.expirada)
                        const Text(
                          'Tu periodo de prueba ha terminado.\n'
                          'Ingresa una clave de licencia para continuar.',
                          textAlign: TextAlign.center,
                        ),
                      if (e != null && e.licenciada && !e.expirada)
                        Text(
                          e.permanente
                              ? '✅ Licencia permanente activa'
                              : '✅ Licencia activa hasta '
                                    '${e.vence!.day}/${e.vence!.month}/${e.vence!.year}',
                          textAlign: TextAlign.center,
                        ),
                      if (e != null && !e.licenciada && !e.expirada)
                        Text(
                          '🧪 Te quedan ${e.diasTrialRestantes} días de prueba.\n'
                          'Activa tu licencia cuando quieras.',
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _claveCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Clave de licencia',
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _activando ? null : _activar,
                        icon: _activando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.key),
                        label: const Text('Activar licencia'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
