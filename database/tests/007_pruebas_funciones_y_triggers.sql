DROP TABLE IF EXISTS resultados_prueba;
CREATE TEMP TABLE resultados_prueba (
  prueba    TEXT,
  resultado TEXT,
  detalle   TEXT
);

-- PRUEBA 0: ¿hay datos cargados?
INSERT INTO resultados_prueba
SELECT 'PRUEBA 0', 'INFO',
       'lotes=' || (SELECT count(*) FROM lote) ||
       ', reservas=' || (SELECT count(*) FROM reserva) ||
       ', movimientos=' || (SELECT count(*) FROM movimiento_inventario) ||
       ', auditoria=' || (SELECT count(*) FROM auditoria);

-- PRUEBA 1: saldo de la función vs saldo guardado en la tabla lote
DO $$
DECLARE
  v_total      INT;
  v_diferentes INT;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE saldo_lote_a_fecha(id_lote, CURRENT_DATE) <> saldo)
    INTO v_total, v_diferentes
  FROM lote;

  INSERT INTO resultados_prueba VALUES (
    'PRUEBA 1',
    CASE WHEN v_total = 0 THEN 'OMITIDA'
         WHEN v_diferentes = 0 THEN 'OK'
         ELSE 'REVISAR' END,
    v_total || ' lotes revisados, ' || v_diferentes || ' con saldo distinto');
END $$;

-- PRUEBA 2: la tasa de aprovechamiento debe estar entre 0 y 100
DO $$
DECLARE
  v_tasa NUMERIC;
BEGIN
  v_tasa := tasa_aprovechamiento(DATE '2026-01-01', DATE '2026-12-31', 'kg');

  INSERT INTO resultados_prueba VALUES (
    'PRUEBA 2',
    CASE WHEN v_tasa IS NULL THEN 'FALLÓ'
         WHEN v_tasa BETWEEN 0 AND 100 THEN 'OK'
         ELSE 'FALLÓ' END,
    'tasa = ' || COALESCE(v_tasa::TEXT, 'NULL (no hay entradas en kg en ese período)'));
END $$;

-- PRUEBA 3 (negativa): una reserva no activa NO puede volver a 'activa'
DO $$
DECLARE
  v_id  INT;
  v_res TEXT;
  v_det TEXT;
BEGIN
  SELECT id_reserva INTO v_id FROM reserva WHERE estado <> 'activa' LIMIT 1;

  IF v_id IS NULL THEN
    v_res := 'OMITIDA';
    v_det := 'no hay reservas que no estén activas en los datos de prueba';
  ELSE
    BEGIN
      UPDATE reserva SET estado = 'activa' WHERE id_reserva = v_id;
      v_res := 'FALLÓ';
      v_det := 'la base permitió reactivar la reserva ' || v_id;
      RAISE EXCEPTION 'deshacer_prueba';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM = 'deshacer_prueba' THEN
        NULL;  -- el FALLÓ ya quedó en las variables
      ELSE
        v_res := 'OK';
        v_det := 'la base rechazó el cambio: ' || SQLERRM;
      END IF;
    END;
  END IF;

  INSERT INTO resultados_prueba VALUES ('PRUEBA 3', v_res, v_det);
END $$;

-- PRUEBA 4 (positiva): cancelar una reserva activa deja auditoría con el usuario
DO $$
DECLARE
  v_reserva INT;
  v_usuario INT;
  v_antes   INT;
  v_despues INT;
  v_actor   INT;
  v_res_a   TEXT := 'FALLÓ';
  v_det_a   TEXT := '';
  v_res_b   TEXT := 'FALLÓ';
  v_det_b   TEXT := '';
BEGIN
  SELECT id_reserva INTO v_reserva FROM reserva WHERE estado = 'activa' LIMIT 1;
  SELECT id_usuario INTO v_usuario FROM usuario ORDER BY id_usuario LIMIT 1;

  IF v_reserva IS NULL THEN
    INSERT INTO resultados_prueba VALUES
      ('PRUEBA 4', 'OMITIDA', 'no hay reservas activas en los datos de prueba');
    RETURN;
  END IF;

  BEGIN
    PERFORM set_config('app.id_usuario', v_usuario::TEXT, true);

    SELECT count(*) INTO v_antes FROM auditoria WHERE tabla = 'reserva';

    UPDATE reserva SET estado = 'cancelada' WHERE id_reserva = v_reserva;

    SELECT count(*) INTO v_despues FROM auditoria WHERE tabla = 'reserva';

    SELECT id_usuario INTO v_actor
    FROM auditoria
    WHERE tabla = 'reserva'
      AND id_registro = v_reserva::TEXT
      AND datos_nuevos ->> 'estado' = 'cancelada'
    LIMIT 1;

    IF v_despues = v_antes + 1 THEN
      v_res_a := 'OK';
    END IF;
    v_det_a := 'filas de auditoría antes=' || v_antes || ', después=' || v_despues;

    IF v_actor = v_usuario THEN
      v_res_b := 'OK';
    END IF;
    v_det_b := 'usuario esperado=' || v_usuario || ', guardado=' || COALESCE(v_actor::TEXT, 'NULL');

    RAISE EXCEPTION 'deshacer_prueba';   -- deshace el UPDATE y la auditoría
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'deshacer_prueba' THEN
      v_res_a := 'FALLÓ';
      v_det_a := 'error inesperado: ' || SQLERRM;
      v_res_b := 'FALLÓ';
      v_det_b := 'no se pudo probar';
    END IF;
  END;

  INSERT INTO resultados_prueba VALUES ('PRUEBA 4a', v_res_a, v_det_a);
  INSERT INTO resultados_prueba VALUES ('PRUEBA 4b', v_res_b, v_det_b);
END $$;

-- PRUEBA 5: las reservas quedaron como estaban
INSERT INTO resultados_prueba
SELECT 'PRUEBA 5', 'INFO',
       COALESCE(string_agg(estado || '=' || n, ', ' ORDER BY estado), 'sin reservas')
FROM (SELECT estado, count(*) AS n FROM reserva GROUP BY estado) t;

-- RESULTADO FINAL (esto es lo que ves en Data Output)
SELECT * FROM resultados_prueba ORDER BY prueba;

