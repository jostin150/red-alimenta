-- Pruebas de crear_solicitud
-- Muestra una tabla con 4 pruebas. No deja datos guardados: todo lo que
-- se crea durante la prueba se deshace automáticamente al terminar.

CREATE OR REPLACE FUNCTION pg_temp.probar_crear_solicitud()
RETURNS TABLE (prueba TEXT, resultado TEXT, detalle TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_id          INT;
  v_ben_usuario INT;
  v_gestor      INT;
  v_categoria   INT;
  v_unidad      INT;
  r_prueba      TEXT[] := '{}';
  r_resultado   TEXT[] := '{}';
  r_detalle     TEXT[] := '{}';
BEGIN
  BEGIN  -- todo lo que ocurra dentro de este bloque se deshace al final
    -- Buscamos datos que SÍ existen en tu base (los números pueden variar)
    SELECT id_usuario INTO v_ben_usuario
    FROM beneficiario WHERE estado = 'activo' AND consentimiento
    ORDER BY id_usuario LIMIT 1;

    SELECT ur.id_usuario INTO v_gestor
    FROM usuario_rol ur JOIN rol r ON r.id_rol = ur.id_rol
    WHERE r.nombre = 'gestor' ORDER BY ur.id_usuario LIMIT 1;

    SELECT id_categoria INTO v_categoria FROM categoria ORDER BY id_categoria LIMIT 1;
    SELECT id_unidad    INTO v_unidad    FROM unidad    ORDER BY id_unidad    LIMIT 1;

    -- 1) Caso feliz
    CALL crear_solicitud(v_ben_usuario, v_categoria, v_unidad, 5, v_id);
    r_prueba := array_append(r_prueba, ('1 solicitud válida')::text);
    IF EXISTS (SELECT 1 FROM solicitud s JOIN beneficiario b USING (id_beneficiario)
               WHERE s.id_solicitud = v_id AND b.id_usuario = v_ben_usuario
                 AND s.estado = 'pendiente') THEN
      r_resultado := array_append(r_resultado, ('OK')::text);
      r_detalle := array_append(r_detalle, (('se creó la solicitud pendiente número ' || v_id))::text);
    ELSE
      r_resultado := array_append(r_resultado, ('FALLÓ')::text);
      r_detalle := array_append(r_detalle, ('la solicitud no quedó pendiente')::text);
    END IF;

    -- 2) Cantidad cero
    r_prueba := array_append(r_prueba, ('2 cantidad 0')::text);
    BEGIN
      CALL crear_solicitud(v_ben_usuario, v_categoria, v_unidad, 0, v_id);
      r_resultado := array_append(r_resultado, ('FALLÓ')::text);
      r_detalle := array_append(r_detalle, ('debía rechazarla')::text);
    EXCEPTION WHEN OTHERS THEN
      r_resultado := array_append(r_resultado, ('OK')::text);
      r_detalle := array_append(r_detalle, (SQLERRM)::text);
    END;

    -- 3) Un gestor no es beneficiario
    r_prueba := array_append(r_prueba, ('3 gestor pide')::text);
    BEGIN
      CALL crear_solicitud(v_gestor, v_categoria, v_unidad, 5, v_id);
      r_resultado := array_append(r_resultado, ('FALLÓ')::text);
      r_detalle := array_append(r_detalle, ('debía rechazarla')::text);
    EXCEPTION WHEN OTHERS THEN
      r_resultado := array_append(r_resultado, ('OK')::text);
      r_detalle := array_append(r_detalle, (SQLERRM)::text);
    END;

    -- 4) Categoría inexistente
    r_prueba := array_append(r_prueba, ('4 categoría falsa')::text);
    BEGIN
      CALL crear_solicitud(v_ben_usuario, 999999, v_unidad, 5, v_id);
      r_resultado := array_append(r_resultado, ('FALLÓ')::text);
      r_detalle := array_append(r_detalle, ('debía rechazarla')::text);
    EXCEPTION WHEN OTHERS THEN
      r_resultado := array_append(r_resultado, ('OK')::text);
      r_detalle := array_append(r_detalle, (SQLERRM)::text);
    END;

    -- Forzamos un error a propósito para que PostgreSQL deshaga lo creado
    RAISE EXCEPTION 'deshacer_pruebas' USING ERRCODE = 'P0099';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN
    NULL;  -- esperado: los datos de prueba se deshicieron, los resultados quedan
  END;

  RETURN QUERY SELECT * FROM unnest(r_prueba, r_resultado, r_detalle);
END;
$$;

SELECT * FROM pg_temp.probar_crear_solicitud();