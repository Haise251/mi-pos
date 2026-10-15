import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'base_datos.dart';

/// Respaldos locales de la base de datos completa (.db).
///
/// - Exportar: copia pos.db a una carpeta elegida con nombre fechado.
/// - Restaurar: cierra la BD activa, copia el respaldo por encima y reabre.
///
/// La restauración reemplaza TODO el contenido actual de la base de datos.
class RespaldoService {
  RespaldoService._();
  static final RespaldoService instancia = RespaldoService._();

  static const String _nombreBd = 'pos.db';

  // ---------- Exportar ----------

  /// Copia la base de datos actual a la carpeta que el usuario elija.
  /// Devuelve null si canceló, o la ruta donde quedó el respaldo.
  Future<String?> exportar() async {
    // Aseguramos que no queden transacciones pendientes en disco
    final dbActiva = await BaseDatos.instancia.bdParaRespaldo();
    await dbActiva.execute('PRAGMA wal_checkpoint(FULL)');

    final dirBd = await getDatabasesPath();
    final origen = File(p.join(dirBd, _nombreBd));
    if (!origen.existsSync()) {
      throw Exception('No existe la base de datos aún.');
    }

    final ahora = DateTime.now();
    String dos(int v) => v.toString().padLeft(2, '0');
    final nombre =
        'pos_respaldo_${ahora.year}-${dos(ahora.month)}-${dos(ahora.day)}_'
        '${dos(ahora.hour)}-${dos(ahora.minute)}.db';

    final ruta = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar respaldo local de la base de datos',
      fileName: nombre,
      type: FileType.any,
    );
    if (ruta == null) return null;

    // En Android a veces saveFile devuelve una ruta de contenido que
    // necesita escritura vía bytes; usamos copy con manejo seguro.
    final destino = File(ruta);
    try {
      await origen.copy(ruta);
    } catch (_) {
      final bytes = await origen.readAsBytes();
      await destino.writeAsBytes(bytes, flush: true);
    }

    await BaseDatos.instancia.registrarBitacora(
      'respaldo_local',
      'Copia de la BD guardada en: $ruta',
    );
    return ruta;
  }

  // ---------- Restaurar ----------

  /// Permite elegir un archivo .db y lo restaura como base de datos activa.
  /// Devuelve un mensaje de éxito o lanza excepción con el motivo.
  Future<String> restaurar() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Elegir respaldo de base de datos (.db)',
      type: FileType.any,
      withData: false,
    );
    if (res == null || res.files.isEmpty) {
      throw Exception('Operación cancelada.');
    }
    final rutaOrigen = res.files.single.path;
    if (rutaOrigen == null || rutaOrigen.isEmpty) {
      throw Exception('No se pudo acceder al archivo seleccionado.');
    }

    final origen = File(rutaOrigen);
    if (!origen.existsSync()) {
      throw Exception('El archivo ya no existe.');
    }

    // Validación mínima: debe parecer una SQLite (el header empieza con
    // "SQLite format 3")
    final header = await origen.openRead(0, 16).join();
    if (!header.contains('SQLite format 3')) {
      throw Exception(
        'El archivo no parece una base de datos SQLite válida.',
      );
    }

    // Cerramos la BD activa para liberar el archivo
    await BaseDatos.instancia.cerrar();

    final dirBd = await getDatabasesPath();
    final destino = p.join(dirBd, _nombreBd);

    // Eliminamos también los archivos wal/shm viejos para no mezclar datos
    final wal = File('$destino-wal');
    final shm = File('$destino-shm');
    if (wal.existsSync()) await wal.delete();
    if (shm.existsSync()) await shm.delete();

    await origen.copy(destino);

    await BaseDatos.instancia.registrarBitacora(
      'respaldo_local',
      'Base de datos restaurada desde: $rutaOrigen',
    );
    return 'Base de datos restaurada correctamente. '
        'Todos los datos provienen ahora del respaldo seleccionado.';
  }
}