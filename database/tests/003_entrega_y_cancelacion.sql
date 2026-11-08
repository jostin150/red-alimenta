WITH nueva AS (
  INSERT INTO solicitud (id_beneficiario, id_punto)
  SELECT MIN(id_beneficiario), (SELECT MIN(id_punto) FROM punto_entrega) FROM beneficiario
  RETURNING id_solicitud
), mejor AS (
  SELECT id_categoria, id_tipo, id_unidad
  FROM lote
  WHERE estado = 'activo' AND saldo > 0 AND fecha_vencimiento >= CURRENT_DATE
  GROUP BY id_categoria, id_tipo, id_unidad
  ORDER BY SUM(saldo) DESC
  LIMIT 1
)
INSERT INTO solicitud_detalle (id_solicitud, id_categoria, id_tipo, id_unidad, cantidad_solicitada)
SELECT nueva.id_solicitud, mejor.id_categoria, mejor.id_tipo, mejor.id_unidad, 20
FROM nueva, mejor
RETURNING id_solicitud;