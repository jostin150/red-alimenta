BEGIN;


SELECT setseed(0.42);

-- 1. USUARIOS: 1 administrador, 2 gestores y 60 beneficiarios
INSERT INTO usuario (nombre, correo, password_hash) VALUES
  ('Administrador Prueba', 'admin@alimenta.test',   'hash_de_prueba'),
  ('Gestor Uno',           'gestor1@alimenta.test', 'hash_de_prueba'),
  ('Gestor Dos',           'gestor2@alimenta.test', 'hash_de_prueba');

INSERT INTO usuario (nombre, correo, password_hash)
SELECT 'Beneficiario ' || n,
       'beneficiario' || n || '@alimenta.test',
       'hash_de_prueba'
FROM generate_series(1, 60) n;

-- 2. ROLES de cada usuario
INSERT INTO usuario_rol (id_usuario, id_rol)
SELECT u.id_usuario, r.id_rol
FROM usuario u
JOIN rol r ON r.nombre = CASE
    WHEN u.correo LIKE 'admin@%'        THEN 'administrador'
    WHEN u.correo LIKE 'gestor%'        THEN 'gestor'
    WHEN u.correo LIKE 'beneficiario%'  THEN 'beneficiario'
  END
WHERE u.correo LIKE '%@alimenta.test';

-- 3. BENEFICIARIOS (los 60 usuarios con rol beneficiario)
INSERT INTO beneficiario (id_usuario, documento, programa)
SELECT u.id_usuario,
       '10' || lpad(substring(u.correo from 'beneficiario(\d+)@'), 8, '0'),
       'Programa ' || ((u.id_usuario % 4) + 1)
FROM usuario u
WHERE u.correo LIKE 'beneficiario%@alimenta.test';

-- 4. DONANTES: 12
INSERT INTO donante (nombre, nit, tipo)
SELECT 'Donante ' || n,
       '900' || lpad(n::text, 6, '0') || '-1',
       (ARRAY['tienda','panaderia','restaurante','otro'])[1 + (n % 4)]
FROM generate_series(1, 12) n;

-- 5. SEDES: 20, repartidas entre los donantes
INSERT INTO sede (id_donante, nombre, direccion, barrio)
SELECT d.id_donante,
       'Sede ' || n,
       'Calle ' || n || ' # ' || n || '-10',
       (ARRAY['Laureles','El Poblado','Belén','Robledo','Candelaria'])[1 + (n % 5)]
FROM generate_series(1, 20) n
JOIN donante d
  ON d.nit = '900' || lpad((1 + (n % 12))::text, 6, '0') || '-1';

-- 6. LOTES: 250, recibidos en los últimos 6 meses
INSERT INTO lote (id_sede, id_categoria, id_unidad, descripcion,
                  cantidad_inicial, saldo, fecha_recepcion, fecha_vencimiento)
SELECT s.id_sede, c.id_categoria, un.id_unidad,
       'Lote de prueba ' || g.n,
       g.cant, g.cant, g.rec, g.rec + g.dias
FROM (
  SELECT n,
         round((5 + random() * 95)::numeric, 2) AS cant,
         CURRENT_DATE - (random() * 180)::int   AS rec,
         (2 + random() * 20)::int               AS dias,
         1 + (random() * 19)::int               AS sede_n,
         1 + (random() * 7)::int                AS cat_n,
         1 + (random() * 3)::int                AS uni_n
  FROM generate_series(1, 250) n
) g
JOIN (SELECT id_sede,
             row_number() OVER (ORDER BY id_sede) AS rn
      FROM sede) s ON s.rn = g.sede_n
JOIN (SELECT id_categoria,
             row_number() OVER (ORDER BY id_categoria) AS rn
      FROM categoria) c ON c.rn = g.cat_n
JOIN (SELECT id_unidad,
             row_number() OVER (ORDER BY id_unidad) AS rn
      FROM unidad
      WHERE abreviatura IN ('kg','l','und','porc')) un ON un.rn = g.uni_n;

-- 7. MOVIMIENTO de ENTRADA por cada lote (cuando llegó)
INSERT INTO movimiento_inventario (id_lote, id_usuario, tipo, cantidad, motivo, fecha)
SELECT l.id_lote,
       (SELECT id_usuario FROM usuario WHERE correo = 'gestor1@alimenta.test'),
       'entrada',
       l.cantidad_inicial,
       'Recepción de donación',
       l.fecha_recepcion + time '09:00'
FROM lote l;

-- 8. SOLICITUDES, RESERVAS, ENTREGAS y sus MOVIMIENTOS
DO $$
DECLARE
  v_gestor        INT;
  v_benef         INT;
  v_fecha         TIMESTAMPTZ;
  v_lote          RECORD;
  v_primer_lote   INT;
  v_cat           SMALLINT;
  v_uni           SMALLINT;
  v_cant          NUMERIC(10,2);
  v_total         NUMERIC(10,2);
  v_n_res         INT;
  v_r             NUMERIC;
  v_estado_sol    VARCHAR(15);
  v_estado_res    VARCHAR(15);
  v_id_solicitud  INT;
  v_id_reserva    INT;
BEGIN
  SELECT id_usuario INTO v_gestor
  FROM usuario WHERE correo = 'gestor1@alimenta.test';

  FOR i IN 1..180 LOOP
    v_fecha := now() - make_interval(days  => (random() * 170)::int,
                                     hours => (random() * 10)::int);

    SELECT id_beneficiario INTO v_benef
    FROM beneficiario ORDER BY random() LIMIT 1;

    -- Busca un lote que existiera y no estuviera vencido ese día
    SELECT id_lote, id_categoria, id_unidad, saldo INTO v_lote
    FROM lote
    WHERE fecha_recepcion <= v_fecha::date
      AND fecha_vencimiento >= v_fecha::date
      AND saldo >= 1
    ORDER BY random() LIMIT 1;

    -- Si no había nada disponible, la solicitud se rechaza
    IF NOT FOUND THEN
      INSERT INTO solicitud (id_beneficiario, fecha_solicitud, estado, observacion)
      VALUES (v_benef, v_fecha, 'rechazada', 'Sin inventario disponible');
      CONTINUE;
    END IF;

    v_primer_lote := v_lote.id_lote;
    v_cat   := v_lote.id_categoria;
    v_uni   := v_lote.id_unidad;
    v_total := 0;
    v_n_res := CASE WHEN random() < 0.4 THEN 2 ELSE 1 END;

    -- Decide cómo terminó la solicitud
    v_r := random();
    IF v_fecha > now() - interval '3 days' AND v_r < 0.5 THEN
      v_estado_sol := 'reservada';  v_estado_res := 'activa';
    ELSIF v_r < 0.85 THEN
      v_estado_sol := 'entregada';  v_estado_res := 'entregada';
    ELSE
      v_estado_sol := 'cancelada';  v_estado_res := 'cancelada';
    END IF;

    INSERT INTO solicitud (id_beneficiario, fecha_solicitud, estado)
    VALUES (v_benef, v_fecha, v_estado_sol)
    RETURNING id_solicitud INTO v_id_solicitud;

    -- Una solicitud puede cubrirse con 1 o 2 lotes
    FOR j IN 1..v_n_res LOOP
      IF j = 2 THEN
        SELECT id_lote, id_categoria, id_unidad, saldo INTO v_lote
        FROM lote
        WHERE id_categoria = v_cat
          AND id_unidad = v_uni
          AND id_lote <> v_primer_lote
          AND fecha_recepcion <= v_fecha::date
          AND fecha_vencimiento >= v_fecha::date
          AND saldo >= 1
        ORDER BY random() LIMIT 1;
        EXIT WHEN NOT FOUND;
      END IF;

      v_cant  := LEAST(v_lote.saldo, round((1 + random() * 9)::numeric, 2));
      v_total := v_total + v_cant;

      INSERT INTO reserva (id_solicitud, fecha_reserva, estado)
      VALUES (v_id_solicitud, LEAST(v_fecha + interval '5 minutes', now()), v_estado_res)
      RETURNING id_reserva INTO v_id_reserva;

      INSERT INTO reserva_detalle (id_reserva, id_lote, cantidad)
      VALUES (v_id_reserva, v_lote.id_lote, v_cant);

      INSERT INTO movimiento_inventario
        (id_lote, id_reserva, id_usuario, tipo, cantidad, motivo, fecha)
      VALUES (v_lote.id_lote, v_id_reserva, v_gestor, 'reserva', v_cant,
              'Reserva de inventario',
              LEAST(v_fecha + interval '5 minutes', now()));

      IF v_estado_res = 'entregada' THEN
        INSERT INTO entrega (id_reserva, id_usuario_gestor, fecha_entrega)
        VALUES (v_id_reserva, v_gestor, LEAST(v_fecha + interval '1 day', now()));

        INSERT INTO movimiento_inventario
          (id_lote, id_reserva, id_usuario, tipo, cantidad, motivo, fecha)
        VALUES (v_lote.id_lote, v_id_reserva, v_gestor, 'salida', v_cant,
                'Entrega al beneficiario',
                LEAST(v_fecha + interval '1 day', now()));

        UPDATE lote SET saldo = saldo - v_cant WHERE id_lote = v_lote.id_lote;

      ELSIF v_estado_res = 'cancelada' THEN
        INSERT INTO movimiento_inventario
          (id_lote, id_reserva, id_usuario, tipo, cantidad, motivo, fecha)
        VALUES (v_lote.id_lote, v_id_reserva, v_gestor, 'liberacion', v_cant,
                'Reserva cancelada',
                LEAST(v_fecha + interval '2 hours', now()));
        -- el saldo no cambia: la reserva y la liberación se compensan

      ELSE
        UPDATE lote SET saldo = saldo - v_cant WHERE id_lote = v_lote.id_lote;
      END IF;
    END LOOP;

    INSERT INTO solicitud_detalle (id_solicitud, id_categoria, id_unidad, cantidad_solicitada)
    VALUES (v_id_solicitud, v_cat, v_uni, v_total);
  END LOOP;

  -- 9. Lotes vencidos con saldo: lo que sobra se pierde
  INSERT INTO movimiento_inventario (id_lote, id_usuario, tipo, cantidad, motivo, fecha)
  SELECT id_lote, v_gestor, 'vencimiento', saldo, 'Lote vencido',
         (fecha_vencimiento + 1) + time '08:00'
  FROM lote
  WHERE fecha_vencimiento < CURRENT_DATE AND saldo > 0;

  UPDATE lote SET saldo = 0, estado = 'vencido'
  WHERE fecha_vencimiento < CURRENT_DATE AND saldo > 0;

  UPDATE lote SET estado = 'agotado'
  WHERE saldo = 0 AND estado = 'activo';
END $$;

COMMIT;