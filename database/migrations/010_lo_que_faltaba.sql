BEGIN;

CREATE TABLE punto_entrega (
  id_punto  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre    VARCHAR(100) NOT NULL UNIQUE,
  direccion VARCHAR(200) NOT NULL,
  comuna    VARCHAR(60),
  activo    BOOLEAN NOT NULL DEFAULT TRUE
);

ALTER TABLE entrega ADD COLUMN id_punto INT REFERENCES punto_entrega(id_punto);
CREATE INDEX idx_entrega_punto ON entrega (id_punto);

ALTER TABLE beneficiario
  ADD COLUMN consentimiento BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN fecha_consentimiento TIMESTAMPTZ,
  ADD CONSTRAINT ck_consentimiento_fecha
    CHECK (NOT consentimiento OR fecha_consentimiento IS NOT NULL);

CREATE OR REPLACE PROCEDURE marcar_lotes_vencidos(
  p_id_usuario INT,
  INOUT p_lotes_marcados INT DEFAULT 0
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM usuario u
    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
    JOIN rol r ON r.id_rol = ur.id_rol
    WHERE u.id_usuario = p_id_usuario
      AND u.activo
      AND r.nombre IN ('gestor', 'administrador')
  ) THEN
    RAISE EXCEPTION 'El usuario % no tiene permiso para marcar lotes vencidos', p_id_usuario;
  END IF;

  WITH vencidos AS (
    SELECT id_lote, saldo
    FROM lote
    WHERE fecha_vencimiento < CURRENT_DATE
      AND saldo > 0
      AND estado IN ('activo', 'vencido')
    FOR UPDATE
  ), perdidas AS (
    INSERT INTO movimiento_inventario (id_lote, id_usuario, tipo, cantidad, motivo)
    SELECT id_lote, p_id_usuario, 'vencimiento', saldo, 'Lote vencido'
    FROM vencidos
    RETURNING id_lote
  )
  UPDATE lote l
  SET saldo = 0, estado = 'vencido'
  FROM vencidos v
  WHERE l.id_lote = v.id_lote;

  GET DIAGNOSTICS p_lotes_marcados = ROW_COUNT;
END;
$$;

DROP PROCEDURE IF EXISTS confirmar_entrega(INT, INT, VARCHAR, INT);

CREATE OR REPLACE PROCEDURE confirmar_entrega(
  p_id_reserva  INT,
  p_id_usuario  INT,
  p_id_punto    INT,
  p_observacion VARCHAR DEFAULT NULL,
  INOUT p_id_entrega INT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_estado_res   VARCHAR(15);
  v_id_solicitud INT;
  v_vencidos     INT;
BEGIN
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

  IF NOT EXISTS (
    SELECT 1 FROM punto_entrega WHERE id_punto = p_id_punto AND activo
  ) THEN
    RAISE EXCEPTION 'El punto de entrega % no existe o está inactivo', p_id_punto;
  END IF;

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

  SELECT count(*) INTO v_vencidos
  FROM reserva_detalle rd
  JOIN lote l ON l.id_lote = rd.id_lote
  WHERE rd.id_reserva = p_id_reserva
    AND l.fecha_vencimiento < CURRENT_DATE;

  IF v_vencidos > 0 THEN
    RAISE EXCEPTION 'La reserva % incluye % lote(s) vencido(s); debe cancelarse',
      p_id_reserva, v_vencidos;
  END IF;

  INSERT INTO entrega (id_reserva, id_usuario_gestor, id_punto, observacion)
  VALUES (p_id_reserva, p_id_usuario, p_id_punto, p_observacion)
  RETURNING id_entrega INTO p_id_entrega;

  INSERT INTO movimiento_inventario
    (id_lote, id_reserva, id_usuario, tipo, cantidad, motivo)
  SELECT rd.id_lote, p_id_reserva, p_id_usuario, 'salida', rd.cantidad,
         'Entrega al beneficiario'
  FROM reserva_detalle rd
  WHERE rd.id_reserva = p_id_reserva;

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

CREATE OR REPLACE PROCEDURE reservar_inventario(
  p_id_solicitud INT,
  p_id_usuario   INT,
  INOUT p_id_reserva INT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_estado_sol  VARCHAR(15);
  v_estado_ben  VARCHAR(15);
  v_consent     BOOLEAN;
  d             RECORD;
  l             RECORD;
  v_falta       NUMERIC(10,2);
  v_toma        NUMERIC(10,2);
  v_hay_detalle BOOLEAN := FALSE;
BEGIN
  SELECT s.estado, b.estado, b.consentimiento
    INTO v_estado_sol, v_estado_ben, v_consent
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

  IF NOT v_consent THEN
    RAISE EXCEPTION 'El beneficiario de la solicitud % no ha dado su consentimiento', p_id_solicitud;
  END IF;

  INSERT INTO reserva (id_solicitud)
  VALUES (p_id_solicitud)
  RETURNING id_reserva INTO p_id_reserva;

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

  UPDATE solicitud SET estado = 'reservada' WHERE id_solicitud = p_id_solicitud;
END;
$$;

CREATE OR REPLACE FUNCTION impedir_borrado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'No se permite borrar registros de %: use estados o anulación trazable', TG_TABLE_NAME;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION impedir_modificacion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'La tabla % es de solo agregar: no se permite % de filas', TG_TABLE_NAME, TG_OP;
  RETURN NULL;
END;
$$;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['lote', 'solicitud', 'solicitud_detalle',
                           'reserva', 'reserva_detalle', 'entrega']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_no_borrar ON %I', t);
    EXECUTE format('CREATE TRIGGER trg_no_borrar BEFORE DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION impedir_borrado()', t);
  END LOOP;

  FOREACH t IN ARRAY ARRAY['movimiento_inventario', 'auditoria']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_solo_agregar ON %I', t);
    EXECUTE format('CREATE TRIGGER trg_solo_agregar BEFORE UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION impedir_modificacion()', t);
  END LOOP;
END $$;

GRANT SELECT, INSERT, UPDATE ON punto_entrega TO alimenta_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO alimenta_app;

GRANT EXECUTE ON PROCEDURE confirmar_entrega(INT, INT, INT, VARCHAR, INT) TO alimenta_app;
GRANT EXECUTE ON PROCEDURE marcar_lotes_vencidos(INT, INT)                 TO alimenta_app;

COMMIT;