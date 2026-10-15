import 'dart:io' show File;
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/producto.dart';
import 'base_datos.dart';

/// Exporta e importa respaldos en Excel (.xlsx).
///
/// El archivo tiene 3 hojas:
///   Productos: Código | Nombre | Precio USD | Stock | Stock Min | Ilimitado | Precio Bs
///   Clientes:  Nombre | Teléfono
///   Config:    Clave | Valor  (tasa, comisión, nombre del negocio)
///
/// La importación NO borra nada: crea lo que falta y actualiza lo existente.
class ExcelService {
  ExcelService._();
  static final ExcelService instancia = ExcelService._();

  // ---------- Exportar ----------

  Future<String?> exportarRespaldo() async {
    final productos =
    await BaseDatos.instancia.listar(incluirOcultos: true);
    final clientes = await BaseDatos.instancia.listarClientes();
    final tasa = await BaseDatos.instancia.obtenerTasa();
    final comision = await BaseDatos.instancia.obtenerComisionAvance();
    final negocio = await BaseDatos.instancia.obtenerNombreNegocio();

    final excel = Excel.createExcel();

    // Hoja Productos
    final shP = excel['Productos'];
    shP.appendRow(<CellValue?>[
       TextCellValue('Código'),
       TextCellValue('Nombre'),
       TextCellValue('Precio USD'),
       TextCellValue('Stock'),
       TextCellValue('Stock Min'),
       TextCellValue('Ilimitado'),
       TextCellValue('Precio Bs (ref)'),
    ]);
    for (final p in productos) {
      shP.appendRow(<CellValue?>[
        TextCellValue(p.codigo),
        TextCellValue(p.nombre),
        DoubleCellValue(p.precio),
        IntCellValue(p.stock),
        IntCellValue(p.stockMinimo),
        TextCellValue(p.stockIlimitado ? 'SI' : 'NO'),
        DoubleCellValue(p.precio * tasa),
      ]);
    }

    // Hoja Clientes
    final shC = excel['Clientes'];
    shC.appendRow(<CellValue?>[
       TextCellValue('Nombre'),
       TextCellValue('Teléfono'),
    ]);
    for (final c in clientes) {
      shC.appendRow(<CellValue?>[
        TextCellValue((c['nombre'] ?? '').toString()),
        TextCellValue((c['telefono'] ?? '').toString()),
      ]);
    }

    // Hoja Config
    final shK = excel['Config'];
    shK.appendRow(<CellValue?>[
       TextCellValue('Clave'),
       TextCellValue('Valor'),
    ]);
    shK.appendRow(<CellValue?>[
       TextCellValue('nombre_negocio'),
      TextCellValue(negocio),
    ]);
    shK.appendRow(<CellValue?>[
       TextCellValue('tasa_bs'),
      DoubleCellValue(tasa),
    ]);
    shK.appendRow(<CellValue?>[
      TextCellValue('comision_avance'),
      DoubleCellValue(comision),
    ]);

    // En excel 4.x el método para borrar hojas es "delete" (antes era "remove")
    try {
      excel.delete('Sheet1');
    } catch (_) {}

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo Excel');
    }

    String dos(int v) => v.toString().padLeft(2, '0');
    final f = DateTime.now();
    final nombre =
        'respaldo_mi_pos_${f.year}-${dos(f.month)}-${dos(f.day)}.xlsx';

    if (kIsWeb) {
      final ruta = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar respaldo de datos',
        fileName: nombre,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
      return ruta;
    }

    // Android / Windows / escritorio: pedimos la ruta y escribimos nosotros
    final ruta = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar respaldo de datos',
      fileName: nombre,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (ruta != null) {
      await File(ruta).writeAsBytes(Uint8List.fromList(bytes));
      await BaseDatos.instancia.registrarBitacora(
        'respaldo_excel',
        'Exportación: ${productos.length} productos, ${clientes.length} clientes',
      );
    }
    return ruta;
  }

  // ---------- Importar ----------

  Future<Map<String, dynamic>> importarRespaldo() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Abrir respaldo de datos',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return {'cancelado': true};
    final data = res.files.first.bytes;
    if (data == null) return {'error': 'No se pudo leer el archivo'};

    final excel = Excel.decodeBytes(data);
    var pCreados = 0, pActualizados = 0, pOmitidos = 0;
    var cCreados = 0, cActualizados = 0;
    double? tasa, comision;
    String? negocio;

    // --- Hoja Productos ---
    if (excel.tables.containsKey('Productos')) {
      final filas = excel.tables['Productos']!.rows;
      final inicio = _filaInicio(filas, 'cod');
      final productos = <Producto>[];
      for (var i = inicio; i < filas.length; i++) {
        final f = filas[i];
        final codigo = _celda(f, 0);
        final nombre = _celda(f, 1);
        final precio =
            double.tryParse(_celda(f, 2).replaceAll(',', '.')) ?? 0;
        final stock = int.tryParse(_celda(f, 3)) ?? 0;
        final stockMin = int.tryParse(_celda(f, 4)) ?? 5;
        final ilimitado = _celda(f, 5).toUpperCase().contains('S');
        if (nombre.isEmpty) {
          pOmitidos++;
          continue;
        }
        productos.add(Producto(
          codigo: codigo,
          nombre: nombre,
          precio: precio,
          stock: stock,
          stockMinimo: stockMin,
          stockIlimitado: ilimitado,
        ));
      }
      if (productos.isNotEmpty) {
        final r =
        await BaseDatos.instancia.importarProductos(productos);
        pCreados = r['creados'] ?? 0;
        pActualizados = r['actualizados'] ?? 0;
        pOmitidos += r['omitidos'] ?? 0;
      }
    }

    // --- Hoja Clientes ---
    if (excel.tables.containsKey('Clientes')) {
      final filas = excel.tables['Clientes']!.rows;
      final inicio = _filaInicio(filas, 'nom');
      final clientes = <Map<String, dynamic>>[];
      for (var i = inicio; i < filas.length; i++) {
        final f = filas[i];
        final nombre = _celda(f, 0);
        final telefono = _celda(f, 1);
        if (nombre.isEmpty) continue;
        clientes.add({'nombre': nombre, 'telefono': telefono});
      }
      if (clientes.isNotEmpty) {
        final r = await BaseDatos.instancia.importarClientes(clientes);
        cCreados = r['creados'] ?? 0;
        cActualizados = r['actualizados'] ?? 0;
      }
    }

    // --- Hoja Config ---
    if (excel.tables.containsKey('Config')) {
      final filas = excel.tables['Config']!.rows;
      final inicio = _filaInicio(filas, 'cla');
      for (var i = inicio; i < filas.length; i++) {
        final clave = _celda(filas[i], 0).toLowerCase();
        final valor = _celda(filas[i], 1);
        if (clave == 'tasa_bs') {
          tasa = double.tryParse(valor.replaceAll(',', '.'));
        } else if (clave == 'comision_avance') {
          comision = double.tryParse(valor.replaceAll(',', '.'));
        } else if (clave == 'nombre_negocio' && valor.isNotEmpty) {
          negocio = valor;
        }
      }
    }

    await BaseDatos.instancia.registrarBitacora(
      'respaldo_excel',
      'Importación: productos +$pCreados/~$pActualizados, clientes +$cCreados/~$cActualizados',
    );

    return {
      'productosCreados': pCreados,
      'productosActualizados': pActualizados,
      'productosOmitidos': pOmitidos,
      'clientesCreados': cCreados,
      'clientesActualizados': cActualizados,
      'tasa': tasa,
      'comision': comision,
      'nombre': negocio,
    };
  }

  // ---------- Helpers de lectura ----------

  /// Si la primera fila es encabezado, empieza a leer desde la segunda.
  int _filaInicio(List<List<Data?>> filas, String pista) {
    if (filas.isEmpty) return 0;
    final primera = _celda(filas.first, 0).toLowerCase();
    return primera.contains(pista) ? 1 : 0;
  }

  String _celda(List<Data?> fila, int i) {
    if (i >= fila.length) return '';
    final v = fila[i]?.value;
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString().trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return v.toString();
  }
}