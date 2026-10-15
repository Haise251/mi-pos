import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cliente.dart';
import '../models/compra.dart';
import '../models/producto.dart';
import '../models/usuario.dart';
import '../models/venta.dart';
import 'sesion.dart';

class BaseDatos {
  BaseDatos._();
  static final BaseDatos instancia = BaseDatos._();

  Database? _db;

  Future<Database> get _bd async {
    if (_db != null) return _db!;
    final ruta = join(await getDatabasesPath(), 'pos.db');
    _db = await openDatabase(
      ruta,
      version: 7,
      onCreate: _alCrear,
      onUpgrade: _alActualizar,
    );
    return _db!;
  }

  // ---------- Creación / migración ----------

  Future<void> _alCrear(Database db, int version) async {
    await _crearTablas(db);
    await _sembrarAdmin(db);
  }

  Future<void> _alActualizar(Database db, int oldV, int newV) async {
    await _crearTablas(db);
    await _sembrarAdmin(db);
  }

  Future<void> _crearTablas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS productos (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo          TEXT UNIQUE,
        nombre          TEXT NOT NULL,
        precio          REAL NOT NULL,
        stock           INTEGER NOT NULL DEFAULT 0,
        stock_minimo    INTEGER NOT NULL DEFAULT 5,
        stock_ilimitado INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usuarios (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre    TEXT NOT NULL,
        usuario   TEXT UNIQUE NOT NULL,
        salt      TEXT NOT NULL,
        hash      TEXT NOT NULL,
        rol       TEXT NOT NULL DEFAULT 'cajero',
        activo    INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS movimientos (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        producto_id      INTEGER NOT NULL,
        tipo             TEXT NOT NULL,
        cantidad         INTEGER NOT NULL,
        stock_resultante INTEGER,
        usuario_id       INTEGER,
        referencia       TEXT,
        fecha            TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS configuracion (
        clave TEXT PRIMARY KEY,
        valor TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ventas (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha       TEXT NOT NULL,
        usuario_id  INTEGER,
        cliente_id  INTEGER,
        estado_pago TEXT NOT NULL DEFAULT 'pagada',
        total_usd   REAL NOT NULL,
        tasa        REAL NOT NULL,
        total_bs    REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS venta_detalle (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id        INTEGER NOT NULL,
        producto_id     INTEGER NOT NULL,
        nombre_producto TEXT NOT NULL,
        cantidad        INTEGER NOT NULL,
        precio_usd      REAL NOT NULL,
        subtotal_usd    REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS venta_pagos (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id   INTEGER NOT NULL,
        metodo     TEXT NOT NULL,
        monto_usd  REAL NOT NULL,
        monto_bs   REAL NOT NULL,
        referencia TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS compras (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha       TEXT NOT NULL,
        proveedor   TEXT NOT NULL,
        estado_pago TEXT NOT NULL DEFAULT 'pagada',
        total_usd   REAL NOT NULL,
        tasa        REAL NOT NULL,
        total_bs    REAL NOT NULL,
        usuario_id  INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS compra_detalle (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        compra_id       INTEGER NOT NULL,
        producto_id     INTEGER NOT NULL,
        nombre_producto TEXT NOT NULL,
        cantidad        INTEGER NOT NULL,
        costo_usd       REAL NOT NULL,
        subtotal_usd    REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clientes (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre    TEXT NOT NULL,
        telefono  TEXT,
        creado_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS abonos (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id   INTEGER NOT NULL,
        cliente_id INTEGER NOT NULL,
        monto_usd  REAL NOT NULL,
        monto_bs   REAL NOT NULL,
        tasa       REAL NOT NULL,
        metodo     TEXT NOT NULL,
        referencia TEXT,
        fecha      TEXT NOT NULL,
        usuario_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pagos_compra (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        compra_id  INTEGER NOT NULL,
        monto_usd  REAL NOT NULL,
        monto_bs   REAL NOT NULL,
        tasa       REAL NOT NULL,
        metodo     TEXT NOT NULL,
        referencia TEXT,
        fecha      TEXT NOT NULL,
        usuario_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bitacora (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha      TEXT NOT NULL,
        usuario_id INTEGER,
        accion     TEXT NOT NULL,
        detalle    TEXT
      )
    ''');
    try {
      await db.execute(
        'ALTER TABLE productos ADD COLUMN stock_minimo INTEGER NOT NULL DEFAULT 5',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE productos ADD COLUMN stock_ilimitado INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE ventas ADD COLUMN cliente_id INTEGER');
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE ventas ADD COLUMN estado_pago TEXT NOT NULL DEFAULT 'pagada'",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE compras ADD COLUMN estado_pago TEXT NOT NULL DEFAULT 'pagada'",
      );
    } catch (_) {}
  }

  Future<void> _sembrarAdmin(Database db) async {
    final n =
        Sqflite.firstIntValue(
          await db.query('usuarios', columns: ['COUNT(*)']),
        ) ??
            0;
    if (n > 0) return;
    final salt = _saltAleatorio();
    await db.insert('usuarios', {
      'nombre': 'Administrador',
      'usuario': 'admin',
      'salt': salt,
      'hash': _hashear(salt, 'admin123'),
      'rol': 'admin',
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  // ---------- Bitácora ----------

  Future<void> registrarBitacora(String accion, [String? detalle]) async {
    await (await _bd).insert('bitacora', {
      'fecha': DateTime.now().toIso8601String(),
      'usuario_id': SesionActual.usuarioId,
      'accion': accion,
      'detalle': detalle,
    });
  }

  Future<void> _bitacoraTxn(
      Transaction txn,
      String accion, [
        String? detalle,
      ]) async {
    await txn.insert('bitacora', {
      'fecha': DateTime.now().toIso8601String(),
      'usuario_id': SesionActual.usuarioId,
      'accion': accion,
      'detalle': detalle,
    });
  }

  Future<List<Map<String, dynamic>>> listarBitacora({int limite = 300}) async {
    final db = await _bd;
    return db.rawQuery(
      '''
      SELECT b.*, u.nombre AS usuario
      FROM bitacora b
      LEFT JOIN usuarios u ON u.id = b.usuario_id
      ORDER BY b.id DESC LIMIT ?
    ''',
      [limite],
    );
  }

  // ---------- Productos ----------

  Future<List<Producto>> listar({
    String filtro = '',
    bool incluirOcultos = false,
  }) async {
    final db = await _bd;
    final f = filtro.trim();
    final excluirCond = incluirOcultos ? '1=1' : "codigo != '0000001'";
    if (f.isEmpty) {
      final filas = await db.query(
        'productos',
        where: excluirCond,
        orderBy: 'nombre',
      );
      return filas.map(Producto.fromMap).toList();
    }
    final filas = await db.query(
      'productos',
      where:
      '$excluirCond AND (nombre LIKE ? OR (codigo IS NOT NULL AND codigo != "" AND codigo LIKE ?))',
      whereArgs: ['%$f%', '%$f%'],
      orderBy: 'nombre',
    );
    return filas.map(Producto.fromMap).toList();
  }

  /// Genera variantes de un código de barras para búsqueda tolerante:
  /// UPC-A (12 dígitos) ↔ EAN-13 (el mismo código con 0 adelante).
  List<String> _variantesCodigo(String codigo) {
    final c = codigo.trim();
    final variantes = <String>[c];
    if (c.isEmpty || !RegExp(r'^\d+$').hasMatch(c)) return variantes;
    if (c.length == 12) {
      variantes.add('0$c');
    } else if (c.length == 13 && c.startsWith('0')) {
      variantes.add(c.substring(1));
    }
    return variantes;
  }

  Future<Producto?> buscarPorCodigo(String codigo) async {
    final candidatos = await buscarCandidatos(codigo);
    return candidatos.length == 1 ? candidatos.first : null;
  }

  /// Devuelve TODOS los productos que coinciden (exacto, variante UPC/EAN
  /// o parcial). Sirve para mostrar un selector cuando el lector trunca
  /// el código y la coincidencia es ambigua.
  Future<List<Producto>> buscarCandidatos(String codigo) async {
    final variantes = _variantesCodigo(codigo);
    final db = await _bd;

    for (final c in variantes) {
      final filas = await db.query(
        'productos',
        where: 'codigo = ?',
        whereArgs: [c],
        limit: 1,
      );
      if (filas.isNotEmpty) return [Producto.fromMap(filas.first)];
    }

    final limpio = codigo.trim();
    if (limpio.length >= 8 && RegExp(r'^\d+$').hasMatch(limpio)) {
      final filas = await db.query(
        'productos',
        where: "codigo IS NOT NULL AND codigo != '' AND codigo != '0000001' "
            'AND (codigo LIKE ? OR codigo LIKE ?)',
        whereArgs: ['$limpio%', '%$limpio'],
        limit: 12,
      );
      final vistos = <int>{};
      final out = <Producto>[];
      for (final f in filas) {
        final p = Producto.fromMap(f);
        if (p.id != null && vistos.add(p.id!)) out.add(p);
      }
      return out;
    }
    return [];
  }

  Future<int> guardar(Producto p) async {
    final db = await _bd;
    final mapa = p.toMap()..removeWhere((k, v) => k == 'id' && v == null);
    final id = p.id == null
        ? await db.insert('productos', mapa)
        : await db.update(
      'productos',
      mapa,
      where: 'id = ?',
      whereArgs: [p.id],
    );
    await registrarBitacora(
      p.id == null ? 'producto_crear' : 'producto_editar',
      '${p.nombre} · \$${p.precio.toStringAsFixed(2)}',
    );
    return id;
  }

  Future<int> eliminar(int id) async {
    final db = await _bd;
    final filas = await db.query(
      'productos',
      columns: ['nombre'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final n = await db.delete('productos', where: 'id = ?', whereArgs: [id]);
    if (n > 0) {
      await registrarBitacora(
        'producto_eliminar',
        filas.isNotEmpty ? filas.first['nombre'] as String : 'ID $id',
      );
    }
    return n;
  }

  Future<void> vaciarProductos() async {
    final db = await _bd;
    final n =
        Sqflite.firstIntValue(
          await db.query('productos', columns: ['COUNT(*)']),
        ) ??
            0;
    await db.delete('productos');
    await db.rawDelete(
      'DELETE FROM movimientos WHERE producto_id NOT IN (SELECT id FROM productos)',
    );
    await registrarBitacora('producto_vaciar', 'Se eliminaron $n productos');
  }

  Future<void> ajustarStock(
      int id,
      int delta, {
        String tipo = 'salida',
        String? referencia,
        int? usuarioId,
      }) async {
    final db = await _bd;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE productos SET stock = stock + ? WHERE id = ? AND (stock_ilimitado IS NULL OR stock_ilimitado = 0)',
        [delta, id],
      );
      final filas = await txn.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.insert('movimientos', {
        'producto_id': id,
        'tipo': tipo,
        'cantidad': delta.abs(),
        'stock_resultante': filas.isNotEmpty ? filas.first['stock'] : null,
        'usuario_id': usuarioId ?? SesionActual.usuarioId,
        'referencia': referencia,
        'fecha': DateTime.now().toIso8601String(),
      });
      await _bitacoraTxn(
        txn,
        'stock_ajuste',
        '$tipo de ${delta.abs()}${referencia != null ? ' · $referencia' : ''}',
      );
    });
  }

  Future<List<Map<String, dynamic>>> listarMovimientos({
    int? productoId,
    int limite = 200,
  }) async {
    final db = await _bd;
    return db.rawQuery(
      '''
      SELECT m.*, p.nombre AS producto, u.nombre AS usuario
      FROM movimientos m
      LEFT JOIN productos p ON p.id = m.producto_id
      LEFT JOIN usuarios u ON u.id = m.usuario_id
      ${productoId != null ? 'WHERE m.producto_id = ?' : ''}
      ORDER BY m.id DESC LIMIT ?
    ''',
      [?productoId, limite],
    );
  }

  // ---------- Ventas ----------

  Future<int> registrarVenta({
    required List<ItemVenta> items,
    required List<Pago> pagos,
    required double tasa,
    int? clienteId,
  }) async {
    final db = await _bd;
    final totalUsd = items.fold<double>(0, (s, i) => s + i.subtotalUsd);
    final esCredito = pagos.any((p) => p.metodo == 'credito');
    return db.transaction((txn) async {
      final ventaId = await txn.insert('ventas', {
        'fecha': DateTime.now().toIso8601String(),
        'usuario_id': SesionActual.usuarioId,
        'cliente_id': esCredito ? clienteId : null,
        'estado_pago': esCredito ? 'credito' : 'pagada',
        'total_usd': totalUsd,
        'tasa': tasa,
        'total_bs': totalUsd * tasa,
      });
      for (final i in items) {
        await txn.insert('venta_detalle', {
          'venta_id': ventaId,
          'producto_id': i.productoId,
          'nombre_producto': i.nombre,
          'cantidad': i.cantidad,
          'precio_usd': i.precioUsd,
          'subtotal_usd': i.subtotalUsd,
        });
        await txn.rawUpdate(
          'UPDATE productos SET stock = stock - ? WHERE id = ? AND (stock_ilimitado IS NULL OR stock_ilimitado = 0)',
          [i.cantidad, i.productoId],
        );
        final filas = await txn.query(
          'productos',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [i.productoId],
          limit: 1,
        );
        await txn.insert('movimientos', {
          'producto_id': i.productoId,
          'tipo': 'salida',
          'cantidad': i.cantidad,
          'stock_resultante': filas.isNotEmpty ? filas.first['stock'] : null,
          'usuario_id': SesionActual.usuarioId,
          'referencia': 'Venta #$ventaId',
          'fecha': DateTime.now().toIso8601String(),
        });
      }
      for (final p in pagos) {
        await txn.insert('venta_pagos', {
          'venta_id': ventaId,
          'metodo': p.metodo,
          'monto_usd': p.montoUsd,
          'monto_bs': p.montoBs,
          'referencia': p.referencia,
        });
      }
      await _bitacoraTxn(
        txn,
        'venta',
        'Venta #$ventaId · \$${totalUsd.toStringAsFixed(2)}${esCredito ? ' (con crédito)' : ''}',
      );
      return ventaId;
    });
  }

  Future<Map<String, dynamic>?> detalleVenta(int ventaId) async {
    final db = await _bd;
    final venta = await db.query(
      'ventas',
      where: 'id = ?',
      whereArgs: [ventaId],
      limit: 1,
    );
    if (venta.isEmpty) return null;
    final items = await db.query(
      'venta_detalle',
      where: 'venta_id = ?',
      whereArgs: [ventaId],
    );
    final pagos = await db.query(
      'venta_pagos',
      where: 'venta_id = ?',
      whereArgs: [ventaId],
    );
    return {'venta': venta.first, 'items': items, 'pagos': pagos};
  }

  // ---------- Compras ----------

  Future<int> registrarCompra({
    required String proveedor,
    required List<ItemCompra> items,
    required double tasa,
    bool aCredito = false,
  }) async {
    final db = await _bd;
    final totalUsd = items.fold<double>(0, (s, i) => s + i.subtotalUsd);
    return db.transaction((txn) async {
      final compraId = await txn.insert('compras', {
        'fecha': DateTime.now().toIso8601String(),
        'proveedor': proveedor,
        'estado_pago': aCredito ? 'credito' : 'pagada',
        'total_usd': totalUsd,
        'tasa': tasa,
        'total_bs': totalUsd * tasa,
        'usuario_id': SesionActual.usuarioId,
      });
      for (final i in items) {
        await txn.insert('compra_detalle', {
          'compra_id': compraId,
          'producto_id': i.productoId,
          'nombre_producto': i.nombre,
          'cantidad': i.cantidad,
          'costo_usd': i.costoUsd,
          'subtotal_usd': i.subtotalUsd,
        });
        await txn.rawUpdate(
          'UPDATE productos SET stock = stock + ? WHERE id = ? AND (stock_ilimitado IS NULL OR stock_ilimitado = 0)',
          [i.cantidad, i.productoId],
        );
        final filas = await txn.query(
          'productos',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [i.productoId],
          limit: 1,
        );
        await txn.insert('movimientos', {
          'producto_id': i.productoId,
          'tipo': 'entrada',
          'cantidad': i.cantidad,
          'stock_resultante': filas.isNotEmpty ? filas.first['stock'] : null,
          'usuario_id': SesionActual.usuarioId,
          'referencia': 'Compra #$compraId · $proveedor',
          'fecha': DateTime.now().toIso8601String(),
        });
      }
      await _bitacoraTxn(
        txn,
        'compra',
        'Compra #$compraId · $proveedor · \$${totalUsd.toStringAsFixed(2)}${aCredito ? ' a crédito' : ''}',
      );
      return compraId;
    });
  }

  Future<List<Map<String, dynamic>>> listarCompras({int limite = 100}) async =>
      (await _bd).query('compras', orderBy: 'id DESC', limit: limite);

  Future<Map<String, dynamic>?> detalleCompra(int compraId) async {
    final db = await _bd;
    final compra = await db.query(
      'compras',
      where: 'id = ?',
      whereArgs: [compraId],
      limit: 1,
    );
    if (compra.isEmpty) return null;
    final items = await db.query(
      'compra_detalle',
      where: 'compra_id = ?',
      whereArgs: [compraId],
    );
    return {'compra': compra.first, 'items': items};
  }

  Future<List<Map<String, dynamic>>> comprasConSaldo() async {
    final db = await _bd;
    return db.rawQuery('''
      SELECT c.id AS compra_id, c.proveedor, c.fecha, c.total_usd, c.total_bs,
        c.total_usd - COALESCE((SELECT SUM(p.monto_usd) FROM pagos_compra p
                                WHERE p.compra_id = c.id), 0) AS saldo_usd,
        COALESCE((SELECT SUM(p.monto_usd) FROM pagos_compra p
                  WHERE p.compra_id = c.id), 0) AS pagado_usd
      FROM compras c
      WHERE c.estado_pago = 'credito'
      ORDER BY c.id ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> pagosDeCompra(
      int compraId, {
        int limite = 20,
      }) async {
    final db = await _bd;
    return db.query(
      'pagos_compra',
      where: 'compra_id = ?',
      whereArgs: [compraId],
      orderBy: 'id DESC',
      limit: limite,
    );
  }

  Future<void> registrarPagoCompra({
    required int compraId,
    required double montoUsd,
    required double tasa,
    required String metodo,
    String referencia = '',
  }) async {
    final db = await _bd;
    await db.transaction((txn) async {
      await txn.insert('pagos_compra', {
        'compra_id': compraId,
        'monto_usd': montoUsd,
        'monto_bs': montoUsd * tasa,
        'tasa': tasa,
        'metodo': metodo,
        'referencia': referencia,
        'fecha': DateTime.now().toIso8601String(),
        'usuario_id': SesionActual.usuarioId,
      });
      final filas = await txn.rawQuery(
        '''
        SELECT c.total_usd,
          COALESCE((SELECT SUM(p.monto_usd) FROM pagos_compra p
                    WHERE p.compra_id = c.id), 0) AS pagado
        FROM compras c WHERE c.id = ?
      ''',
        [compraId],
      );
      if (filas.isNotEmpty) {
        final total = (filas.first['total_usd'] as num).toDouble();
        final pagado = (filas.first['pagado'] as num?)?.toDouble() ?? 0;
        if (total - pagado <= 0.005) {
          await txn.update(
            'compras',
            {'estado_pago': 'pagada'},
            where: 'id = ?',
            whereArgs: [compraId],
          );
        }
      }
      await _bitacoraTxn(
        txn,
        'pago_compra',
        'Pago de \$${montoUsd.toStringAsFixed(2)} a compra #$compraId',
      );
    });
  }

  // ---------- Clientes y cuentas por cobrar ----------

  Future<int> insertarCliente(Cliente c) async => (await _bd).insert(
    'clientes',
    c.toMap()..removeWhere((k, v) => k == 'id' && v == null),
  );

  Future<int> guardarCliente({
    required String nombre,
    String telefono = '',
  }) async =>
      insertarCliente(Cliente(nombre: nombre, telefono: telefono));

  Future<List<Map<String, dynamic>>> listarClientes() async =>
      (await _bd).query('clientes', orderBy: 'nombre');

  /// Importa productos desde Excel: si el código existe actualiza,
  /// si no existe crea. Devuelve contadores para el reporte.
  Future<Map<String, int>> importarProductos(List<Producto> productos) async {
    final db = await _bd;
    var creados = 0, actualizados = 0, omitidos = 0;
    for (final p in productos) {
      try {
        final existente = p.codigo.isNotEmpty
            ? await db.query(
          'productos',
          where: 'codigo = ?',
          whereArgs: [p.codigo],
          limit: 1,
        )
            : <Map<String, dynamic>>[];
        final mapa = p.toMap()..removeWhere((k, v) => k == 'id');
        if (existente.isNotEmpty) {
          await db.update(
            'productos',
            mapa,
            where: 'id = ?',
            whereArgs: [existente.first['id']],
          );
          actualizados++;
        } else {
          await db.insert('productos', mapa);
          creados++;
        }
      } catch (_) {
        omitidos++;
      }
    }
    await registrarBitacora(
      'producto_importar',
      'Excel → creados: $creados, actualizados: $actualizados, omitidos: $omitidos',
    );
    return {'creados': creados, 'actualizados': actualizados, 'omitidos': omitidos};
  }

  /// Importa clientes desde Excel: coincide por nombre (ignora mayúsculas).
  /// Si existe, actualiza el teléfono; si no, lo crea.
  Future<Map<String, int>> importarClientes(
      List<Map<String, dynamic>> clientes,
      ) async {
    final db = await _bd;
    var creados = 0, actualizados = 0;
    for (final c in clientes) {
      final nombre = (c['nombre'] as String? ?? '').trim();
      if (nombre.isEmpty) continue;
      final tel = (c['telefono'] as String? ?? '').trim();
      final existente = await db.query(
        'clientes',
        where: 'LOWER(nombre) = LOWER(?)',
        whereArgs: [nombre],
        limit: 1,
      );
      if (existente.isNotEmpty) {
        await db.update(
          'clientes',
          {'telefono': tel},
          where: 'id = ?',
          whereArgs: [existente.first['id']],
        );
        actualizados++;
      } else {
        await db.insert('clientes', {
          'nombre': nombre,
          'telefono': tel,
          'creado_en': DateTime.now().toIso8601String(),
        });
        creados++;
      }
    }
    await registrarBitacora(
      'cliente_importar',
      'Excel → creados: $creados, actualizados: $actualizados',
    );
    return {'creados': creados, 'actualizados': actualizados};
  }

  Future<List<Map<String, dynamic>>> clientesConSaldo() async {
    final db = await _bd;
    return db.rawQuery('''
      SELECT c.id AS cliente_id, c.nombre, c.telefono,
        COALESCE((SELECT SUM(v.total_usd) FROM ventas v
                  WHERE v.cliente_id = c.id AND v.estado_pago = 'credito'), 0)
        - COALESCE((SELECT SUM(a.monto_usd) FROM abonos a
                    WHERE a.cliente_id = c.id), 0) AS saldo_usd
      FROM clientes c
      ORDER BY c.nombre
    ''');
  }

  Future<List<Map<String, dynamic>>> creditosDeCliente(int clienteId) async {
    final db = await _bd;
    return db.rawQuery(
      '''
      SELECT v.id AS venta_id, v.fecha, v.total_usd, v.total_bs,
        COALESCE((SELECT SUM(vp.monto_usd) FROM venta_pagos vp
                  WHERE vp.venta_id = v.id AND vp.metodo != 'credito'), 0)
        + COALESCE((SELECT SUM(a.monto_usd) FROM abonos a
                    WHERE a.venta_id = v.id), 0) AS pagado_usd
      FROM ventas v
      WHERE v.cliente_id = ? AND v.estado_pago = 'credito'
      ORDER BY v.id ASC
    ''',
      [clienteId],
    );
  }

  Future<List<Map<String, dynamic>>> abonosDeCliente(
      int clienteId, {
        int limite = 30,
      }) async {
    final db = await _bd;
    return db.query(
      'abonos',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'id DESC',
      limit: limite,
    );
  }

  Future<void> registrarAbono({
    required int ventaId,
    required int clienteId,
    required double montoUsd,
    required double tasa,
    required String metodo,
    String referencia = '',
  }) async {
    final db = await _bd;
    await db.transaction((txn) async {
      await txn.insert('abonos', {
        'venta_id': ventaId,
        'cliente_id': clienteId,
        'monto_usd': montoUsd,
        'monto_bs': montoUsd * tasa,
        'tasa': tasa,
        'metodo': metodo,
        'referencia': referencia,
        'fecha': DateTime.now().toIso8601String(),
        'usuario_id': SesionActual.usuarioId,
      });
      final filas = await txn.rawQuery(
        '''
        SELECT v.total_usd,
          COALESCE((SELECT SUM(vp.monto_usd) FROM venta_pagos vp
                    WHERE vp.venta_id = v.id AND vp.metodo != 'credito'), 0)
          + COALESCE((SELECT SUM(a.monto_usd) FROM abonos a
                      WHERE a.venta_id = v.id), 0) AS pagado
        FROM ventas v WHERE v.id = ?
      ''',
        [ventaId],
      );
      if (filas.isNotEmpty) {
        final total = (filas.first['total_usd'] as num).toDouble();
        final pagado = (filas.first['pagado'] as num?)?.toDouble() ?? 0;
        if (total - pagado <= 0.005) {
          await txn.update(
            'ventas',
            {'estado_pago': 'pagada'},
            where: 'id = ?',
            whereArgs: [ventaId],
          );
        }
      }
      await _bitacoraTxn(
        txn,
        'abono',
        'Abono de \$${montoUsd.toStringAsFixed(2)} a venta #$ventaId',
      );
    });
  }

  Future<Producto> obtenerProductoAvance() async {
    final db = await _bd;
    final filas = await db.query(
      'productos',
      where: 'codigo = ?',
      whereArgs: ['0000001'],
      limit: 1,
    );
    if (filas.isNotEmpty) {
      return Producto.fromMap(filas.first);
    }
    final id = await db.insert('productos', {
      'codigo': '0000001',
      'nombre': 'Avance de Efectivo',
      'precio': 0.0,
      'stock': 0,
      'stock_minimo': 0,
      'stock_ilimitado': 1,
    });
    return Producto(
      id: id,
      codigo: '0000001',
      nombre: 'Avance de Efectivo',
      precio: 0.0,
      stockIlimitado: true,
    );
  }

  // ---------- Respaldo / restauración ----------

  /// Expone la BD abierta para hacer checkpoint de WAL antes de copiar.
  Future<Database> bdParaRespaldo() => _bd;

  /// Cierra la conexión activa. La próxima operación la reabre desde disco.
  Future<void> cerrar() async {
    await _db?.close();
    _db = null;
  }

  // ---------- Reportes ----------

  Future<Map<String, dynamic>> resumenDia(String dia) async {
    final db = await _bd;
    final ventas = await db.rawQuery(
      '''
      SELECT COUNT(*) AS n, COALESCE(SUM(total_usd),0) AS total_usd,
             COALESCE(SUM(total_bs),0) AS total_bs
      FROM ventas WHERE date(fecha) = ?
    ''',
      [dia],
    );
    final pagos = await db.rawQuery(
      '''
      SELECT vp.metodo AS metodo, SUM(vp.monto_usd) AS total_usd,
             SUM(vp.monto_bs) AS total_bs
      FROM venta_pagos vp JOIN ventas v ON v.id = vp.venta_id
      WHERE date(v.fecha) = ?
      GROUP BY vp.metodo
    ''',
      [dia],
    );
    final efectivoVentas = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(vp.monto_usd),0) AS total_usd,
             COALESCE(SUM(vp.monto_bs),0) AS total_bs
      FROM venta_pagos vp JOIN ventas v ON v.id = vp.venta_id
      WHERE date(v.fecha) = ? AND vp.metodo = 'efectivo'
    ''',
      [dia],
    );
    final efectivoAbonos = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(monto_usd),0) AS total_usd,
             COALESCE(SUM(monto_bs),0) AS total_bs
      FROM abonos
      WHERE date(fecha) = ? AND metodo = 'efectivo'
    ''',
      [dia],
    );
    final avancesEntregados = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(vd.subtotal_usd),0) AS total_usd
      FROM venta_detalle vd
      JOIN ventas v ON v.id = vd.venta_id
      WHERE date(v.fecha) = ? AND (vd.nombre_producto LIKE 'Avance%' OR vd.producto_id = (SELECT id FROM productos WHERE codigo = '0000001'))
    ''',
      [dia],
    );
    final compras = await db.rawQuery(
      '''
      SELECT COUNT(*) AS n, COALESCE(SUM(total_usd),0) AS total_usd
      FROM compras WHERE date(fecha) = ?
    ''',
      [dia],
    );
    final abonos = await db.rawQuery(
      '''
      SELECT COUNT(*) AS n, COALESCE(SUM(monto_usd),0) AS total_usd
      FROM abonos WHERE date(fecha) = ?
    ''',
      [dia],
    );
    final lista = await db.rawQuery(
      '''
      SELECT v.*,
             (SELECT GROUP_CONCAT(vp.metodo, ', ') FROM venta_pagos vp WHERE vp.venta_id = v.id) AS metodos_pago
      FROM ventas v
      WHERE date(v.fecha) = ?
      ORDER BY v.id DESC
    ''',
      [dia],
    );

    final efVUsd = (efectivoVentas.first['total_usd'] as num?)?.toDouble() ?? 0;
    final efVBs = (efectivoVentas.first['total_bs'] as num?)?.toDouble() ?? 0;
    final efAUsd = (efectivoAbonos.first['total_usd'] as num?)?.toDouble() ?? 0;
    final efABs = (efectivoAbonos.first['total_bs'] as num?)?.toDouble() ?? 0;

    final avUsd =
        (avancesEntregados.first['total_usd'] as num?)?.toDouble() ?? 0;
    final totalVBs = (ventas.first['total_bs'] as num?)?.toDouble() ?? 0;
    final totalVUsd = (ventas.first['total_usd'] as num?)?.toDouble() ?? 0;
    final tasaProm = totalVUsd > 0 ? totalVBs / totalVUsd : 1.0;
    final avBs = avUsd * tasaProm;

    final espUsd = (efVUsd + efAUsd - avUsd) < 0 ? 0.0 : (efVUsd + efAUsd - avUsd);
    final espBs = (efVBs + efABs - avBs) < 0 ? 0.0 : (efVBs + efABs - avBs);

    return {
      'numVentas': Sqflite.firstIntValue(ventas) ?? 0,
      'totalUsd': totalVUsd,
      'totalBs': totalVBs,
      'pagos': pagos,
      'efectivoEsperadoUsd': espUsd,
      'efectivoEsperadoBs': espBs,
      'avancesUsd': avUsd,
      'avancesBs': avBs,
      'numCompras': Sqflite.firstIntValue(compras) ?? 0,
      'comprasUsd': (compras.first['total_usd'] as num?)?.toDouble() ?? 0,
      'numAbonos': Sqflite.firstIntValue(abonos) ?? 0,
      'abonosUsd': (abonos.first['total_usd'] as num?)?.toDouble() ?? 0,
      'ventas': lista,
    };
  }

  Future<List<Map<String, dynamic>>> productosVendidosDia(String dia) async {
    final db = await _bd;
    return db.rawQuery(
      '''
      SELECT vd.nombre_producto AS nombre,
             SUM(vd.cantidad) AS cantidad,
             SUM(vd.subtotal_usd) AS total_usd
      FROM venta_detalle vd
      JOIN ventas v ON v.id = vd.venta_id
      WHERE date(v.fecha) = ?
      GROUP BY vd.nombre_producto
      ORDER BY cantidad DESC
    ''',
      [dia],
    );
  }

  Future<List<Map<String, dynamic>>> topProductos({
    int dias = 30,
    int limite = 10,
  }) async {
    final db = await _bd;
    final desde = DateTime.now().subtract(Duration(days: dias - 1));
    final desdeStr =
        '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
    return db.rawQuery(
      '''
      SELECT vd.nombre_producto AS nombre,
             SUM(vd.cantidad) AS cantidad,
             SUM(vd.subtotal_usd) AS total_usd
      FROM venta_detalle vd JOIN ventas v ON v.id = vd.venta_id
      WHERE date(v.fecha) >= ?
      GROUP BY vd.nombre_producto
      ORDER BY cantidad DESC
      LIMIT ?
    ''',
      [desdeStr, limite],
    );
  }

  // ---------- Usuarios ----------

  Future<Usuario?> buscarUsuario(String usuario) async {
    final db = await _bd;
    final filas = await db.query(
      'usuarios',
      where: 'usuario = ? AND activo = 1',
      whereArgs: [usuario],
      limit: 1,
    );
    return filas.isEmpty ? null : Usuario.fromMap(filas.first);
  }

  Future<List<Usuario>> listarUsuarios() async {
    final db = await _bd;
    final filas = await db.query('usuarios', orderBy: 'nombre');
    return filas.map(Usuario.fromMap).toList();
  }

  Future<int> insertarUsuario(Map<String, dynamic> m) async =>
      (await _bd).insert('usuarios', m);

  Future<int> actualizarUsuario(Map<String, dynamic> m) async =>
      (await _bd).update('usuarios', m, where: 'id = ?', whereArgs: [m['id']]);

  Future<int> eliminarUsuario(int id) async {
    final db = await _bd;
    final filas = await db.query(
      'usuarios',
      columns: ['nombre', 'usuario'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final n = await db.delete('usuarios', where: 'id = ?', whereArgs: [id]);
    if (n > 0) {
      await registrarBitacora(
        'usuario_eliminar',
        filas.isNotEmpty
            ? '${filas.first['nombre']} (${filas.first['usuario']})'
            : 'ID $id',
      );
    }
    return n;
  }

  Future<int> contarAdmins({int? excluido}) async {
    final db = await _bd;
    return Sqflite.firstIntValue(
      await db.query(
        'usuarios',
        columns: ['COUNT(*)'],
        where:
        "rol = 'admin' AND activo = 1${excluido != null ? ' AND id != ?' : ''}",
        whereArgs: [?excluido],
      ),
    ) ??
        0;
  }

  // ---------- Configuración ----------

  Future<String?> getConfig(String clave) async {
    final filas = await (await _bd).query(
      'configuracion',
      where: 'clave = ?',
      whereArgs: [clave],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first['valor'] as String?;
  }

  Future<void> setConfig(String clave, String valor) async {
    final db = await _bd;
    await db.insert('configuracion', {
      'clave': clave,
      'valor': valor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> eliminarConfig(String clave) async => (await _bd).delete(
    'configuracion',
    where: 'clave = ?',
    whereArgs: [clave],
  );

  Future<double> obtenerTasa() async {
    final v = await getConfig('tasa_bs');
    return double.tryParse(v ?? '') ?? 40.0;
  }

  Future<void> guardarTasa(double tasa) async {
    await setConfig('tasa_bs', tasa.toString());
    await registrarBitacora(
      'config',
      'Tasa actualizada a Bs ${tasa.toStringAsFixed(2)} / \$1',
    );
  }

  Future<double> obtenerComisionAvance() async {
    final v = await getConfig('comision_avance');
    return double.tryParse(v ?? '') ?? 5.0;
  }

  Future<void> guardarComisionAvance(double pct) async {
    await setConfig('comision_avance', pct.toString());
    await registrarBitacora(
      'config',
      'Comisión de avance efectivo: ${pct.toStringAsFixed(2)}%',
    );
  }

  Future<double> obtenerTasaDivisa() async {
    final v = await getConfig('tasa_divisa');
    final d = double.tryParse(v ?? '') ?? 0;
    return d > 0 ? d : 0; // 0 = no configurada, usar la general
  }

  Future<void> guardarTasaDivisa(double tasa) async {
    await setConfig('tasa_divisa', tasa.toString());
    await registrarBitacora(
      'config',
      'Tasa de cobro en divisas: Bs ${tasa.toStringAsFixed(2)} / \$1',
    );
  }

  Future<String> obtenerNombreNegocio() async =>
      await getConfig('nombre_negocio') ?? 'Mi POS';

  Future<void> guardarNombreNegocio(String nombre) async {
    await setConfig('nombre_negocio', nombre);
    await registrarBitacora('config', 'Nombre del negocio: $nombre');
  }

  static String _saltAleatorio() {
    final r = Random.secure();
    return List.generate(
      16,
          (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _hashear(String salt, String password) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();
}