import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Pantalla de escaneo con cámara.
///
/// Modo puntual (default): devuelve el primer código leído y se cierra.
///
/// Modo continuo (continuo: true + onCodigo): permanece abierta y cada vez
/// que detecta un código llama a onCodigo. El callback devuelve el nombre
/// del producto agregado (o null si no se encontró) para mostrar feedback.
/// Incluye cooldown de 2.5 s por código para evitar lecturas duplicadas.
class EscanerCamaraScreen extends StatefulWidget {
  final bool continuo;
  final Future<String?> Function(String codigo)? onCodigo;

  const EscanerCamaraScreen({super.key, this.continuo = false, this.onCodigo});

  @override
  State<EscanerCamaraScreen> createState() => _EscanerCamaraScreenState();
}

class _EscanerCamaraScreenState extends State<EscanerCamaraScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _procesando = false;
  bool _cerrando = false;
  String? _ultimoCodigo;
  DateTime _ultimoTiempo = DateTime.fromMillisecondsSinceEpoch(0);
  int _agregados = 0;
  String? _feedback; // null = oculto
  bool _feedbackOk = false;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _alDetectar(BarcodeCapture captura) async {
    if (_procesando || _cerrando) return;

    String? codigo;
    for (final b in captura.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        codigo = v.trim();
        break;
      }
    }
    if (codigo == null) return;

    // Cooldown: el mismo código solo se procesa cada 2.5 s
    final ahora = DateTime.now();
    final esMismo = codigo == _ultimoCodigo;
    final dentroCooldown =
        ahora.difference(_ultimoTiempo) < const Duration(milliseconds: 2500);
    if (esMismo && dentroCooldown) return;

    _ultimoCodigo = codigo;
    _ultimoTiempo = ahora;

    if (!widget.continuo) {
      _cerrando = true;
      Navigator.pop(context, codigo);
      return;
    }

    _procesando = true;
    final nombre = await widget.onCodigo?.call(codigo);
    _procesando = false;
    if (!mounted) return;
    _feedbackTimer?.cancel();
    setState(() {
      _feedbackOk = nombre != null;
      _feedback = _feedbackOk
          ? '✅ $nombre'
          : '⚠️ Código $codigo no encontrado';
      if (_feedbackOk) _agregados++;
    });
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.continuo ? 'Lector continuo' : 'Escanear con cámara',
        ),
        actions: [
          IconButton(
            tooltip: 'Alternar cámara',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () async {
              try {
                await _controller.switchCamera();
              } catch (_) {}
            },
          ),
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flash_on),
            onPressed: () async {
              try {
                await _controller.toggleTorch();
              } catch (_) {}
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _alDetectar,
          ),
          Center(
            child: Container(
              width: 300,
              height: 170,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.teal, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (widget.continuo)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _feedback == null
                      ? const SizedBox.shrink()
                      : Container(
                    key: ValueKey(_feedback),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _feedbackOk
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _feedback!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.continuo)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🛒 $_agregados producto(s) agregado(s)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal.shade800,
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Listo, volver a la venta'),
                    ),
                  ],
                ),
              ),
            )
          else
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Apunta la cámara al código de barras',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}