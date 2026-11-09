BEGIN;

--  Inventario disponible 

CREATE OR REPLACE VIEW v_reporte_inventario_sede_categoria AS
SELECT donante, sede, categoria, unidad,
       count(*)                                         AS lotes,
       SUM(saldo)                                       AS saldo_disponible,
       SUM(saldo) FILTER (WHERE dias_para_vencer <= 3)  AS saldo_por_vencer,
       min(fecha_vencimiento)                           AS proximo_vencimiento
FROM v_inventario_disponible
GROUP BY donante, sede, categoria, unidad;

--  Balance  (recibido, entregado, cancelado, perdido)
CREATE OR REPLACE VIEW v_reporte_balance_mensual AS
SELECT date_trunc('month', m.fecha)::date AS mes,
       u.abreviatura AS unidad,
       COALESCE(SUM(m.cantidad) FILTER (WHERE m.tipo = 'entrada'),     0) AS recibido,
       COALESCE(SUM(m.cantidad) FILTER (WHERE m.tipo = 'salida'),      0) AS entregado,
       COALESCE(SUM(m.cantidad) FILTER (WHERE m.tipo = 'liberacion'),  0) AS cancelado,
       COALESCE(SUM(m.cantidad) FILTER (WHERE m.tipo = 'vencimiento'), 0) AS perdido
FROM movimiento_inventario m
INNER JOIN lote l   ON l.id_lote = m.id_lote
INNER JOIN unidad u ON u.id_unidad = l.id_unidad
GROUP BY date_trunc('month', m.fecha)::date, u.abreviatura;


CREATE OR REPLACE VIEW v_reporte_aprovechamiento AS
WITH por_lote AS (
  SELECT l.id_lote,
         date_trunc('month', l.fecha_recepcion)::date AS mes,
         u.abreviatura AS unidad,
         l.cantidad_inicial,
         COALESCE(SUM(m.cantidad) FILTER (WHERE m.tipo = 'salida'), 0) AS entregado
  FROM lote l
  INNER JOIN unidad u ON u.id_unidad = l.id_unidad
  LEFT JOIN movimiento_inventario m ON m.id_lote = l.id_lote
  GROUP BY l.id_lote, u.abreviatura
),
tiempos AS (
  SELECT date_trunc('month', l.fecha_recepcion)::date AS mes,
         u.abreviatura AS unidad,
         round(AVG(e.fecha_entrega::date - l.fecha_recepcion), 1) AS dias_medios
  FROM entrega e
  INNER JOIN reserva_detalle rd ON rd.id_reserva = e.id_reserva
  INNER JOIN lote l             ON l.id_lote = rd.id_lote
  INNER JOIN unidad u           ON u.id_unidad = l.id_unidad
  GROUP BY date_trunc('month', l.fecha_recepcion)::date, u.abreviatura
)
SELECT p.mes, p.unidad,
       SUM(p.cantidad_inicial) AS recibido,
       SUM(p.entregado)        AS entregado,
       round(100.0 * SUM(p.entregado) / NULLIF(SUM(p.cantidad_inicial), 0), 2)
         AS tasa_aprovechamiento,
       t.dias_medios           AS dias_medios_hasta_entrega
FROM por_lote p
LEFT JOIN tiempos t ON t.mes = p.mes AND t.unidad = p.unidad
GROUP BY p.mes, p.unidad, t.dias_medios;


CREATE OR REPLACE VIEW v_reporte_beneficiarios_comuna AS
SELECT COALESCE(b.comuna, 'Sin comuna')       AS comuna,
       count(DISTINCT b.id_beneficiario)      AS beneficiarios_atendidos,
       count(DISTINCT e.id_entrega)           AS entregas
FROM entrega e
INNER JOIN reserva r       ON r.id_reserva = e.id_reserva
INNER JOIN solicitud s     ON s.id_solicitud = r.id_solicitud
INNER JOIN beneficiario b  ON b.id_beneficiario = s.id_beneficiario
GROUP BY 1
HAVING count(DISTINCT b.id_beneficiario) >= 3;


CREATE OR REPLACE VIEW v_reporte_donantes AS
WITH base AS (
  SELECT d.id_donante, d.nombre AS donante,
         count(l.id_lote) AS lotes,
         COALESCE(SUM(l.cantidad_inicial) FILTER (WHERE u.abreviatura = 'kg'), 0)
           AS kg_donados,
         count(DISTINCT date_trunc('month', l.fecha_recepcion)) AS meses_activos,
         max(l.fecha_recepcion) AS ultima_donacion
  FROM donante d
  INNER JOIN sede s   ON s.id_donante = d.id_donante
  INNER JOIN lote l   ON l.id_sede = s.id_sede
  INNER JOIN unidad u ON u.id_unidad = l.id_unidad
  GROUP BY d.id_donante, d.nombre
),
meses AS (
  SELECT count(DISTINCT date_trunc('month', fecha_recepcion)) AS total
  FROM lote
)
SELECT RANK() OVER (ORDER BY b.lotes DESC, b.meses_activos DESC) AS posicion,
       b.donante, b.lotes, b.kg_donados, b.meses_activos,
       round(100.0 * b.meses_activos / NULLIF(m.total, 0), 1) AS regularidad_pct,
       b.ultima_donacion
FROM base b
CROSS JOIN meses m
ORDER BY posicion, b.donante;


CREATE OR REPLACE FUNCTION trazabilidad_lote(p_id_lote INT)
RETURNS TABLE (
  fecha          TIMESTAMPTZ,
  tipo           VARCHAR,
  cantidad       NUMERIC,
  unidad         VARCHAR,
  id_reserva     INT,
  id_solicitud   INT,
  comuna         VARCHAR,
  registrado_por VARCHAR,
  saldo_despues  NUMERIC
)
LANGUAGE sql
STABLE
AS $$
  SELECT m.fecha, m.tipo, m.cantidad, u.abreviatura,
         m.id_reserva, r.id_solicitud, b.comuna,
         COALESCE(us.nombre, 'Sistema')::VARCHAR,
         SUM(CASE m.tipo
               WHEN 'entrada'     THEN  m.cantidad
               WHEN 'liberacion'  THEN  m.cantidad
               WHEN 'reserva'     THEN -m.cantidad
               WHEN 'vencimiento' THEN -m.cantidad
               ELSE 0
             END) OVER (ORDER BY m.fecha, m.id_movimiento)
  FROM movimiento_inventario m
  INNER JOIN lote l       ON l.id_lote = m.id_lote
  INNER JOIN unidad u     ON u.id_unidad = l.id_unidad
  LEFT JOIN reserva r     ON r.id_reserva = m.id_reserva
  LEFT JOIN solicitud s   ON s.id_solicitud = r.id_solicitud
  LEFT JOIN beneficiario b ON b.id_beneficiario = s.id_beneficiario
  LEFT JOIN usuario us    ON us.id_usuario = m.id_usuario
  WHERE m.id_lote = p_id_lote
  ORDER BY m.fecha, m.id_movimiento;
$$;

COMMIT;