// Generador de claves — SOLO para ti, nunca lo incluyas en la app publicada.
//
// Uso desde la carpeta del proyecto (Windows):
//   dart run tool/generar_licencia.dart 2027-12-31   → vence esa fecha
//   dart run tool/generar_licencia.dart 0            → permanente
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

// ⚠️ El MISMO secreto que en lib/services/licencia_service.dart
const String secreto = 'CAMBIA-ESTE-SECRETO-MIPOS-2025';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Uso: dart run tool/generar_licencia.dart <YYYY-MM-DD | 0>');
    exit(1);
  }

  int dias;
  if (args[0] == '0') {
    dias = 0;
  } else {
    final partes = args[0].split('-');
    final fecha = DateTime.utc(
      int.parse(partes[0]),
      int.parse(partes[1]),
      int.parse(partes[2]),
    );
    dias = fecha.difference(DateTime.utc(1970)).inDays;
  }

  final diasHex = dias.toRadixString(16).padLeft(8, '0').toUpperCase();
  final firma = Hmac(
    sha256,
    utf8.encode(secreto),
  ).convert(utf8.encode(diasHex)).toString().substring(0, 8).toUpperCase();
  final clave = '$diasHex$firma';
  print(
    'Clave: ${clave.substring(0, 4)}-${clave.substring(4, 8)}-'
    '${clave.substring(8, 12)}-${clave.substring(12, 16)}',
  );
}
