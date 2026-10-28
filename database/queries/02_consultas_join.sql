-- J1 (INNER). Lotes con su donante, sede, categoría y unidad. Vista operativa.
SELECT l.id_lote, d.nombre AS donante, s.nombre AS sede, c.nombre AS categoria,
       l.cantidad_inicial, u.abreviatura AS unidad, l.fecha_recepcion
FROM lote l
INNER JOIN sede s      ON s.id_sede = l.id_sede
INNER JOIN donante d   ON d.id_donante = s.id_donante
INNER JOIN categoria c ON c.id_categoria = l.id_categoria
INNER JOIN unidad u    ON u.id_unidad = l.id_unidad
ORDER BY l.fecha_recepcion DESC
LIMIT 15;

-- J2 (INNER). Reservas activas y quién las pidió (uso del gestor).
SELECT r.id_reserva, r.fecha_reserva, s.id_solicitud,
       us.nombre AS beneficiario, r.estado
FROM reserva r
INNER JOIN solicitud s     ON s.id_solicitud = r.id_solicitud
INNER JOIN beneficiario b  ON b.id_beneficiario = s.id_beneficiario
INNER JOIN usuario us      ON us.id_usuario = b.id_usuario
WHERE r.estado = 'activa'
ORDER BY r.fecha_reserva;

-- J3 (LEFT, "anti-join"). Beneficiarios que NUNCA han recibido una entrega.
-- Sirve para detectar a quién no se está llegando.
SELECT b.id_beneficiario, us.nombre
FROM beneficiario b
INNER JOIN usuario us ON us.id_usuario = b.id_usuario
LEFT JOIN solicitud s ON s.id_beneficiario = b.id_beneficiario
                     AND s.estado = 'entregada'
WHERE s.id_solicitud IS NULL
ORDER BY b.id_beneficiario;

-- J4 (LEFT, "anti-join"). Lotes que nadie ha reservado nunca.
-- Sirve para ver excedentes que no se están moviendo.
SELECT l.id_lote, l.descripcion, l.cantidad_inicial, l.estado
FROM lote l
LEFT JOIN reserva_detalle rd ON rd.id_lote = l.id_lote
WHERE rd.id_reserva_detalle IS NULL
ORDER BY l.cantidad_inicial DESC
LIMIT 15;

-- J5 (INNER + GROUP BY). Entregas y cantidad entregada por gestor y unidad.
SELECT g.nombre AS gestor, u.abreviatura AS unidad,
       count(DISTINCT e.id_entrega) AS entregas,
       SUM(rd.cantidad) AS cantidad_total
FROM entrega e
INNER JOIN usuario g          ON g.id_usuario = e.id_usuario_gestor
INNER JOIN reserva_detalle rd ON rd.id_reserva = e.id_reserva
INNER JOIN lote l             ON l.id_lote = rd.id_lote
INNER JOIN unidad u           ON u.id_unidad = l.id_unidad
GROUP BY g.nombre, u.abreviatura
ORDER BY entregas DESC;

-- J6 (INNER + HAVING). Categorías más pedidas (solo las pedidas 5 veces o más).
SELECT c.nombre AS categoria, u.abreviatura AS unidad,
       count(*) AS solicitudes,
       SUM(sd.cantidad_solicitada) AS total_solicitado
FROM solicitud_detalle sd
INNER JOIN categoria c ON c.id_categoria = sd.id_categoria
INNER JOIN unidad u    ON u.id_unidad = sd.id_unidad
GROUP BY c.nombre, u.abreviatura
HAVING count(*) >= 5
ORDER BY total_solicitado DESC;

-- J7 (LEFT + GROUP BY). Lotes donados por cada donante, incluyendo los que
-- aún no han donado nada (salen con 0).
SELECT d.nombre AS donante, count(l.id_lote) AS lotes_donados
FROM donante d
LEFT JOIN sede s ON s.id_donante = d.id_donante
LEFT JOIN lote l ON l.id_sede = s.id_sede
GROUP BY d.nombre
ORDER BY lotes_donados DESC;

-- J8 (LEFT + subconsulta). Historial completo del lote con más movimientos
-- y quién registró cada uno ("Sistema" si no hay usuario).
SELECT m.fecha, m.tipo, m.cantidad,
       COALESCE(us.nombre, 'Sistema') AS registrado_por, m.motivo
FROM movimiento_inventario m
LEFT JOIN usuario us ON us.id_usuario = m.id_usuario
WHERE m.id_lote = (
  SELECT id_lote
  FROM movimiento_inventario
  GROUP BY id_lote
  ORDER BY count(*) DESC, id_lote
  LIMIT 1
)
ORDER BY m.fecha, m.id_movimiento;