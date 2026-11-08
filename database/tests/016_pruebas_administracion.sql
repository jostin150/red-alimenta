-- Pruebas de la migración 016. Todo va dentro de BEGIN ... ROLLBACK:
-- no deja datos guardados. Resultados en la pestaña "Messages".
BEGIN;

DO $$
DECLARE
  v_admin INT;
  v_otro  INT;
  v_cat   INT;
  v_nuevo INT;
BEGIN
  SELECT ur.id_usuario INTO v_admin
  FROM usuario_rol ur JOIN rol r ON r.id_rol = ur.id_rol
  WHERE r.nombre = 'administrador' ORDER BY ur.id_usuario LIMIT 1;

  SELECT ur.id_usuario INTO v_otro
  FROM usuario_rol ur JOIN rol r ON r.id_rol = ur.id_rol
  WHERE r.nombre = 'beneficiario' ORDER BY ur.id_usuario LIMIT 1;

  -- Prueba 1: un administrador crea una categoría y un tipo
  CALL admin_guardar_categoria(v_admin, NULL, 'Categoría de prueba');
  SELECT id_categoria INTO v_cat FROM categoria WHERE nombre = 'Categoría de prueba';
  CALL admin_guardar_tipo(v_admin, NULL, v_cat, 'Tipo de prueba', TRUE);
  RAISE NOTICE 'Prueba 1 OK: categoría % y su tipo creados', v_cat;

  -- Prueba 2: alguien que NO es administrador debe ser rechazado
  BEGIN
    CALL admin_guardar_categoria(v_otro, NULL, 'No debería existir');
    RAISE NOTICE 'Prueba 2 FALLO: un beneficiario pudo crear una categoría';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Prueba 2 OK: (%)', SQLERRM;
  END;

  -- Prueba 3: el administrador no puede desactivarse a sí mismo
  BEGIN
    CALL admin_estado_usuario(v_admin, v_admin, FALSE);
    RAISE NOTICE 'Prueba 3 FALLO: el administrador se desactivó';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Prueba 3 OK: (%)', SQLERRM;
  END;

  -- Prueba 4: no se puede crear un beneficiario por aquí
  BEGIN
    CALL admin_crear_usuario(v_admin, 'Prueba', 'prueba@alimenta.test', 'x', 'beneficiario', NULL, NULL);
    RAISE NOTICE 'Prueba 4 FALLO: creó un beneficiario';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Prueba 4 OK: (%)', SQLERRM;
  END;

  -- Prueba 5: crear un gestor y quitarle el rol
  CALL admin_crear_usuario(v_admin, 'Gestor de prueba', 'gestor.prueba@alimenta.test', 'x', 'gestor', NULL, v_nuevo);
  CALL admin_quitar_rol(v_admin, v_nuevo, 'gestor');
  RAISE NOTICE 'Prueba 5 OK: usuario % creado y rol quitado', v_nuevo;

  -- Prueba 6: un donante exige una organización
  BEGIN
    CALL admin_asignar_rol(v_admin, v_nuevo, 'donante', NULL);
    RAISE NOTICE 'Prueba 6 FALLO: asignó donante sin organización';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Prueba 6 OK: (%)', SQLERRM;
  END;
END $$;

ROLLBACK;
