BEGIN;

-- ============================================================
--  saldo de un lote en una fecha
-- Sumar lo que entró y lo liberado, y resta lo reservado y lo vencido
-- ============================================================
CREATE OR REPLACE FUNCTION saldo_lote_a_fecha(p_id_lote INT, p_fecha DATE)
RETURNS NUMERIC(10,2)
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(SUM(CASE tipo
                        WHEN 'entrada'     THEN  cantidad
                        WHEN 'liberacion'  THEN  cantidad
                        WHEN 'reserva'     THEN -cantidad
                        WHEN 'vencimiento' THEN -cantidad
                        ELSE 0
                      END), 0)::NUMERIC(10,2)
  FROM movimiento_inventario
  WHERE id_lote = p_id_lote
    AND fecha < p_fecha + 1;
$$;

-- ============================================================
-- FUNCIÓN 2: tasa de aprovechamiento de un período
-- (entregado / donado) * 100, para una unidad de medida
-- ============================================================
CREATE OR REPLACE FUNCTION tasa_aprovechamiento(
  p_desde  DATE,
  p_hasta  DATE,
  p_unidad VARCHAR DEFAULT 'kg'
)
RETURNS NUMERIC(5,2)
LANGUAGE sql
STABLE
AS $$
  SELECT round(
           100.0 * COALESCE(SUM(m.cantidad) FILTER (WHERE m.tipo = 'salida'), 0)
                 / NULLIF(SUM(m.cantidad) FILTER (WHERE m.tipo = 'entrada'), 0),
           2)::NUMERIC(5,2)
  FROM movimiento_inventario m
  JOIN lote l   ON l.id_lote = m.id_lote
  JOIN unidad u ON u.id_unidad = l.id_unidad
  WHERE u.abreviatura = p_unidad
    AND m.fecha >= p_desde
    AND m.fecha <  p_hasta + 1;
$$;

-- ============================================================
-- TRIGGER 1: AUDITORÍA
-- Una sola función que se conecta a varias tablas
-- ============================================================
CREATE OR REPLACE FUNCTION auditar_cambio()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_clave   TEXT := TG_ARGV[0];
  v_usuario INT  := NULLIF(current_setting('app.id_usuario', true), '')::INT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    INSERT INTO auditoria (tabla, operacion, id_registro, datos_anteriores, id_usuario)
    VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD) ->> v_clave, to_jsonb(OLD), v_usuario);
    RETURN OLD;

  ELSIF TG_OP = 'INSERT' THEN
    INSERT INTO auditoria (tabla, operacion, id_registro, datos_nuevos, id_usuario)
    VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW) ->> v_clave, to_jsonb(NEW), v_usuario);
    RETURN NEW;

  ELSE
    INSERT INTO auditoria (tabla, operacion, id_registro, datos_anteriores, datos_nuevos, id_usuario)
    VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW) ->> v_clave,
            to_jsonb(OLD), to_jsonb(NEW), v_usuario);
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_auditoria_reserva ON reserva;
CREATE TRIGGER trg_auditoria_reserva
AFTER UPDATE ON reserva
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION auditar_cambio('id_reserva');

DROP TRIGGER IF EXISTS trg_auditoria_entrega ON entrega;
CREATE TRIGGER trg_auditoria_entrega
AFTER INSERT ON entrega
FOR EACH ROW
EXECUTE FUNCTION auditar_cambio('id_entrega');

DROP TRIGGER IF EXISTS trg_auditoria_usuario_rol ON usuario_rol;
CREATE TRIGGER trg_auditoria_usuario_rol
AFTER INSERT OR DELETE ON usuario_rol
FOR EACH ROW
EXECUTE FUNCTION auditar_cambio('id_usuario');

DROP TRIGGER IF EXISTS trg_auditoria_lote ON lote;
CREATE TRIGGER trg_auditoria_lote
AFTER UPDATE ON lote
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION auditar_cambio('id_lote');

-- ============================================================
-- TRIGGER 2: ESTADO DE RESERVA
-- Solo se permite pasar de 'activa' a entregada, cancelada o vencida
-- ============================================================
CREATE OR REPLACE FUNCTION validar_cambio_estado_reserva()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.estado = 'activa'
     AND NEW.estado IN ('entregada', 'cancelada', 'vencida') THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Cambio de estado no permitido en la reserva %: % -> %',
    OLD.id_reserva, OLD.estado, NEW.estado;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_estado_reserva ON reserva;
CREATE TRIGGER trg_validar_estado_reserva
BEFORE UPDATE OF estado ON reserva
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION validar_cambio_estado_reserva();

-- ============================================================
-- TRIGGER 3: LOTE VÁLIDO AL RESERVAR
-- ============================================================
CREATE OR REPLACE FUNCTION validar_lote_en_reserva()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_estado VARCHAR(15);
  v_venc   DATE;
  v_saldo  NUMERIC(10,2);
BEGIN
  SELECT estado, fecha_vencimiento, saldo
    INTO v_estado, v_venc, v_saldo
  FROM lote
  WHERE id_lote = NEW.id_lote;

  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'El lote % no está activo (estado: %)', NEW.id_lote, v_estado;
  END IF;

  IF v_venc < CURRENT_DATE THEN
    RAISE EXCEPTION 'El lote % está vencido (venció el %)', NEW.id_lote, v_venc;
  END IF;

  IF NEW.cantidad > v_saldo THEN
    RAISE EXCEPTION 'La cantidad % supera el saldo % del lote %',
      NEW.cantidad, v_saldo, NEW.id_lote;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_lote_en_reserva ON reserva_detalle;
CREATE TRIGGER trg_validar_lote_en_reserva
BEFORE INSERT ON reserva_detalle
FOR EACH ROW
EXECUTE FUNCTION validar_lote_en_reserva();

COMMIT;