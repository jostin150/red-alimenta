BEGIN;

-- ÍNDICES
-- Para escoger rápido los lotes que vencen primero (FiFO)
CREATE INDEX idx_lote_fefo
  ON lote (id_categoria, fecha_vencimiento)
  WHERE estado = 'activo' AND saldo > 0;

CREATE INDEX idx_lote_sede ON lote (id_sede);
CREATE INDEX idx_movimiento_lote ON movimiento_inventario (id_lote, fecha);
CREATE INDEX idx_solicitud_beneficiario ON solicitud (id_beneficiario, estado);
CREATE INDEX idx_reserva_solicitud ON reserva (id_solicitud);
CREATE INDEX idx_reserva_detalle_lote ON reserva_detalle (id_lote);
CREATE INDEX idx_auditoria_tabla ON auditoria (tabla, fecha);

--inventario disponible
CREATE VIEW v_inventario_disponible AS
SELECT l.id_lote,
       d.nombre AS donante,
       s.nombre AS sede,
       c.nombre AS categoria,
       l.descripcion,
       l.saldo,
       u.abreviatura AS unidad,
       l.fecha_vencimiento,
       (l.fecha_vencimiento - CURRENT_DATE) AS dias_para_vencer
FROM lote l
JOIN sede s ON s.id_sede = l.id_sede
JOIN donante d ON d.id_donante = s.id_donante
JOIN categoria c ON c.id_categoria = l.id_categoria
JOIN unidad u ON u.id_unidad = l.id_unidad
WHERE l.estado = 'activo'
  AND l.saldo > 0
  AND l.fecha_vencimiento >= CURRENT_DATE;

--alertas de vencimiento (próximos 3 días)
CREATE VIEW v_alertas_vencimiento AS
SELECT *
FROM v_inventario_disponible
WHERE dias_para_vencer <= 3
ORDER BY fecha_vencimiento;

--historial de movimientos
CREATE VIEW v_historial_movimientos AS
SELECT m.id_movimiento,
       m.fecha,
       m.tipo,
       m.cantidad,
       u.abreviatura AS unidad,
       l.id_lote,
       l.descripcion,
       m.id_reserva,
       us.nombre AS usuario,
       m.motivo
FROM movimiento_inventario m
JOIN lote l ON l.id_lote = m.id_lote
JOIN unidad u ON u.id_unidad = l.id_unidad
LEFT JOIN usuario us ON us.id_usuario = m.id_usuario;

-- indicador mensual (donado, entregado, perdido)
CREATE VIEW v_indicador_mensual AS
SELECT date_trunc('month', m.fecha)::date AS mes,
       u.abreviatura AS unidad,
       SUM(m.cantidad) FILTER (WHERE m.tipo = 'entrada') AS donado,
       SUM(m.cantidad) FILTER (WHERE m.tipo = 'salida') AS entregado,
       SUM(m.cantidad) FILTER (WHERE m.tipo = 'vencimiento') AS perdido
FROM movimiento_inventario m
JOIN lote l ON l.id_lote = m.id_lote
JOIN unidad u ON u.id_unidad = l.id_unidad
GROUP BY 1, 2;

COMMIT;