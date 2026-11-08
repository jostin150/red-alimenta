-- Prueba de la 017: reservar para un beneficiario SIN consentimiento debe fallar.
-- Todo va dentro de BEGIN ... ROLLBACK: no deja datos guardados.
-- El resultado sale en la pestaña "Messages".
BEGIN;

DO $$
DECLARE
  v_user   INT;
  v_gestor INT;
  v_tipo   INT;
  v_unidad INT;
  v_punto  INT;
  v_sol    INT;
  v_res    INT;
BEGIN
  SELECT b.id_usuario INTO v_user
  FROM beneficiario b JOIN usuario u ON u.id_usuario = b.id_usuario
  WHERE b.estado = 'activo' AND b.consentimiento AND u.activo
  ORDER BY b.id_usuario LIMIT 1;

  SELECT ur.id_usuario INTO v_gestor
  FROM usuario_rol ur JOIN rol r ON r.id_rol = ur.id_rol
  WHERE r.nombre = 'gestor' ORDER BY ur.id_usuario LIMIT 1;

  SELECT id_tipo   INTO v_tipo   FROM tipo_alimento WHERE nombre = 'Agua';
  SELECT id_unidad INTO v_unidad FROM unidad WHERE abreviatura = 'l';
  SELECT id_punto  INTO v_punto  FROM punto_entrega WHERE activo ORDER BY id_punto LIMIT 1;

  CALL crear_solicitud(v_user, v_tipo, v_unidad, 1, v_punto, v_sol);

  -- Le quitamos el consentimiento (dentro de la prueba; se deshace al final)
  UPDATE beneficiario SET consentimiento = FALSE, fecha_consentimiento = NULL
  WHERE id_usuario = v_user;

  BEGIN
    CALL reservar_inventario(v_sol, v_gestor, v_res);
    RAISE NOTICE 'PRUEBA FALLO: reservó para alguien sin consentimiento';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PRUEBA OK: (%)', SQLERRM;
  END;
END $$;

ROLLBACK;
