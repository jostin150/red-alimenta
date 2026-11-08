-- Pruebas de registrar_lote con usuarios donantes.
-- Se ejecuta completo con F5 y muestra una tabla de resultados.
-- No deja datos: todo lo que crea se deshace al final.
CREATE OR REPLACE FUNCTION pg_temp.probar_registrar_lote()
RETURNS TABLE (prueba TEXT, resultado TEXT, detalle TEXT)
LANGUAGE plpgsql AS $$
DECLARE
  v_res        JSONB := '[]'::jsonb;
  v_donante    INT;   -- usuario donante2
  v_sede_propia INT;
  v_sede_ajena  INT;
  v_ben        INT;   -- un beneficiario
  v_gestor     INT;
  v_tipo       INT;
  v_uni        INT;
  v_id         INT;
  v_mov        INT;
BEGIN
  BEGIN  -- zona de pruebas: todo lo de aquí dentro se deshace al final
    SELECT id_usuario INTO v_donante FROM usuario WHERE correo = 'donante2@alimenta.test';
    SELECT id_usuario INTO v_ben     FROM usuario WHERE correo = 'beneficiario1@alimenta.test';
    SELECT id_usuario INTO v_gestor  FROM usuario WHERE correo = 'gestor1@alimenta.test';
    SELECT min(s.id_sede) INTO v_sede_propia
      FROM sede s JOIN usuario_donante ud ON ud.id_donante = s.id_donante
      WHERE ud.id_usuario = v_donante;
    SELECT min(s.id_sede) INTO v_sede_ajena
      FROM sede s
      WHERE s.id_donante NOT IN (SELECT id_donante FROM usuario_donante WHERE id_usuario = v_donante);
    SELECT min(id_tipo) INTO v_tipo FROM tipo_alimento WHERE activo;
    SELECT min(id_unidad)    INTO v_uni FROM unidad;

    -- 1) Donante registra en su propia sede -> debe funcionar y crear la entrada
    BEGIN
      CALL registrar_lote(v_donante, v_sede_propia, v_tipo, v_uni,
                          'Prueba donante propia', 10, CURRENT_DATE + 5, v_id);
      SELECT count(*) INTO v_mov FROM movimiento_inventario
        WHERE id_lote = v_id AND tipo = 'entrada';
      IF v_mov = 1 THEN
        v_res := v_res || jsonb_build_array(jsonb_build_array('1 donante, su sede', 'OK', 'lote ' || v_id || ' con su movimiento de entrada'));
      ELSE
        v_res := v_res || jsonb_build_array(jsonb_build_array('1 donante, su sede', 'FALLÓ', 'no creó el movimiento de entrada'));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_res := v_res || jsonb_build_array(jsonb_build_array('1 donante, su sede', 'FALLÓ', SQLERRM));
    END;

    -- 2) Donante intenta registrar en sede de OTRO donante -> debe rechazarse
    BEGIN
      CALL registrar_lote(v_donante, v_sede_ajena, v_tipo, v_uni,
                          'Prueba sede ajena', 10, CURRENT_DATE + 5, v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_array('2 donante, sede ajena', 'FALLÓ', 'debía rechazarlo'));
    EXCEPTION WHEN OTHERS THEN
      v_res := v_res || jsonb_build_array(jsonb_build_array('2 donante, sede ajena', 'OK', SQLERRM));
    END;

    -- 3) Beneficiario intenta registrar -> debe rechazarse
    BEGIN
      CALL registrar_lote(v_ben, v_sede_propia, v_tipo, v_uni,
                          'Prueba beneficiario', 10, CURRENT_DATE + 5, v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_array('3 beneficiario', 'FALLÓ', 'debía rechazarlo'));
    EXCEPTION WHEN OTHERS THEN
      v_res := v_res || jsonb_build_array(jsonb_build_array('3 beneficiario', 'OK', SQLERRM));
    END;

    -- 4) Gestor registra en cualquier sede -> debe funcionar
    BEGIN
      CALL registrar_lote(v_gestor, v_sede_ajena, v_tipo, v_uni,
                          'Prueba gestor', 10, CURRENT_DATE + 5, v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_array('4 gestor, cualquier sede', 'OK', 'lote ' || v_id));
    EXCEPTION WHEN OTHERS THEN
      v_res := v_res || jsonb_build_array(jsonb_build_array('4 gestor, cualquier sede', 'FALLÓ', SQLERRM));
    END;

    -- 5) Cantidad cero -> debe rechazarse
    BEGIN
      CALL registrar_lote(v_donante, v_sede_propia, v_tipo, v_uni,
                          'Prueba cantidad cero', 0, CURRENT_DATE + 5, v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_array('5 cantidad cero', 'FALLÓ', 'debía rechazarlo'));
    EXCEPTION WHEN OTHERS THEN
      v_res := v_res || jsonb_build_array(jsonb_build_array('5 cantidad cero', 'OK', SQLERRM));
    END;

    -- 6) Fecha de vencimiento ya pasada -> debe rechazarse
    BEGIN
      CALL registrar_lote(v_donante, v_sede_propia, v_tipo, v_uni,
                          'Prueba vencido', 10, CURRENT_DATE - 3, v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_array('6 fecha pasada', 'FALLÓ', 'debía rechazarlo'));
    EXCEPTION WHEN OTHERS THEN
      v_res := v_res || jsonb_build_array(jsonb_build_array('6 fecha pasada', 'OK', SQLERRM));
    END;

    RAISE EXCEPTION 'deshacer_pruebas';   -- fuerza el deshacer de los lotes de prueba
  EXCEPTION WHEN OTHERS THEN
    NULL;   -- la base vuelve a como estaba; v_res conserva los resultados
  END;

  RETURN QUERY
    SELECT e->>0, e->>1, e->>2 FROM jsonb_array_elements(v_res) AS e;
END;
$$;

SELECT * FROM pg_temp.probar_registrar_lote();
