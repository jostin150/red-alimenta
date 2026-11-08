-- PREPARACIÓN: lote de 10 kg y dos solicitudes de 8 kg cada una
BEGIN;

INSERT INTO categoria (nombre) VALUES ('Prueba concurrencia');

INSERT INTO tipo_alimento (id_categoria, nombre)
SELECT id_categoria, 'Tipo concurrencia' FROM categoria WHERE nombre = 'Prueba concurrencia';

INSERT INTO donante (nombre, nit, tipo)
VALUES ('Donante Concurrencia', '999999999-9', 'otro');

INSERT INTO sede (id_donante, nombre, direccion)
SELECT id_donante, 'Sede Concurrencia', 'Calle 0'
FROM donante WHERE nit = '999999999-9';

INSERT INTO lote (id_sede, id_categoria, id_tipo, id_unidad, descripcion,
                  cantidad_inicial, saldo, fecha_vencimiento)
SELECT s.id_sede, c.id_categoria, t.id_tipo, u.id_unidad, 'Lote concurrencia',
       10, 10, CURRENT_DATE + 5
FROM sede s, categoria c, tipo_alimento t, unidad u
WHERE s.nombre = 'Sede Concurrencia'
  AND c.nombre = 'Prueba concurrencia'
  AND t.id_categoria = c.id_categoria AND t.nombre = 'Tipo concurrencia'
  AND u.abreviatura = 'kg';

INSERT INTO movimiento_inventario (id_lote, tipo, cantidad, motivo)
SELECT id_lote, 'entrada', 10, 'Recepción de prueba'
FROM lote WHERE descripcion = 'Lote concurrencia';

INSERT INTO solicitud (id_beneficiario, id_punto)
SELECT id_beneficiario, (SELECT MIN(id_punto) FROM punto_entrega)
FROM beneficiario ORDER BY id_beneficiario LIMIT 2;

INSERT INTO solicitud_detalle (id_solicitud, id_categoria, id_tipo, id_unidad, cantidad_solicitada)
SELECT s.id_solicitud, c.id_categoria, t.id_tipo, u.id_unidad, 8
FROM (SELECT id_solicitud FROM solicitud ORDER BY id_solicitud DESC LIMIT 2) s,
     categoria c, tipo_alimento t, unidad u
WHERE c.nombre = 'Prueba concurrencia'
  AND t.id_categoria = c.id_categoria AND t.nombre = 'Tipo concurrencia'
  AND u.abreviatura = 'kg';

COMMIT;

SELECT id_solicitud FROM solicitud ORDER BY id_solicitud DESC LIMIT 2;

-- SESIÓN A:
--   BEGIN;
--   CALL reservar_inventario(ID_A, 2, NULL);
--   (no confirmar todavía)
-- SESIÓN B:
--   CALL reservar_inventario(ID_B, 2, NULL);
--   Resultado esperado: se queda esperando.
-- SESIÓN A:
--   COMMIT;
-- SESIÓN B:
--   Resultado esperado: ERROR "Inventario insuficiente ... faltan 6.00"
-- VERIFICACIÓN:
--   saldo del lote = 2, una reserva de 8 kg, una solicitud reservada y otra pendiente.