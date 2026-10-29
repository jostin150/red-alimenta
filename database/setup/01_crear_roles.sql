-- Ejecutar UNA vez, conectado como postgres. No contiene contraseñas.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alimenta_app') THEN
    CREATE ROLE alimenta_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alimenta_lectura') THEN
    CREATE ROLE alimenta_lectura LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;
END $$;