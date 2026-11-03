-- 012: vincula cada usuario con rol "donante" a su organización donante
--      y hace que registrar_lote solo deje registrar en SUS sedes.
--
-- Antes: un usuario "donante" podía registrar un lote en la sede de
-- cualquier otro donante, porque nada decía a qué donante pertenecía.
BEGIN;

-- Un usuario pertenece a UN donante (llave primaria = id_usuario).
-- Un donante puede tener varios usuarios.
CREATE TABLE usuario_donante (
  id_usuario INT PRIMARY KEY REFERENCES usuario(id_usuario),
  id_donante INT NOT NULL REFERENCES donante(id_donante)
);

CREATE INDEX idx_usuario_donante_donante ON usuario_donante (id_donante);

GRANT SELECT ON usuario_donante TO alimenta_app;

-- Misma firma que en la migración 009 (por eso conserva sus permisos),
-- con una regla nueva: un donante solo registra en sedes de su organización.
CREATE OR REPLACE PROCEDURE registrar_lote(
  p_id_usuario        INT,
  p_id_sede           INT,
  p_id_categoria      INT,
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

  INSERT INTO lote (id_sede, id_categoria, id_unidad, descripcion,
                    cantidad_inicial, saldo, fecha_vencimiento)
  VALUES (p_id_sede, p_id_categoria, p_id_unidad, p_descripcion,
          p_cantidad, p_cantidad, p_fecha_vencimiento)
  RETURNING id_lote INTO p_id_lote;

  INSERT INTO movimiento_inventario (id_lote, id_usuario, tipo, cantidad, motivo)
  VALUES (p_id_lote, p_id_usuario, 'entrada', p_cantidad, 'Recepción de donación');
END;
$$;

COMMIT;
