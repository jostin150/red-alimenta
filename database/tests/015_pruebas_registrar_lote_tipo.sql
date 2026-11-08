-- Pruebas de la migración 015. Todo va dentro de BEGIN ... ROLLBACK:
-- no deja datos guardados. Resultados en la pestaña "Messages".
BEGIN;

DO $$
DECLARE
  v_user   INT;
  v_sede   INT;
  v_tipo   INT;
  v_unidad INT;
  v_lote   INT;
  v_cat    TEXT;
BEGIN
  SELECT ur.id_usuario INTO v_user
  FROM usuario_rol ur JOIN rol r ON r.id_rol = ur.id_rol
  JOIN usuario u ON u.id_usuario = ur.id_usuario
  WHERE r.nombre = 'gestor' AND u.activo
  ORDER BY ur.id_usuario LIMIT 1;

  SELECT id_sede   INTO v_sede   FROM sede ORDER BY id_sede LIMIT 1;
  SELECT id_tipo   INTO v_tipo   FROM tipo_alimento WHERE nombre = 'Agua';
  SELECT id_unidad INTO v_unidad FROM unidad WHERE abreviatura = 'l';

  -- Prueba 1: registrar un lote de Agua
  CALL registrar_lote(v_user, v_sede, v_tipo, v_unidad,
                      'Prueba agua', 10, CURRENT_DATE + 30, v_lote);
  SELECT c.nombre INTO v_cat
  FROM lote l JOIN categoria c ON c.id_categoria = l.id_categoria
  WHERE l.id_lote = v_lote;
  RAISE NOTICE 'Prueba 1: lote % creado, categoría = % (esperado: Bebidas)', v_lote, v_cat;

  -- Prueba 2: un tipo que no existe debe fallar
  BEGIN
    CALL registrar_lote(v_user, v_sede, -5, v_unidad,
                        'Prueba mala', 10, CURRENT_DATE + 30, v_lote);
    RAISE NOTICE 'Prueba 2 FALLO: aceptó un tipo inexistente';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Prueba 2 OK: (%)', SQLERRM;
  END;
END $$;

ROLLBACK;
