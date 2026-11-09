
BEGIN;

CREATE OR REPLACE PROCEDURE public.crear_solicitud(
	IN p_id_usuario integer,
	IN p_id_categoria integer,
	IN p_id_unidad integer,
	IN p_cantidad numeric,
	INOUT p_id_solicitud integer)
LANGUAGE 'plpgsql'
    SECURITY DEFINER 
    SET search_path=public, pg_temp
AS $BODY$
DECLARE
  v_id_beneficiario INT;
  v_estado          VARCHAR(15);
  v_consentimiento  BOOLEAN;
BEGIN
  SELECT b.id_beneficiario, b.estado, b.consentimiento
    INTO v_id_beneficiario, v_estado, v_consentimiento
  FROM beneficiario b
  JOIN usuario u ON u.id_usuario = b.id_usuario
  WHERE b.id_usuario = p_id_usuario AND u.activo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario % no es un beneficiario activo', p_id_usuario;
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'Tu perfil de beneficiario no está activo';
  END IF;
  IF NOT v_consentimiento THEN
    RAISE EXCEPTION 'Debes aceptar el tratamiento de tus datos antes de solicitar';
  END IF;
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'La cantidad debe ser mayor que cero';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM categoria WHERE id_categoria = p_id_categoria) THEN
    RAISE EXCEPTION 'La categoría % no existe', p_id_categoria;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM unidad WHERE id_unidad = p_id_unidad) THEN
    RAISE EXCEPTION 'La unidad % no existe', p_id_unidad;
  END IF;

  INSERT INTO solicitud (id_beneficiario)
  VALUES (v_id_beneficiario)
  RETURNING id_solicitud INTO p_id_solicitud;

  INSERT INTO solicitud_detalle (id_solicitud, id_categoria, id_unidad, cantidad_solicitada)
  VALUES (p_id_solicitud, p_id_categoria, p_id_unidad, p_cantidad);
END;
$BODY$;


GRANT EXECUTE ON PROCEDURE public.crear_solicitud(integer, integer, integer, numeric, integer) TO alimenta_app;


REVOKE ALL ON PROCEDURE public.crear_solicitud(integer, integer, integer, numeric, integer) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE crear_solicitud(INT, INT, INT, NUMERIC, INT) TO alimenta_app;

COMMIT;