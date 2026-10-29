BEGIN;

-- ============================================================
-- 1. Dos objetos nuevos que la aplicación necesita
-- ============================================================

-- Registrar un lote SIEMPRE crea también su movimiento de entrada.
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

  INSERT INTO lote (id_sede, id_categoria, id_unidad, descripcion,
                    cantidad_inicial, saldo, fecha_vencimiento)
  VALUES (p_id_sede, p_id_categoria, p_id_unidad, p_descripcion,
          p_cantidad, p_cantidad, p_fecha_vencimiento)
  RETURNING id_lote INTO p_id_lote;

  INSERT INTO movimiento_inventario (id_lote, id_usuario, tipo, cantidad, motivo)
  VALUES (p_id_lote, p_id_usuario, 'entrada', p_cantidad, 'Recepción de donación');
END;
$$;

-- La auditoría solo la puede consultar un administrador.
CREATE OR REPLACE FUNCTION ver_auditoria(p_id_usuario INT, p_limite INT DEFAULT 100)
RETURNS TABLE (
  id_auditoria     BIGINT,
  tabla            VARCHAR,
  operacion        VARCHAR,
  id_registro      VARCHAR,
  datos_anteriores JSONB,
  datos_nuevos     JSONB,
  id_usuario       INT,
  fecha            TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM usuario u
    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
    JOIN rol r ON r.id_rol = ur.id_rol
    WHERE u.id_usuario = p_id_usuario
      AND u.activo
      AND r.nombre = 'administrador'
  ) THEN
    RAISE EXCEPTION 'El usuario % no tiene permiso para consultar la auditoría', p_id_usuario;
  END IF;

  RETURN QUERY
  SELECT a.id_auditoria, a.tabla, a.operacion, a.id_registro,
         a.datos_anteriores, a.datos_nuevos, a.id_usuario, a.fecha
  FROM auditoria a
  ORDER BY a.id_auditoria DESC
  LIMIT p_limite;
END;
$$;

-- ============================================================
-- 2. Los procedimientos y el trigger de auditoría se ejecutan
--    con los permisos de su dueño (SECURITY DEFINER)
-- ============================================================
ALTER PROCEDURE reservar_inventario(INT, INT, INT)
  SECURITY DEFINER SET search_path = public, pg_temp;

ALTER PROCEDURE confirmar_entrega(INT, INT, VARCHAR, INT)
  SECURITY DEFINER SET search_path = public, pg_temp;

ALTER PROCEDURE cancelar_reserva(INT, INT, VARCHAR)
  SECURITY DEFINER SET search_path = public, pg_temp;

ALTER FUNCTION auditar_cambio()
  SECURITY DEFINER SET search_path = public, pg_temp;

ALTER FUNCTION tasa_aprovechamiento(DATE, DATE, VARCHAR)
  SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================
-- 3. Cerrar todo por defecto
-- ============================================================
REVOKE ALL ON ALL TABLES   IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

GRANT CONNECT ON DATABASE alimenta TO alimenta_app, alimenta_lectura;
GRANT USAGE ON SCHEMA public TO alimenta_app, alimenta_lectura;

-- ============================================================
-- 4. Rol de la APLICACIÓN
-- ============================================================
-- Puede leer las tablas del negocio (la auditoría NO)
GRANT SELECT ON rol, usuario, usuario_rol, donante, sede, categoria, unidad,
                beneficiario, lote, solicitud, solicitud_detalle, reserva,
                reserva_detalle, entrega, movimiento_inventario
TO alimenta_app;

-- Puede administrar catálogos y personas
GRANT INSERT, UPDATE ON usuario, usuario_rol, donante, sede, categoria, unidad,
                        beneficiario
TO alimenta_app;
GRANT DELETE ON usuario_rol TO alimenta_app;

-- Puede crear solicitudes
GRANT INSERT ON solicitud, solicitud_detalle TO alimenta_app;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO alimenta_app;

-- Puede leer todas las vistas
GRANT SELECT ON v_inventario_disponible, v_alertas_vencimiento,
                v_historial_movimientos, v_indicador_mensual,
                v_reporte_inventario_sede_categoria, v_reporte_balance_mensual,
                v_reporte_aprovechamiento, v_reporte_beneficiarios_comuna,
                v_reporte_donantes
TO alimenta_app;

-- Y llamar a los procedimientos y funciones
GRANT EXECUTE ON PROCEDURE reservar_inventario(INT, INT, INT)           TO alimenta_app;
GRANT EXECUTE ON PROCEDURE confirmar_entrega(INT, INT, VARCHAR, INT)    TO alimenta_app;
GRANT EXECUTE ON PROCEDURE cancelar_reserva(INT, INT, VARCHAR)          TO alimenta_app;
GRANT EXECUTE ON PROCEDURE registrar_lote(INT, INT, INT, INT, VARCHAR, NUMERIC, DATE, INT)
                                                                        TO alimenta_app;
GRANT EXECUTE ON FUNCTION ver_auditoria(INT, INT)                       TO alimenta_app;
GRANT EXECUTE ON FUNCTION saldo_lote_a_fecha(INT, DATE)                 TO alimenta_app;
GRANT EXECUTE ON FUNCTION tasa_aprovechamiento(DATE, DATE, VARCHAR)     TO alimenta_app;
GRANT EXECUTE ON FUNCTION trazabilidad_lote(INT)                        TO alimenta_app;

-- ============================================================
-- 5. Rol de LECTURA (solo reportes agregados, sin datos personales)
-- ============================================================
GRANT SELECT ON v_inventario_disponible, v_alertas_vencimiento,
                v_indicador_mensual, v_reporte_inventario_sede_categoria,
                v_reporte_balance_mensual, v_reporte_aprovechamiento,
                v_reporte_beneficiarios_comuna, v_reporte_donantes
TO alimenta_lectura;

GRANT EXECUTE ON FUNCTION tasa_aprovechamiento(DATE, DATE, VARCHAR) TO alimenta_lectura;

COMMIT;