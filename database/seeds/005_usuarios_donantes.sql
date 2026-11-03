-- Dos usuarios donantes de demostración, cada uno vinculado a su donante.
--   donante2@alimenta.test -> "Donante 2"
--   donante3@alimenta.test -> "Donante 3"
-- Se puede ejecutar más de una vez sin duplicar nada.
BEGIN;

INSERT INTO usuario (nombre, correo, password_hash) VALUES
  ('Usuario Donante 2', 'donante2@alimenta.test', 'hash_de_prueba'),
  ('Usuario Donante 3', 'donante3@alimenta.test', 'hash_de_prueba')
ON CONFLICT (correo) DO NOTHING;

INSERT INTO usuario_rol (id_usuario, id_rol)
SELECT u.id_usuario, r.id_rol
FROM usuario u
JOIN rol r ON r.nombre = 'donante'
WHERE u.correo IN ('donante2@alimenta.test', 'donante3@alimenta.test')
ON CONFLICT DO NOTHING;

INSERT INTO usuario_donante (id_usuario, id_donante)
SELECT u.id_usuario, d.id_donante
FROM usuario u
JOIN donante d ON d.nit = CASE u.correo
    WHEN 'donante2@alimenta.test' THEN '900000002-1'
    WHEN 'donante3@alimenta.test' THEN '900000003-1'
  END
WHERE u.correo IN ('donante2@alimenta.test', 'donante3@alimenta.test')
ON CONFLICT DO NOTHING;

COMMIT;
