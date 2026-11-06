-- 014: la solicitud usa TIPO + PUNTO DE ENTREGA, la reserva respeta el tipo,
--      y el beneficiario puede cancelar su propia solicitud.
--
-- Requiere haber ejecutado antes la 013.
-- Ejecutar UNA sola vez, en el Query Tool de la base "alimenta".
--
-- OJO: al terminar esta migración, el formulario "Nueva solicitud" de la
-- aplicación deja de funcionar hasta que cambiemos app.py (paso siguiente).
BEGIN;

-- ============================================================
-- 1. crear_solicitud: ahora recibe tipo y punto de entrega
-- La categoría ya no se envía: se deduce del tipo (cada tipo pertenece
-- a una sola categoría), así nadie puede mezclarlas.
-- ============================================================
DROP PROCEDURE IF EXISTS public.crear_solicitud(INT, INT, INT, NUMERIC, INT);

CREATE OR REPLACE PROCEDURE public.crear_solicitud(
  p_id_usuario INT,
  p_id_tipo    INT,
  p_id_unidad  INT,
  p_cantidad   NUMERIC,
  p_id_punto   INT,
  INOUT p_id_solicitud INT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id_beneficiario INT;
  v_estado          VARCHAR(15);
  v_consentimiento  BOOLEAN;
  v_id_categoria    SMALLINT;
BEGIN
  -- 1) Debe ser un beneficiario activo y con consentimiento
  SELECT b.id_beneficiario, b.estado, b.consentimiento
    INTO v_id_beneficiario, v_estado, v_consentimiento
  FROM beneficiario b
  JOIN usuario u ON u.id_usuario = b.id_usuario
  WHERE b.id_usuario = p_id_usuario AND u.activo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario % no es un beneficiario activo', p_id_usuario;
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'Tu perfil de beneficiario no está activo';
  END IF;
  IF NOT v_consentimiento THEN
    RAISE EXCEPTION 'Debes aceptar el tratamiento de tus datos antes de solicitar';
  END IF;

  -- 2) Cantidad, unidad, tipo y punto válidos
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'La cantidad debe ser mayor que cero';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM unidad WHERE id_unidad = p_id_unidad) THEN
    RAISE EXCEPTION 'La unidad % no existe', p_id_unidad;
  END IF;

  SELECT id_categoria INTO v_id_categoria
  FROM tipo_alimento
  WHERE id_tipo = p_id_tipo AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El tipo de alimento % no existe o no está disponible', p_id_tipo;
  END IF;

  IF p_id_punto IS NULL THEN
    RAISE EXCEPTION 'Debes elegir un punto de entrega';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM punto_entrega WHERE id_punto = p_id_punto AND activo) THEN
    RAISE EXCEPTION 'El punto de entrega % no existe o no está activo', p_id_punto;
  END IF;

  -- 3) Crear la solicitud y su detalle
  INSERT INTO solicitud (id_beneficiario, id_punto)
  VALUES (v_id_beneficiario, p_id_punto)
  RETURNING id_solicitud INTO p_id_solicitud;

  INSERT INTO solicitud_detalle
    (id_solicitud, id_categoria, id_tipo, id_unidad, cantidad_solicitada)
  VALUES (p_id_solicitud, v_id_categoria, p_id_tipo, p_id_unidad, p_cantidad);
END;
$$;

REVOKE ALL ON PROCEDURE public.crear_solicitud(INT, INT, INT, NUMERIC, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.crear_solicitud(INT, INT, INT, NUMERIC, INT, INT) TO alimenta_app;

-- ============================================================
-- 2. reservar_inventario: busca lotes del MISMO TIPO (antes, de la misma
--    categoría). Misma firma que antes, así que conserva sus permisos.
--    Solo cambian dos líneas: d.id_tipo y el WHERE de lote.
-- ============================================================
CREATE OR REPLACE PROCEDURE reservar_inventario(
  p_id_solicitud INT,
  p_id_usuario   INT,
  INOUT p_id_reserva INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_estado_sol  VARCHAR(15);
  v_estado_ben  VARCHAR(15);
  d             RECORD;
  l             RECORD;
  v_falta       NUMERIC(10,2);
  v_toma        NUMERIC(10,2);
  v_hay_detalle BOOLEAN := FALSE;
BEGIN
  SELECT s.estado, b.estado
    INTO v_estado_sol, v_estado_ben
  FROM solicitud s
  JOIN beneficiario b ON b.id_beneficiario = s.id_beneficiario
  WHERE s.id_solicitud = p_id_solicitud
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La solicitud % no existe', p_id_solicitud;
  END IF;

  IF v_estado_sol <> 'pendiente' THEN
    RAISE EXCEPTION 'La solicitud % no está pendiente (estado actual: %)',
      p_id_solicitud, v_estado_sol;
  END IF;

  IF v_estado_ben <> 'activo' THEN
    RAISE EXCEPTION 'El beneficiario de la solicitud % no está activo', p_id_solicitud;
  END IF;

  INSERT INTO reserva (id_solicitud)
  VALUES (p_id_solicitud)
  RETURNING id_reserva INTO p_id_reserva;

  FOR d IN
    SELECT sd.id_tipo, sd.id_unidad, sd.cantidad_solicitada, t.nombre AS tipo
    FROM solicitud_detalle sd
    JOIN tipo_alimento t ON t.id_tipo = sd.id_tipo
    WHERE sd.id_solicitud = p_id_solicitud
    ORDER BY sd.id_detalle
  LOOP
    v_hay_detalle := TRUE;
    v_falta := d.cantidad_solicitada;

    FOR l IN
      SELECT id_lote, saldo
      FROM lote
      WHERE id_tipo = d.id_tipo                -- CAMBIO: tipo, no categoría
        AND id_unidad = d.id_unidad
        AND estado = 'activo'
        AND saldo > 0
        AND fecha_vencimiento >= CURRENT_DATE
      ORDER BY fecha_vencimiento, id_lote      -- FEFO: primero vence, primero sale
      FOR UPDATE
    LOOP
      v_toma := LEAST(l.saldo, v_falta);

      INSERT INTO reserva_detalle (id_reserva, id_lote, cantidad)
      VALUES (p_id_reserva, l.id_lote, v_toma);

      UPDATE lote
      SET saldo  = saldo - v_toma,
          estado = CASE WHEN saldo - v_toma = 0 THEN 'agotado' ELSE estado END
      WHERE id_lote = l.id_lote;

      INSERT INTO movimiento_inventario
        (id_lote, id_reserva, id_usuario, tipo, cantidad, motivo)
      VALUES (l.id_lote, p_id_reserva, p_id_usuario, 'reserva', v_toma, 'Reserva FEFO');

      v_falta := v_falta - v_toma;
      EXIT WHEN v_falta = 0;
    END LOOP;

    IF v_falta > 0 THEN
      RAISE EXCEPTION 'Inventario insuficiente de "%": faltan %', d.tipo, v_falta;
    END IF;
  END LOOP;

  IF NOT v_hay_detalle THEN
    RAISE EXCEPTION 'La solicitud % no tiene detalle', p_id_solicitud;
  END IF;

  UPDATE solicitud SET estado = 'reservada' WHERE id_solicitud = p_id_solicitud;
END;
$$;

-- ============================================================
-- 3. cancelar_solicitud: la cancela el PROPIO beneficiario
--    - Si está "pendiente": solo cambia de estado.
--    - Si está "reservada": además devuelve el inventario a los lotes.
--    - Si ya fue entregada, cancelada o rechazada: no se puede.
-- ============================================================
CREATE OR REPLACE PROCEDURE public.cancelar_solicitud(
  p_id_solicitud INT,
  p_id_usuario   INT,
  p_motivo       VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_estado     VARCHAR(15);
  v_id_reserva INT;
BEGIN
  -- 1) La solicitud debe existir y ser de ESTE usuario (no de otro)
  SELECT s.estado
    INTO v_estado
  FROM solicitud s
  JOIN beneficiario b ON b.id_beneficiario = s.id_beneficiario
  WHERE s.id_solicitud = p_id_solicitud
    AND b.id_usuario = p_id_usuario
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No encontramos esa solicitud entre las tuyas';
  END IF;

  IF v_estado NOT IN ('pendiente', 'reservada') THEN
    RAISE EXCEPTION 'La solicitud % ya no se puede cancelar (estado: %)',
      p_id_solicitud, v_estado;
  END IF;

  -- 2) Si tenía una reserva activa, devolver el inventario
  SELECT id_reserva INTO v_id_reserva
  FROM reserva
  WHERE id_solicitud = p_id_solicitud AND estado = 'activa'
  FOR UPDATE;

  IF v_id_reserva IS NOT NULL THEN
    UPDATE lote l
    SET saldo  = l.saldo + rd.cantidad,
        estado = CASE WHEN l.estado = 'agotado' THEN 'activo' ELSE l.estado END
    FROM reserva_detalle rd
    WHERE rd.id_reserva = v_id_reserva
      AND l.id_lote = rd.id_lote;

    INSERT INTO movimiento_inventario
      (id_lote, id_reserva, id_usuario, tipo, cantidad, motivo)
    SELECT rd.id_lote, v_id_reserva, p_id_usuario, 'liberacion', rd.cantidad,
           COALESCE(p_motivo, 'Cancelada por el beneficiario')
    FROM reserva_detalle rd
    WHERE rd.id_reserva = v_id_reserva;

    UPDATE reserva SET estado = 'cancelada' WHERE id_reserva = v_id_reserva;
  END IF;

  -- 3) Cerrar la solicitud
  UPDATE solicitud
  SET estado = 'cancelada',
      observacion = COALESCE(left(p_motivo, 300), observacion)
  WHERE id_solicitud = p_id_solicitud;
END;
$$;

REVOKE ALL ON PROCEDURE public.cancelar_solicitud(INT, INT, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.cancelar_solicitud(INT, INT, VARCHAR) TO alimenta_app;

COMMIT;
