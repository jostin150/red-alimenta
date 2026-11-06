BEGIN;


UPDATE categoria SET nombre = 'Carnes' WHERE lower(nombre) LIKE 'carnes y pescado%';
INSERT INTO categoria (nombre) VALUES ('Pescados')
ON CONFLICT (nombre) DO NOTHING;

-- ============================================================
-- 2. TABLA DE TIPOS
-- ============================================================
CREATE TABLE tipo_alimento (
  id_tipo      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_categoria SMALLINT NOT NULL REFERENCES categoria(id_categoria),
  nombre       VARCHAR(80) NOT NULL,
  activo       BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (id_categoria, nombre),
  -- Este UNIQUE extra permite la llave compuesta del paso 3:
  -- así la base garantiza que un tipo pertenece a SU categoría.
  UNIQUE (id_tipo, id_categoria)
);

CREATE INDEX idx_tipo_categoria ON tipo_alimento (id_categoria);

-- Tipos iniciales.
INSERT INTO tipo_alimento (id_categoria, nombre)
SELECT c.id_categoria, t.nombre
FROM (VALUES
  ('Panadería',             'Pan tajado'),
  ('Panadería',             'Pan francés'),
  ('Panadería',             'Pasteles y tortas'),
  ('Panadería',             'Arepas'),
  ('Frutas y verduras',     'Frutas'),
  ('Frutas y verduras',     'Verduras'),
  ('Frutas y verduras',     'Tubérculos'),
  ('Lácteos',               'Leche'),
  ('Lácteos',               'Queso'),
  ('Lácteos',               'Yogur'),
  ('Lácteos',               'Mantequilla'),
  ('Carnes',                'Res'),
  ('Carnes',                'Pollo'),
  ('Carnes',                'Cerdo'),
  ('Pescados',              'Pescado fresco'),
  ('Pescados',              'Atún y sardinas'),
  ('Granos y cereales',     'Arroz'),
  ('Granos y cereales',     'Lentejas y fríjoles'),
  ('Granos y cereales',     'Pasta'),
  ('Granos y cereales',     'Avena y cereal'),
  ('Comida preparada',      'Almuerzo'),
  ('Comida preparada',      'Sopa'),
  ('Comida preparada',      'Sándwich'),
  ('Enlatados y empacados', 'Enlatados'),
  ('Enlatados y empacados', 'Galletas y snacks'),
  ('Enlatados y empacados', 'Aceite y condimentos'),
  ('Bebidas',               'Agua'),
  ('Bebidas',               'Gaseosa'),
  ('Bebidas',               'Jugo'),
  ('Bebidas',               'Bebida láctea')
) AS t(categoria, nombre)
JOIN categoria c ON c.nombre = t.categoria
ON CONFLICT (id_categoria, nombre) DO NOTHING;

-- "Otro" para TODAS las categorías que existan en tu base, sin importar su nombre.
-- Así ningún lote ni solicitud vieja se queda sin tipo.
INSERT INTO tipo_alimento (id_categoria, nombre)
SELECT id_categoria, 'Otro' FROM categoria
ON CONFLICT (id_categoria, nombre) DO NOTHING;

-- ============================================================
-- 3. EL LOTE Y EL DETALLE DE LA SOLICITUD GUARDAN EL TIPO
-- Primero la columna queda opcional, llenamos los datos viejos con "Otro",
-- y al final la volvemos obligatoria.
-- ============================================================
ALTER TABLE lote               ADD COLUMN id_tipo INT;
ALTER TABLE solicitud_detalle  ADD COLUMN id_tipo INT;

UPDATE lote l
SET id_tipo = t.id_tipo
FROM tipo_alimento t
WHERE t.id_categoria = l.id_categoria AND t.nombre = 'Otro';

UPDATE solicitud_detalle sd
SET id_tipo = t.id_tipo
FROM tipo_alimento t
WHERE t.id_categoria = sd.id_categoria AND t.nombre = 'Otro';

ALTER TABLE lote               ALTER COLUMN id_tipo SET NOT NULL;
ALTER TABLE solicitud_detalle  ALTER COLUMN id_tipo SET NOT NULL;

-- Llave compuesta: (tipo, categoría) debe existir junta en tipo_alimento.
-- Si alguien intenta guardar "Agua" dentro de "Lácteos", la base lo rechaza.
ALTER TABLE lote
  ADD CONSTRAINT fk_lote_tipo
  FOREIGN KEY (id_tipo, id_categoria)
  REFERENCES tipo_alimento (id_tipo, id_categoria);

ALTER TABLE solicitud_detalle
  ADD CONSTRAINT fk_detalle_tipo
  FOREIGN KEY (id_tipo, id_categoria)
  REFERENCES tipo_alimento (id_tipo, id_categoria);

-- Antes no se podía repetir la categoría en una solicitud; ahora no se
-- puede repetir el tipo (se puede pedir Agua y Gaseosa, ambas Bebidas).
ALTER TABLE solicitud_detalle
  DROP CONSTRAINT IF EXISTS solicitud_detalle_id_solicitud_id_categoria_key;
ALTER TABLE solicitud_detalle
  ADD CONSTRAINT uq_detalle_solicitud_tipo UNIQUE (id_solicitud, id_tipo);

-- Para que FEFO busque rápido por tipo.
CREATE INDEX idx_lote_tipo_vence ON lote (id_tipo, fecha_vencimiento);

-- ============================================================
-- 4. PUNTO DE ENTREGA ELEGIDO POR EL BENEFICIARIO
-- Queda opcional en la tabla (las solicitudes viejas no lo tienen);
-- el procedimiento crear_solicitud lo exigirá en las nuevas (paso siguiente).
-- ============================================================
ALTER TABLE solicitud ADD COLUMN id_punto INT REFERENCES punto_entrega(id_punto);
CREATE INDEX idx_solicitud_punto ON solicitud (id_punto);

-- ============================================================
-- 5. PERMISOS
-- ============================================================
GRANT SELECT ON tipo_alimento TO alimenta_app;
GRANT SELECT ON tipo_alimento TO alimenta_lectura;

COMMIT;

-- Comprobación rápida (ejecútala aparte, después del COMMIT):
--   SELECT c.nombre AS categoria, t.nombre AS tipo
--   FROM tipo_alimento t JOIN categoria c USING (id_categoria)
--   ORDER BY c.nombre, t.nombre;
