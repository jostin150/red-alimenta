BEGIN;


CREATE OR REPLACE PROCEDURE confirmar_entrega(
  p_id_reserva  INT,
  p_id_usuario  INT,
  p_observacion VARCHAR DEFAULT NULL,
  INOUT p_id_entrega INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_estado_res  VARCHAR(15);
  v_id_solicitud INT;
  v_vencidos    INT;
BEGIN
  -- n gestor o administrador activo puede confirmar
  IF NOT EXISTS (
    SELECT 1
    FROM usuario u
    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
    JOIN rol r ON r.id_rol = ur.id_rol
    WHERE u.id_usuario = p_id_usuario
      AND u.activo
      AND r.nombre IN ('gestor', 'administrador')
  ) THEN
    RAISE EXCEPTION 'El usuario % no tiene permiso para confirmar entregas', p_id_usuario;
  END IF;

  --  Bloquear  reserva y revisar su estado
  SELECT estado, id_solicitud
    INTO v_estado_res, v_id_solicitud
  FROM reserva
  WHERE id_reserva = p_id_reserva
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La reserva % no existe', p_id_reserva;
  END IF;

  IF v_estado_res <> 'activa' THEN
    RAISE EXCEPTION 'La reserva % no está activa (estado actual: %)',
      p_id_reserva, v_estado_res;
  END IF;

  -- Ne entrega comida vencida
  SELECT count(*) INTO v_vencidos
  FROM reserva_detalle rd
  JOIN lote l ON l.id_lote = rd.id_lote
  WHERE rd.id_reserva = p_id_reserva
    AND l.fecha_vencimiento < CURRENT_DATE;

  IF v_vencidos > 0 THEN
    RAISE EXCEPTION 'La reserva % incluye % lote(s) vencido(s); debe cancelarse',
      p_id_reserva, v_vencidos;
  END IF;

  -- Registrar la entrega
  INSERT INTO entrega (id_reserva, id_usuario_gestor, observacion)
  VALUES (p_id_reserva, p_id_usuario, p_observacion)
  RETURNING id_entrega INTO p_id_entrega;

  
  INSERT INTO movimiento_inventario
    (id_lote, id_reserva, id_usuario, tipo, cantidad, motivo)
  SELECT rd.id_lote, p_id_reserva, p_id_usuario, 'salida', rd.cantidad,
         'Entrega al beneficiario'
  FROM reserva_detalle rd
  WHERE rd.id_reserva = p_id_reserva;

  --  Actualizar estados
  UPDATE reserva SET estado = 'entregada' WHERE id_reserva = p_id_reserva;

  UPDATE solicitud
  SET estado = 'entregada'
  WHERE id_solicitud = v_id_solicitud
    AND NOT EXISTS (
      SELECT 1 FROM reserva
      WHERE id_solicitud = v_id_solicitud AND estado = 'activa'
    );
END;
$$;


-- CANCELAR RESERVA

CREATE OR REPLACE PROCEDURE cancelar_reserva(
  p_id_reserva INT,
  p_id_usuario INT,
  p_motivo     VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_estado_res   VARCHAR(15);
  v_id_solicitud INT;
BEGIN
  --  gestor o administrador  puede cancelar
  IF NOT EXISTS (
    SELECT 1
    FROM usuario u
    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
    JOIN rol r ON r.id_rol = ur.id_rol
    WHERE u.id_usuario = p_id_usuario
      AND u.activo
      AND r.nombre IN ('gestor', 'administrador')
  ) THEN
    RAISE EXCEPTION 'El usuario % no tiene permiso para cancelar reservas', p_id_usuario;
  END IF;

  --  Bloquear  reserva y revisar su estado
  SELECT estado, id_solicitud
    INTO v_estado_res, v_id_solicitud
  FROM reserva
  WHERE id_reserva = p_id_reserva
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La reserva % no existe', p_id_reserva;
  END IF;

  IF v_estado_res <> 'activa' THEN
    RAISE EXCEPTION 'Solo se cancelan reservas activas; la reserva % está %',
      p_id_reserva, v_estado_res;
  END IF;

  --  Devolver  saldo a cada lote
  UPDATE lote l
  SET saldo  = l.saldo + rd.cantidad,
      estado = CASE WHEN l.estado = 'agotado' THEN 'activo' ELSE l.estado END
  FROM reserva_detalle rd
  WHERE rd.id_reserva = p_id_reserva
    AND l.id_lote = rd.id_lote;


  INSERT INTO movimiento_inventario
    (id_lote, id_reserva, id_usuario, tipo, cantidad, motivo)
  SELECT rd.id_lote, p_id_reserva, p_id_usuario, 'liberacion', rd.cantidad,
         COALESCE(p_motivo, 'Reserva cancelada')
  FROM reserva_detalle rd
  WHERE rd.id_reserva = p_id_reserva;

  --  Actualizar estados
  UPDATE reserva SET estado = 'cancelada' WHERE id_reserva = p_id_reserva;

  UPDATE solicitud
  SET estado = 'cancelada'
  WHERE id_solicitud = v_id_solicitud
    AND NOT EXISTS (
      SELECT 1 FROM reserva
      WHERE id_solicitud = v_id_solicitud AND estado IN ('activa', 'entregada')
    );
END;
$$;

COMMIT;