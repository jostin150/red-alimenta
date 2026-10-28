BEGIN;

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
  -- 1. Bloquear la solicitud y revisar que se pueda reservar
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

  -- 2. Crear la reserva
  INSERT INTO reserva (id_solicitud)
  VALUES (p_id_solicitud)
  RETURNING id_reserva INTO p_id_reserva;

  -- 3. Por cada categoría pedida, tomar lotes en orden FEFO
  FOR d IN
    SELECT id_categoria, id_unidad, cantidad_solicitada
    FROM solicitud_detalle
    WHERE id_solicitud = p_id_solicitud
    ORDER BY id_detalle
  LOOP
    v_hay_detalle := TRUE;
    v_falta := d.cantidad_solicitada;

    FOR l IN
      SELECT id_lote, saldo
      FROM lote
      WHERE id_categoria = d.id_categoria
        AND id_unidad = d.id_unidad
        AND estado = 'activo'
        AND saldo > 0
        AND fecha_vencimiento >= CURRENT_DATE
      ORDER BY fecha_vencimiento, id_lote
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
      RAISE EXCEPTION 'Inventario insuficiente para la categoría %: faltan %',
        d.id_categoria, v_falta;
    END IF;
  END LOOP;

  IF NOT v_hay_detalle THEN
    RAISE EXCEPTION 'La solicitud % no tiene detalle', p_id_solicitud;
  END IF;

  -- 4. Marcar la solicitud como reservada
  UPDATE solicitud SET estado = 'reservada' WHERE id_solicitud = p_id_solicitud;
END;
$$;

COMMIT;