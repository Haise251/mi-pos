import 'package:flutter/foundation.dart';

import 'base_datos.dart';

/// Tasa Bs/$ global. Al guardar, notifica a TODAS las pantallas en vivo.
class TasaService {
  TasaService._();

  static final ValueNotifier<double> tasa = ValueNotifier(0);

  /// Carga la tasa guardada (se llama al arrancar la app, en main()).
  static Future<void> cargar() async {
    tasa.value = await BaseDatos.instancia.obtenerTasa();
  }

  /// Guarda en BD y notifica al instante a todo el sistema.
  static Future<void> guardar(double nueva) async {
    await BaseDatos.instancia.guardarTasa(nueva);
    tasa.value = nueva; // ← todos los listeners se enteran aquí
  }
}
