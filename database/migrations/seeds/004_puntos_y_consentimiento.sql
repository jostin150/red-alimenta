INSERT INTO punto_entrega (nombre, direccion, comuna) VALUES
  ('Punto Aranjuez', 'Carrera 52 # 90-15',  'Aranjuez'),
  ('Punto Robledo',  'Calle 80 # 85-30',    'Robledo'),
  ('Punto Laureles', 'Carrera 70 # 44-12',  'Laureles-Estadio'),
  ('Punto Belén',    'Calle 30 # 76-20',    'Belén'),
  ('Punto Popular',  'Carrera 42 # 107-40', 'Popular')
ON CONFLICT (nombre) DO NOTHING;

UPDATE beneficiario
SET consentimiento = TRUE,
    fecha_consentimiento = now()
WHERE NOT consentimiento;

WITH p AS (
  SELECT id_punto, row_number() OVER (ORDER BY id_punto) - 1 AS rn
  FROM punto_entrega
), n AS (
  SELECT count(*) AS c FROM punto_entrega
)
UPDATE entrega e
SET id_punto = p.id_punto
FROM p, n
WHERE e.id_punto IS NULL
  AND p.rn = e.id_entrega % n.c;