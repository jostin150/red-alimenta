-- Pruebas de la migración 014.
-- Todo va dentro de BEGIN ... ROLLBACK: no deja ningún dato guardado.
-- Los resultados salen en la pestaña "Messages" de pgAdmin.
BEGIN;

DO $$
DECLARE
  v_user   INT;
  v_tipo   INT;
  v_unidad INT;
  v_punto  INT;
  v_sol    INT;
  v_estado TEXT;
BEGIN
  SELECT b.id_usuario INTO v_user
  FROM beneficiario b JOIN usuario u ON u.id_usuario = b.id_usuario
  WHERE b.estado = 'activo' AND b.consentimiento AND u.activo
  ORDER BY b.id_usuario LIMIT 1;

  SELECT id_tipo   INTO v_tipo   FROM tipo_alimento WHERE nombre = 'Agua';
  SELECT id_unidad INTO v_unidad FROM unidad        WHERE abreviatura = 'l';
  SELECT id_punto  INTO v_punto  FROM punto_entrega WHERE activo ORDER BY id_punto LIMIT 1;

  -- Prueba 1: crear una solicitud de 2 litros de Agua
  CALL crear_solicitud(v_user, v_tipo, v_unidad, 2, v_punto, v_sol);
  RAISE NOTICE 'Prueba 1 OK: solicitud % creada', v_sol;

  -- Prueba 2: otro usuario NO puede cancelarla (debe fallar)
  BEGIN
    CALL cancelar_solicitud(v_sol, -1, 'intento ajeno');
    RAISE NOTICE 'Prueba 2 FALLO: un usuario ajeno pudo cancelar';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Prueba 2 OK: usuario ajeno rechazado (%)', SQLERRM;
  END;

  -- Prueba 3: el dueño la cancela
  CALL cancelar_solicitud(v_sol, v_user, 'prueba');
  SELECT estado INTO v_estado FROM solicitud WHERE id_solicitud = v_sol;
  RAISE NOTICE 'Prueba 3: estado final = % (esperado: cancelada)', v_estado;

  -- Prueba 4: cancelarla otra vez debe fallar
  BEGIN
    CALL cancelar_solicitud(v_sol, v_user, 'otra vez');
    RAISE NOTICE 'Prueba 4 FALLO: se canceló dos veces';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Prueba 4 OK: (%)', SQLERRM;
  END;

  -- Prueba 5: un tipo que no existe debe fallar
  BEGIN
    CALL crear_solicitud(v_user, -5, v_unidad, 2, v_punto, v_sol);
    RAISE NOTICE 'Prueba 5 FALLO: aceptó un tipo inexistente';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Prueba 5 OK: (%)', SQLERRM;
  END;
END $$;

ROLLBACK;
