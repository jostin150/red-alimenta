-- Pruebas de crear_solicitud
-- Se ejecutan dentro de una transacción y al final se deshacen (ROLLBACK),
-- así que no dejan datos de prueba en tu base.
BEGIN;

CREATE TEMP TABLE resultados (prueba TEXT, resultado TEXT, detalle TEXT);

DO $$
DECLARE
  v_id          INT;
  v_ben_usuario INT;
  v_gestor      INT;
  v_tipo        INT;
  v_punto       INT;
  v_unidad      INT;
BEGIN
  -- Buscamos datos que SÍ existen en tu base (los números pueden variar)
  SELECT id_usuario INTO v_ben_usuario
  FROM beneficiario WHERE estado = 'activo' AND consentimiento ORDER BY id_usuario LIMIT 1;

  SELECT ur.id_usuario INTO v_gestor
  FROM usuario_rol ur JOIN rol r ON r.id_rol = ur.id_rol
  WHERE r.nombre = 'gestor' ORDER BY ur.id_usuario LIMIT 1;

  SELECT id_tipo INTO v_tipo FROM tipo_alimento WHERE activo ORDER BY id_tipo LIMIT 1;
  SELECT id_punto INTO v_punto FROM punto_entrega WHERE activo ORDER BY id_punto LIMIT 1;
  SELECT id_unidad    INTO v_unidad    FROM unidad    ORDER BY id_unidad    LIMIT 1;

  -- 1) Caso feliz
  CALL crear_solicitud(v_ben_usuario, v_tipo, v_unidad, 5, v_punto, v_id);
  INSERT INTO resultados
  SELECT '1 solicitud válida', 'OK', 'se creó la solicitud pendiente número ' || v_id
  WHERE EXISTS (SELECT 1 FROM solicitud s JOIN beneficiario b USING (id_beneficiario)
                WHERE s.id_solicitud = v_id AND b.id_usuario = v_ben_usuario
                  AND s.estado = 'pendiente');

  -- 2) Cantidad cero
  BEGIN
    CALL crear_solicitud(v_ben_usuario, v_tipo, v_unidad, 0, v_punto, v_id);
    INSERT INTO resultados VALUES ('2 cantidad 0', 'FALLÓ', 'debía rechazarla');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultados VALUES ('2 cantidad 0', 'OK', SQLERRM);
  END;

  -- 3) Un gestor no es beneficiario
  BEGIN
    CALL crear_solicitud(v_gestor, v_tipo, v_unidad, 5, v_punto, v_id);
    INSERT INTO resultados VALUES ('3 gestor pide', 'FALLÓ', 'debía rechazarla');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultados VALUES ('3 gestor pide', 'OK', SQLERRM);
  END;

  -- 4) Tipo de alimento inexistente
  BEGIN
    CALL crear_solicitud(v_ben_usuario, 999999, v_unidad, 5, v_punto, v_id);
    INSERT INTO resultados VALUES ('4 tipo falso', 'FALLÓ', 'debía rechazarla');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultados VALUES ('4 tipo falso', 'OK', SQLERRM);
  END;

  -- 5) Sin punto de entrega
  BEGIN
    CALL crear_solicitud(v_ben_usuario, v_tipo, v_unidad, 5, NULL, v_id);
    INSERT INTO resultados VALUES ('5 sin punto de entrega', 'FALLÓ', 'debía rechazarla');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultados VALUES ('5 sin punto de entrega', 'OK', SQLERRM);
  END;
END $$;

SELECT * FROM resultados;
ROLLBACK;
