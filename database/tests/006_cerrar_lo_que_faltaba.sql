WITH nuevo AS (
  INSERT INTO lote (id_sede, id_categoria, id_tipo, id_unidad, descripcion,
                    cantidad_inicial, saldo, fecha_recepcion, fecha_vencimiento)
  SELECT (SELECT min(id_sede) FROM sede),
         (SELECT min(id_categoria) FROM categoria),
         (SELECT min(id_tipo) FROM tipo_alimento
           WHERE id_categoria = (SELECT min(id_categoria) FROM categoria)),
         (SELECT min(id_unidad) FROM unidad WHERE abreviatura = 'kg'),
         'Lote vencido de prueba', 8, 8, CURRENT_DATE - 10, CURRENT_DATE - 2
  RETURNING id_lote
)
INSERT INTO movimiento_inventario (id_lote, tipo, cantidad, motivo, fecha)
SELECT id_lote, 'entrada', 8, 'Recepción de prueba', now() - interval '10 days'
FROM nuevo
RETURNING id_lote;

CALL marcar_lotes_vencidos(2, 0);