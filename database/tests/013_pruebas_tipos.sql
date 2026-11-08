-- Pruebas de la migración 013 (tipos de alimento y punto de entrega).
-- Todo va dentro de BEGIN ... ROLLBACK: no deja datos guardados.
-- Resultados en la pestaña "Messages".
BEGIN;

DO $$
DECLARE
  v_n      INT;
  v_sede   INT;
  v_unidad INT;
  v_agua   INT;
  v_lacteo INT;
BEGIN
  -- Prueba 1: Carnes y Pescados son categorías separadas
  SELECT count(*) INTO v_n FROM categoria WHERE nombre IN ('Carnes', 'Pescados');
  RAISE NOTICE 'Prueba 1: % de 2 categorías (esperado: 2)', v_n;

  -- Prueba 2: toda categoría tiene su tipo "Otro"
  SELECT count(*) INTO v_n FROM categoria c
  WHERE NOT EXISTS (SELECT 1 FROM tipo_alimento t
                    WHERE t.id_categoria = c.id_categoria AND t.nombre = 'Otro');
  RAISE NOTICE 'Prueba 2: % categorías sin tipo Otro (esperado: 0)', v_n;

  -- Prueba 3: no se puede guardar un tipo dentro de una categoría que no es la suya
  SELECT id_sede INTO v_sede FROM sede ORDER BY id_sede LIMIT 1;
  SELECT id_unidad INTO v_unidad FROM unidad WHERE abreviatura = 'l';
  SELECT id_tipo INTO v_agua FROM tipo_alimento WHERE nombre = 'Agua';
  SELECT id_categoria INTO v_lacteo FROM categoria WHERE nombre = 'Lácteos';
  BEGIN
    INSERT INTO lote (id_sede, id_categoria, id_tipo, id_unidad, descripcion,
                      cantidad_inicial, saldo, fecha_vencimiento)
    VALUES (v_sede, v_lacteo, v_agua, v_unidad, 'Agua en Lácteos', 5, 5, CURRENT_DATE + 5);
    RAISE NOTICE 'Prueba 3 FALLO: aceptó Agua dentro de Lácteos';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'Prueba 3 OK: la base rechazó la combinación tipo/categoría';
  END;

  -- Prueba 4: dos tipos con el mismo nombre en la misma categoría no se permiten
  BEGIN
    INSERT INTO tipo_alimento (id_categoria, nombre)
    SELECT id_categoria, 'Agua' FROM tipo_alimento WHERE nombre = 'Agua';
    RAISE NOTICE 'Prueba 4 FALLO: aceptó un tipo repetido';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Prueba 4 OK: tipo repetido rechazado';
  END;
END $$;

ROLLBACK;
