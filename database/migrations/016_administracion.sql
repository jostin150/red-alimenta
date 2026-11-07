-- 016: administración (solo para el rol "administrador")
--      catálogos (categorías, tipos, unidades, puntos de entrega),
--      usuarios y roles.
--
-- Requiere haber ejecutado antes de la 001 a la 015.
-- Ejecutar UNA sola vez, en el Query Tool de la base "alimenta".
--
-- Idea de seguridad: la aplicación NO escribe directamente en estas tablas.
-- Todo pasa por procedimientos que primero comprueban que quien los llama
-- es un administrador activo (igual que hacen los demás procedimientos).
BEGIN;

-- ============================================================
-- 0. Comprobación común: "¿quien llama es administrador activo?"
-- ============================================================
CREATE OR REPLACE FUNCTION public.verificar_admin(p_id_usuario INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM usuario u
    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
    JOIN rol r ON r.id_rol = ur.id_rol
    WHERE u.id_usuario = p_id_usuario AND u.activo AND r.nombre = 'administrador'
  ) THEN
    RAISE EXCEPTION 'Solo un administrador puede hacer esta operación';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.verificar_admin(INT) FROM PUBLIC;

-- ============================================================
-- 1. CATEGORÍAS
-- p_id NULL = crear una nueva; p_id con valor = cambiarle el nombre.
-- ============================================================
CREATE OR REPLACE PROCEDURE public.admin_guardar_categoria(
  p_admin  INT,
  p_id     INT,
  p_nombre VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM verificar_admin(p_admin);
  p_nombre := btrim(p_nombre);
  IF p_nombre IS NULL OR p_nombre = '' THEN
    RAISE EXCEPTION 'El nombre de la categoría es obligatorio';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO categoria (nombre) VALUES (p_nombre);
  ELSE
    UPDATE categoria SET nombre = p_nombre WHERE id_categoria = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'La categoría % no existe', p_id;
    END IF;
  END IF;
END;
$$;

-- ============================================================
-- 2. TIPOS DE ALIMENTO
-- Al editar solo se cambia el nombre y si está activo. La categoría de un
-- tipo no se cambia (los lotes ya guardados dependen de ella).
-- ============================================================
CREATE OR REPLACE PROCEDURE public.admin_guardar_tipo(
  p_admin        INT,
  p_id           INT,
  p_id_categoria INT,
  p_nombre       VARCHAR,
  p_activo       BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM verificar_admin(p_admin);
  p_nombre := btrim(p_nombre);
  IF p_nombre IS NULL OR p_nombre = '' THEN
    RAISE EXCEPTION 'El nombre del tipo es obligatorio';
  END IF;

  IF p_id IS NULL THEN
    IF NOT EXISTS (SELECT 1 FROM categoria WHERE id_categoria = p_id_categoria) THEN
      RAISE EXCEPTION 'Elige una categoría válida para el tipo';
    END IF;
    INSERT INTO tipo_alimento (id_categoria, nombre, activo)
    VALUES (p_id_categoria, p_nombre, COALESCE(p_activo, TRUE));
  ELSE
    UPDATE tipo_alimento
    SET nombre = p_nombre, activo = COALESCE(p_activo, FALSE)
    WHERE id_tipo = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'El tipo % no existe', p_id;
    END IF;
  END IF;
END;
$$;

-- ============================================================
-- 3. UNIDADES
-- ============================================================
CREATE OR REPLACE PROCEDURE public.admin_guardar_unidad(
  p_admin       INT,
  p_id          INT,
  p_nombre      VARCHAR,
  p_abreviatura VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM verificar_admin(p_admin);
  p_nombre := btrim(p_nombre);
  p_abreviatura := btrim(p_abreviatura);
  IF p_nombre IS NULL OR p_nombre = '' OR p_abreviatura IS NULL OR p_abreviatura = '' THEN
    RAISE EXCEPTION 'La unidad necesita nombre y abreviatura';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO unidad (nombre, abreviatura) VALUES (p_nombre, p_abreviatura);
  ELSE
    UPDATE unidad SET nombre = p_nombre, abreviatura = p_abreviatura
    WHERE id_unidad = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'La unidad % no existe', p_id;
    END IF;
  END IF;
END;
$$;

-- ============================================================
-- 4. PUNTOS DE ENTREGA
-- ============================================================
CREATE OR REPLACE PROCEDURE public.admin_guardar_punto(
  p_admin     INT,
  p_id        INT,
  p_nombre    VARCHAR,
  p_direccion VARCHAR,
  p_comuna    VARCHAR,
  p_activo    BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM verificar_admin(p_admin);
  p_nombre := btrim(p_nombre);
  p_direccion := btrim(p_direccion);
  p_comuna := NULLIF(btrim(p_comuna), '');
  IF p_nombre IS NULL OR p_nombre = '' OR p_direccion IS NULL OR p_direccion = '' THEN
    RAISE EXCEPTION 'El punto de entrega necesita nombre y dirección';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO punto_entrega (nombre, direccion, comuna, activo)
    VALUES (p_nombre, p_direccion, p_comuna, COALESCE(p_activo, TRUE));
  ELSE
    UPDATE punto_entrega
    SET nombre = p_nombre, direccion = p_direccion, comuna = p_comuna,
        activo = COALESCE(p_activo, FALSE)
    WHERE id_punto = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'El punto de entrega % no existe', p_id;
    END IF;
  END IF;
END;
$$;

-- ============================================================
-- 5. USUARIOS
-- Roles que se pueden dar aquí: administrador, gestor y donante.
-- Los beneficiarios se registran con su documento y consentimiento, no aquí.
-- ============================================================
CREATE OR REPLACE PROCEDURE public.admin_crear_usuario(
  p_admin         INT,
  p_nombre        VARCHAR,
  p_correo        VARCHAR,
  p_password_hash TEXT,
  p_rol           VARCHAR,
  p_id_donante    INT DEFAULT NULL,
  INOUT p_id_usuario INT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id_rol SMALLINT;
BEGIN
  PERFORM verificar_admin(p_admin);
  p_nombre := btrim(p_nombre);
  p_correo := lower(btrim(p_correo));

  IF p_nombre IS NULL OR p_nombre = '' THEN
    RAISE EXCEPTION 'El nombre es obligatorio';
  END IF;
  IF p_correo IS NULL OR p_correo !~ '^[^@\s]+@[^@\s]+$' THEN
    RAISE EXCEPTION 'El correo no es válido';
  END IF;
  IF p_password_hash IS NULL OR p_password_hash = '' THEN
    RAISE EXCEPTION 'Falta la contraseña';
  END IF;
  IF p_rol NOT IN ('administrador', 'gestor', 'donante') THEN
    RAISE EXCEPTION 'Aquí solo se pueden crear administradores, gestores y donantes';
  END IF;
  IF p_rol = 'donante' AND NOT EXISTS (
       SELECT 1 FROM donante WHERE id_donante = p_id_donante AND activo) THEN
    RAISE EXCEPTION 'Un usuario donante debe pertenecer a una organización donante activa';
  END IF;

  INSERT INTO usuario (nombre, correo, password_hash)
  VALUES (p_nombre, p_correo, p_password_hash)
  RETURNING id_usuario INTO p_id_usuario;

  SELECT id_rol INTO v_id_rol FROM rol WHERE nombre = p_rol;
  INSERT INTO usuario_rol (id_usuario, id_rol) VALUES (p_id_usuario, v_id_rol);

  IF p_rol = 'donante' THEN
    INSERT INTO usuario_donante (id_usuario, id_donante)
    VALUES (p_id_usuario, p_id_donante);
  END IF;
END;
$$;

-- Activar o desactivar un usuario (no se borra: se conserva el historial).
CREATE OR REPLACE PROCEDURE public.admin_estado_usuario(
  p_admin      INT,
  p_id_usuario INT,
  p_activo     BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM verificar_admin(p_admin);

  IF NOT p_activo THEN
    IF p_id_usuario = p_admin THEN
      RAISE EXCEPTION 'No puedes desactivar tu propio usuario';
    END IF;
    -- Siempre debe quedar al menos un administrador activo
    IF EXISTS (
         SELECT 1 FROM usuario_rol ur JOIN rol r ON r.id_rol = ur.id_rol
         WHERE ur.id_usuario = p_id_usuario AND r.nombre = 'administrador')
       AND NOT EXISTS (
         SELECT 1 FROM usuario u
         JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
         JOIN rol r ON r.id_rol = ur.id_rol
         WHERE r.nombre = 'administrador' AND u.activo AND u.id_usuario <> p_id_usuario) THEN
      RAISE EXCEPTION 'Debe quedar al menos un administrador activo';
    END IF;
  END IF;

  UPDATE usuario SET activo = p_activo WHERE id_usuario = p_id_usuario;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario % no existe', p_id_usuario;
  END IF;
END;
$$;

-- Agregar un rol a un usuario.
CREATE OR REPLACE PROCEDURE public.admin_asignar_rol(
  p_admin      INT,
  p_id_usuario INT,
  p_rol        VARCHAR,
  p_id_donante INT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id_rol SMALLINT;
BEGIN
  PERFORM verificar_admin(p_admin);

  IF p_rol NOT IN ('administrador', 'gestor', 'donante') THEN
    RAISE EXCEPTION 'Aquí solo se pueden asignar los roles administrador, gestor y donante';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario) THEN
    RAISE EXCEPTION 'El usuario % no existe', p_id_usuario;
  END IF;
  IF p_rol = 'donante' AND NOT EXISTS (
       SELECT 1 FROM donante WHERE id_donante = p_id_donante AND activo) THEN
    RAISE EXCEPTION 'Para el rol donante elige una organización donante activa';
  END IF;

  SELECT id_rol INTO v_id_rol FROM rol WHERE nombre = p_rol;
  IF EXISTS (SELECT 1 FROM usuario_rol WHERE id_usuario = p_id_usuario AND id_rol = v_id_rol) THEN
    RAISE EXCEPTION 'El usuario ya tiene el rol %', p_rol;
  END IF;

  INSERT INTO usuario_rol (id_usuario, id_rol) VALUES (p_id_usuario, v_id_rol);

  IF p_rol = 'donante' THEN
    INSERT INTO usuario_donante (id_usuario, id_donante)
    VALUES (p_id_usuario, p_id_donante)
    ON CONFLICT (id_usuario) DO UPDATE SET id_donante = EXCLUDED.id_donante;
  END IF;
END;
$$;

-- Quitar un rol a un usuario.
CREATE OR REPLACE PROCEDURE public.admin_quitar_rol(
  p_admin      INT,
  p_id_usuario INT,
  p_rol        VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id_rol SMALLINT;
BEGIN
  PERFORM verificar_admin(p_admin);

  IF p_rol NOT IN ('administrador', 'gestor', 'donante') THEN
    RAISE EXCEPTION 'Aquí solo se pueden quitar los roles administrador, gestor y donante';
  END IF;

  IF p_rol = 'administrador' THEN
    IF p_id_usuario = p_admin THEN
      RAISE EXCEPTION 'No puedes quitarte a ti mismo el rol de administrador';
    END IF;
    IF NOT EXISTS (
         SELECT 1 FROM usuario u
         JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
         JOIN rol r ON r.id_rol = ur.id_rol
         WHERE r.nombre = 'administrador' AND u.activo AND u.id_usuario <> p_id_usuario) THEN
      RAISE EXCEPTION 'Debe quedar al menos un administrador activo';
    END IF;
  END IF;

  SELECT id_rol INTO v_id_rol FROM rol WHERE nombre = p_rol;
  DELETE FROM usuario_rol WHERE id_usuario = p_id_usuario AND id_rol = v_id_rol;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario no tiene el rol %', p_rol;
  END IF;

  IF p_rol = 'donante' THEN
    DELETE FROM usuario_donante WHERE id_usuario = p_id_usuario;
  END IF;
END;
$$;

-- ============================================================
-- 6. PERMISOS: la app solo puede LLAMAR a estos procedimientos
-- ============================================================
REVOKE ALL ON PROCEDURE public.admin_guardar_categoria(INT, INT, VARCHAR) FROM PUBLIC;
REVOKE ALL ON PROCEDURE public.admin_guardar_tipo(INT, INT, INT, VARCHAR, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON PROCEDURE public.admin_guardar_unidad(INT, INT, VARCHAR, VARCHAR) FROM PUBLIC;
REVOKE ALL ON PROCEDURE public.admin_guardar_punto(INT, INT, VARCHAR, VARCHAR, VARCHAR, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON PROCEDURE public.admin_crear_usuario(INT, VARCHAR, VARCHAR, TEXT, VARCHAR, INT, INT) FROM PUBLIC;
REVOKE ALL ON PROCEDURE public.admin_estado_usuario(INT, INT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON PROCEDURE public.admin_asignar_rol(INT, INT, VARCHAR, INT) FROM PUBLIC;
REVOKE ALL ON PROCEDURE public.admin_quitar_rol(INT, INT, VARCHAR) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.admin_guardar_categoria(INT, INT, VARCHAR) TO alimenta_app;
GRANT EXECUTE ON PROCEDURE public.admin_guardar_tipo(INT, INT, INT, VARCHAR, BOOLEAN) TO alimenta_app;
GRANT EXECUTE ON PROCEDURE public.admin_guardar_unidad(INT, INT, VARCHAR, VARCHAR) TO alimenta_app;
GRANT EXECUTE ON PROCEDURE public.admin_guardar_punto(INT, INT, VARCHAR, VARCHAR, VARCHAR, BOOLEAN) TO alimenta_app;
GRANT EXECUTE ON PROCEDURE public.admin_crear_usuario(INT, VARCHAR, VARCHAR, TEXT, VARCHAR, INT, INT) TO alimenta_app;
GRANT EXECUTE ON PROCEDURE public.admin_estado_usuario(INT, INT, BOOLEAN) TO alimenta_app;
GRANT EXECUTE ON PROCEDURE public.admin_asignar_rol(INT, INT, VARCHAR, INT) TO alimenta_app;
GRANT EXECUTE ON PROCEDURE public.admin_quitar_rol(INT, INT, VARCHAR) TO alimenta_app;

-- ============================================================
-- 7. AUDITORÍA: quedan registrados los cambios de catálogos
--    (la tabla usuario NO se audita aquí porque guarda contraseñas)
-- ============================================================
DROP TRIGGER IF EXISTS trg_auditoria_categoria ON categoria;
CREATE TRIGGER trg_auditoria_categoria
AFTER INSERT OR UPDATE ON categoria
FOR EACH ROW EXECUTE FUNCTION auditar_cambio('id_categoria');

DROP TRIGGER IF EXISTS trg_auditoria_tipo_alimento ON tipo_alimento;
CREATE TRIGGER trg_auditoria_tipo_alimento
AFTER INSERT OR UPDATE ON tipo_alimento
FOR EACH ROW EXECUTE FUNCTION auditar_cambio('id_tipo');

DROP TRIGGER IF EXISTS trg_auditoria_unidad ON unidad;
CREATE TRIGGER trg_auditoria_unidad
AFTER INSERT OR UPDATE ON unidad
FOR EACH ROW EXECUTE FUNCTION auditar_cambio('id_unidad');

DROP TRIGGER IF EXISTS trg_auditoria_punto_entrega ON punto_entrega;
CREATE TRIGGER trg_auditoria_punto_entrega
AFTER INSERT OR UPDATE ON punto_entrega
FOR EACH ROW EXECUTE FUNCTION auditar_cambio('id_punto');

COMMIT;
