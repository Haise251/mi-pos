import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'base_datos.dart';

class EstadoLicencia {
  final bool licenciada;
  final bool expirada;
  final bool permanente;
  final int diasTrialRestantes;
  final DateTime? vence;

  const EstadoLicencia({
    required this.licenciada,
    this.expirada = false,
    this.permanente = false,
    this.diasTrialRestantes = 0,
    this.vence,
  });
}

class LicenciaService {
  // ⚠️ CAMBIA este secreto por el tuyo ANTES de compilar la versión final.
  // Debe ser el MISMO secreto en tool/generar_licencia.dart
  static const String _secreto = 'CAMBIA-ESTE-SECRETO-MIPOS-2025';
  static const int diasTrial = 14;

  static final _regex = RegExp(r'^[0-9A-F]{16}$');

  static String _firma(String diasHex) => Hmac(
    sha256,
    utf8.encode(_secreto),
  ).convert(utf8.encode(diasHex)).toString().substring(0, 8).toUpperCase();

  static String? normalizarClave(String entrada) {
    final limpia = entrada.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    return _regex.hasMatch(limpia) ? limpia : null;
  }

  static Future<bool> claveEsValida(String clave) async {
    final diasHex = clave.substring(0, 8);
    return clave.substring(8, 16) == _firma(diasHex);
  }

  static DateTime? _vencimientoDe(String clave) {
    final dias = int.parse(clave.substring(0, 8), radix: 16);
    if (dias == 0) return null; // licencia permanente
    return DateTime.utc(1970).add(Duration(days: dias));
  }

  Future<EstadoLicencia> verificar() async {
    final bd = BaseDatos.instancia;
    final clave = await bd.getConfig('licencia_clave');

    if (clave != null && await claveEsValida(clave)) {
      final vence = _vencimientoDe(clave);
      final expirada =
          vence != null &&
          DateTime.now().isAfter(vence.add(const Duration(days: 1)));
      return EstadoLicencia(
        licenciada: true,
        permanente: vence == null,
        expirada: expirada,
        vence: vence,
      );
    }

    // Trial: 14 días desde la primera ejecución
    var primera = await bd.getConfig('primera_ejecucion');
    if (primera == null) {
      primera = DateTime.now().toIso8601String();
      await bd.setConfig('primera_ejecucion', primera);
    }
    final usados = DateTime.now().difference(DateTime.parse(primera)).inDays;
    final restantes = diasTrial - usados;
    return EstadoLicencia(
      licenciada: false,
      expirada: restantes <= 0,
      diasTrialRestantes: restantes < 0 ? 0 : restantes,
    );
  }

  Future<bool> activar(String claveIngresada) async {
    final clave = normalizarClave(claveIngresada);
    if (clave == null || !await claveEsValida(clave)) return false;
    await BaseDatos.instancia.setConfig('licencia_clave', clave);
    await BaseDatos.instancia.registrarBitacora(
      'licencia',
      'Licencia activada: $clave',
    );
    return true;
  }
}
