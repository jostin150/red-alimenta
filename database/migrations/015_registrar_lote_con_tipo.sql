-- 015: registrar_lote ahora recibe el TIPO de alimento (Agua, Gaseosa, Arroz...).
--      La categoría se deduce del tipo, así no se pueden mezclar.
--
-- Requiere haber ejecutado antes la 013 y la 014.
-- Ejecutar UNA sola vez, en el Query Tool de la base "alimenta".
--
-- OJO: al terminar, el formulario "Registrar lote" de la aplicación falla
-- hasta que reemplaces app.py y lotes.html por los de esta carpeta.
BEGIN;

-- Se borra y se vuelve a crear porque cambia el nombre de un parámetro
-- (p_id_categoria -> p_id_tipo) y PostgreSQL no permite hacerlo con REPLACE.
DROP PROCEDURE IF EXISTS public.registrar_lote(INT, INT, INT, INT, VARCHAR, NUMERIC, DATE, INT);

CREATE PROCEDURE public.registrar_lote(
  p_id_usuario        INT,
  p_id_sede           INT,
  p_id_tipo           INT,
  p_id_unidad         INT,
  p_descripcion       VARCHAR,
  p_cantidad          NUMERIC,
  p_fecha_vencimiento DATE,
  INOUT p_id_lote     INT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id_categoria SMALLINT;
BEGIN
  -- 1) Debe ser un usuario activo con un rol autorizado
  IF NOT EXISTS (
    SELECT 1
    FROM usuario u
    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
    JOIN rol r ON r.id_rol = ur.id_rol
    WHERE u.id_usuario = p_id_usuario
      AND u.activo
      AND r.nombre IN ('gestor', 'administrador', 'donante')
  ) THEN
    RAISE EXCEPTION 'El usuario % no tiene permiso para registrar lotes', p_id_usuario;
  END IF;

  -- 2) Si NO es gestor ni administrador (o sea, es solo donante),
  --    la sede debe ser de su propio donante.
  IF NOT EXISTS (
    SELECT 1
    FROM usuario_rol ur
    JOIN rol r ON r.id_rol = ur.id_rol
    WHERE ur.id_usuario = p_id_usuario
      AND r.nombre IN ('gestor', 'administrador')
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM usuario_donante ud
      JOIN donante d ON d.id_donante = ud.id_donante AND d.activo
      JOIN sede s    ON s.id_donante = ud.id_donante
      WHERE ud.id_usuario = p_id_usuario
        AND s.id_sede = p_id_sede
    ) THEN
      RAISE EXCEPTION 'La sede % no pertenece a tu organización donante', p_id_sede;
    END IF;
  END IF;

  -- 3) El tipo debe existir y estar activo; de él sale la categoría
  SELECT id_categoria INTO v_id_categoria
  FROM tipo_alimento
  WHERE id_tipo = p_id_tipo AND activo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El tipo de alimento % no existe o no está disponible', p_id_tipo;
  END IF;

  INSERT INTO lote (id_sede, id_categoria, id_tipo, id_unidad, descripcion,
                    cantidad_inicial, saldo, fecha_vencimiento)
  VALUES (p_id_sede, v_id_categoria, p_id_tipo, p_id_unidad, p_descripcion,
          p_cantidad, p_cantidad, p_fecha_vencimiento)
  RETURNING id_lote INTO p_id_lote;

  INSERT INTO movimiento_inventario (id_lote, id_usuario, tipo, cantidad, motivo)
  VALUES (p_id_lote, p_id_usuario, 'entrada', p_cantidad, 'Recepción de donación');
END;
$$;

REVOKE ALL ON PROCEDURE public.registrar_lote(INT, INT, INT, INT, VARCHAR, NUMERIC, DATE, INT) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.registrar_lote(INT, INT, INT, INT, VARCHAR, NUMERIC, DATE, INT) TO alimenta_app;

COMMIT;
