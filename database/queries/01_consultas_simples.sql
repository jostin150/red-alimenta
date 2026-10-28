-- S1. Lotes activos que vencen en los próximos 5 días (para priorizar su entrega)
SELECT id_lote, descripcion, saldo, fecha_vencimiento
FROM lote
WHERE estado = 'activo' AND saldo > 0
  AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + 5
ORDER BY fecha_vencimiento;

-- S2. Donantes que son panaderías o restaurantes
SELECT id_donante, nombre, tipo
FROM donante
WHERE tipo IN ('panaderia', 'restaurante')
ORDER BY nombre;

-- S3. Los 10 lotes más grandes que han llegado
SELECT id_lote, descripcion, cantidad_inicial, fecha_recepcion
FROM lote
ORDER BY cantidad_inicial DESC
LIMIT 10;

-- S4. Solicitudes pendientes, de la más antigua a la más reciente
SELECT id_solicitud, id_beneficiario, fecha_solicitud
FROM solicitud
WHERE estado = 'pendiente'
ORDER BY fecha_solicitud;

-- S5. Cuántos lotes hay en cada estado
SELECT estado, count(*) AS total
FROM lote
GROUP BY estado
ORDER BY total DESC;

-- S6. Barrios donde hay sedes de donantes
SELECT DISTINCT barrio
FROM sede
WHERE barrio IS NOT NULL
ORDER BY barrio;

-- S7. Buscar usuarios por nombre
SELECT id_usuario, nombre, correo
FROM usuario
WHERE nombre ILIKE 'gestor%';

-- S8. Movimientos de los últimos 30 días
SELECT id_movimiento, id_lote, tipo, cantidad, fecha
FROM movimiento_inventario
WHERE fecha >= CURRENT_DATE - 30
ORDER BY fecha DESC
LIMIT 20;

-- S9. Pérdidas grandes por vencimiento (más de 20 unidades)
SELECT id_lote, cantidad, fecha
FROM movimiento_inventario
WHERE tipo = 'vencimiento' AND cantidad > 20
ORDER BY cantidad DESC;

-- S10. Solicitudes rechazadas, con el motivo
SELECT id_solicitud, fecha_solicitud, observacion
FROM solicitud
WHERE estado = 'rechazada' AND observacion IS NOT NULL
ORDER BY fecha_solicitud DESC;

-- S11. Conteos generales del sistema
SELECT (SELECT count(*) FROM lote)       AS lotes,
       (SELECT count(*) FROM solicitud)  AS solicitudes,
       (SELECT count(*) FROM entrega)    AS entregas;