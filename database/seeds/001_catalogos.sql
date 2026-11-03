INSERT INTO rol (nombre) VALUES
  ('donante'), ('gestor'), ('beneficiario'), ('administrador')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO categoria (nombre) VALUES
  ('Panadería'), ('Frutas y verduras'), ('Lácteos'),
  ('Carnes y pescados'), ('Granos y cereales'),
  ('Comida preparada'), ('Enlatados y empacados'), ('Bebidas')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO unidad (nombre, abreviatura) VALUES
  ('Kilogramo', 'kg'), ('Gramo', 'g'), ('Litro', 'l'),
  ('Unidad', 'und'), ('Porción', 'porc')
ON CONFLICT (nombre) DO NOTHING;