-- A1 (GROUP BY + HAVING). Categorías con más de 50 unidades disponibles.
SELECT categoria, unidad, count(*) AS lotes, SUM(saldo) AS saldo_total
FROM v_inventario_disponible
GROUP BY categoria, unidad
HAVING SUM(saldo) > 50
ORDER BY saldo_total DESC;

-- A2 (subconsulta correlacionada). Lotes con más saldo que el promedio de su
-- misma categoría y unidad.
SELECT l.id_lote, l.descripcion, l.saldo, l.id_categoria
FROM lote l
WHERE l.estado = 'activo'
  AND l.saldo > (
    SELECT AVG(l2.saldo)
    FROM lote l2
    WHERE l2.id_categoria = l.id_categoria
      AND l2.id_unidad = l.id_unidad
      AND l2.estado = 'activo'
  )
ORDER BY l.saldo DESC
LIMIT 10;

-- A3 (CTE + CASE). Inventario disponible clasificado por urgencia de vencimiento.
WITH clasificado AS (
  SELECT categoria, unidad, saldo,
         CASE
           WHEN dias_para_vencer <= 1 THEN '1 Crítico (hoy o mañana)'
           WHEN dias_para_vencer <= 3 THEN '2 Urgente (2 a 3 días)'
           WHEN dias_para_vencer <= 7 THEN '3 Atención (4 a 7 días)'
           ELSE                            '4 Normal (más de 7 días)'
         END AS urgencia
  FROM v_inventario_disponible
)
SELECT urgencia, unidad, count(*) AS lotes, SUM(saldo) AS saldo_total
FROM clasificado
GROUP BY urgencia, unidad
ORDER BY urgencia, unidad;

-- A4 (operaciones con fechas). Vida útil promedio de cada categoría, en días.
SELECT c.nombre AS categoria,
       round(AVG(l.fecha_vencimiento - l.fecha_recepcion), 1) AS vida_util_dias,
       min(l.fecha_recepcion) AS primer_lote,
       max(l.fecha_recepcion) AS ultimo_lote
FROM lote l
INNER JOIN categoria c ON c.id_categoria = l.id_categoria
GROUP BY c.nombre
ORDER BY vida_util_dias DESC;

-- A5 (fechas con date_trunc). Lotes recibidos por mes.
SELECT date_trunc('month', fecha_recepcion)::date AS mes, count(*) AS lotes
FROM lote
GROUP BY 1
ORDER BY 1;

-- W1 (función de ventana RANK). Ranking de donantes por número de lotes.
SELECT d.nombre AS donante,
       count(l.id_lote) AS lotes,
       RANK() OVER (ORDER BY count(l.id_lote) DESC) AS posicion
FROM donante d
INNER JOIN sede s ON s.id_donante = d.id_donante
INNER JOIN lote l ON l.id_sede = s.id_sede
GROUP BY d.id_donante, d.nombre
ORDER BY posicion, donante;

-- W2 (ventanas SUM acumulado y LAG). Lo donado mes a mes, el acumulado y la
-- variación frente al mes anterior.
SELECT mes, unidad, donado, entregado,
       SUM(donado) OVER (PARTITION BY unidad ORDER BY mes) AS donado_acumulado,
       donado - LAG(donado) OVER (PARTITION BY unidad ORDER BY mes)
         AS variacion_vs_mes_anterior
FROM v_indicador_mensual
ORDER BY unidad, mes;