-- T1. Demostración de ROLLBACK: un cambio que se deshace.
-- Paso 1: elige un lote y anota su saldo.
SELECT id_lote, saldo
FROM lote
WHERE estado = 'activo' AND saldo > 5
ORDER BY id_lote
LIMIT 1;

-- Paso 2 (reemplaza ID por el id_lote anterior; ejecuta de a una línea):
-- BEGIN;
-- UPDATE lote SET saldo = saldo - 5 WHERE id_lote = ID;
-- SELECT id_lote, saldo FROM lote WHERE id_lote = ID;   -- aquí ya bajó 5
-- ROLLBACK;
-- SELECT id_lote, saldo FROM lote WHERE id_lote = ID;   -- volvió al original

-- T2. Control de errores: la base rechaza el cambio y avisa.
DO $$
BEGIN
  UPDATE lote
  SET saldo = -1
  WHERE id_lote = (SELECT MIN(id_lote) FROM lote);
EXCEPTION
  WHEN check_violation THEN
    RAISE NOTICE 'La base rechazó el cambio: el saldo no puede ser negativo';
END $$;