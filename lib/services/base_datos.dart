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
      version: 6,
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
    await _crearTablas(db); // IF NOT EXISTS: seguro sobre BDs viejas
    await _sembrarAdmin(db);
  }

  Future<void> _crearTablas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS productos (
        id     INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT UNIQUE,
        nombre TEXT NOT NULL,
        precio REAL NOT NULL,
        stock  INTEGER NOT NULL DEFAULT 0
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
    // Migraciones para BDs creadas en versiones anteriores
    try {
      await db.execute(
        'ALTER TABLE productos ADD COLUMN stock_minimo INTEGER NOT NULL DEFAULT 5',
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
      'hash': _hashear(salt, 'admin123'), // ⚠️ cámbiala tras el primer login
      'rol': 'admin',
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  // ---------- Bitácora ----------

  /// Registra una acción en la bitácora (fuera de transacciones).
  Future<void> registrarBitacora(String accion, [String? detalle]) async {
    await (await _bd).insert('bitacora', {
      'fecha': DateTime.now().toIso8601String(),
      'usuario_id': SesionActual.usuarioId,
      'accion': accion,
      'detalle': detalle,
    });
  }

  /// Versión para usar DENTRO de una transacción.
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

  /// Últimos registros de la bitácora con nombre de usuario.
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

  Future<List<Producto>> listar({String filtro = ''}) async {
    final db = await _bd;
    final f = filtro.trim();
    if (f.isEmpty) {
      final filas = await db.query('productos', orderBy: 'nombre');
      return filas.map(Producto.fromMap).toList();
    }
    final filas = await db.query(
      'productos',
      where:
          'nombre LIKE ? OR (codigo IS NOT NULL AND codigo != "" AND codigo LIKE ?)',
      whereArgs: ['%$f%', '%$f%'],
      orderBy: 'nombre',
    );
    return filas.map(Producto.fromMap).toList();
  }

  Future<Producto?> buscarPorCodigo(String codigo) async {
    final c = codigo.trim();
    if (c.isEmpty) return null;
    final db = await _bd;
    final filas = await db.query(
      'productos',
      where: 'codigo = ?',
      whereArgs: [c],
      limit: 1,
    );
    return filas.isEmpty ? null : Producto.fromMap(filas.first);
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

  /// Elimina TODOS los productos y limpia movimientos huérfanos.
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

  /// Descuenta/aumenta stock y registra el movimiento (kardex).
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
        'UPDATE productos SET stock = stock + ? WHERE id = ?',
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

  /// Kardex: últimos movimientos (opcionalmente de un producto).
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

  /// Registra la venta completa en una transacción.
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
          'UPDATE productos SET stock = stock - ? WHERE id = ?',
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

  /// Registra la compra: aumenta stock, guarda kardex como entrada.
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
          'UPDATE productos SET stock = stock + ? WHERE id = ?',
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

  /// Compras a crédito con saldo pendiente (Cuentas por pagar).
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

  /// Registra un pago a proveedor. Si el saldo llega a 0, la compra se marca pagada.
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

  Future<List<Map<String, dynamic>>> listarClientes() async =>
      (await _bd).query('clientes', orderBy: 'nombre');

  /// Saldo pendiente por cliente (ventas a crédito - abonos).
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

  /// Créditos pendientes de un cliente, con monto pagado de cada venta.
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

  /// Registra un abono a un crédito. Si el saldo llega a 0, la venta se marca pagada.
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

  // ---------- Reportes ----------

  /// Resumen de un día ('yyyy-MM-dd') + lista de sus ventas.
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
    final lista = await db.query(
      'ventas',
      where: 'date(fecha) = ?',
      whereArgs: [dia],
      orderBy: 'id DESC',
    );
    return {
      'numVentas': Sqflite.firstIntValue(ventas) ?? 0,
      'totalUsd': (ventas.first['total_usd'] as num?)?.toDouble() ?? 0,
      'totalBs': (ventas.first['total_bs'] as num?)?.toDouble() ?? 0,
      'pagos': pagos,
      'numCompras': Sqflite.firstIntValue(compras) ?? 0,
      'comprasUsd': (compras.first['total_usd'] as num?)?.toDouble() ?? 0,
      'numAbonos': Sqflite.firstIntValue(abonos) ?? 0,
      'abonosUsd': (abonos.first['total_usd'] as num?)?.toDouble() ?? 0,
      'ventas': lista,
    };
  }

  /// Top de productos más vendidos en los últimos [dias] días.
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

  // ---------- Configuración (tasa, negocio, licencia, trial) ----------

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

  /// Tasa Bs por 1 USD (default 40 si nunca se ha configurado).
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

  Future<String> obtenerNombreNegocio() async =>
      await getConfig('nombre_negocio') ?? 'Mi POS';

  Future<void> guardarNombreNegocio(String nombre) async {
    await setConfig('nombre_negocio', nombre);
    await registrarBitacora('config', 'Nombre del negocio: $nombre');
  }

  // ---------- Utilidades de hash ----------

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
