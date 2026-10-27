BEGIN;

--comida que llega--
CREATE TABLE lote (
  id_lote INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_sede INT NOT NULL REFERENCES sede(id_sede),
  id_categoria SMALLINT NOT NULL REFERENCES categoria(id_categoria),
  id_unidad SMALLINT NOT NULL REFERENCES unidad(id_unidad),
  descripcion VARCHAR(150) NOT NULL,
  cantidad_inicial NUMERIC(10,2) NOT NULL CHECK (cantidad_inicial > 0),
  saldo NUMERIC(10,2) NOT NULL CHECK (saldo >= 0),--nunca puede ser negativo--
  fecha_recepcion DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_vencimiento DATE NOT NULL,
  estado VARCHAR(15) NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo','agotado','vencido','rechazado','cancelado')),
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (saldo <= cantidad_inicial),--saldo no puede ser mayor a l que ha entrado--
  CHECK (fecha_vencimiento >= fecha_recepcion)--no recibe comida ya vvencida--
);

--que  pide  un beneficiario--
CREATE TABLE solicitud (
  id_solicitud INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_beneficiario INT NOT NULL REFERENCES beneficiario(id_beneficiario),
  fecha_solicitud TIMESTAMPTZ NOT NULL DEFAULT now(),
  estado VARCHAR(15) NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente','reservada','entregada','cancelada','rechazada')),
  observacion VARCHAR(300)
);

--detalles categoria y cantidad--
CREATE TABLE solicitud_detalle (
  id_detalle INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_solicitud INT NOT NULL REFERENCES solicitud(id_solicitud),
  id_categoria SMALLINT NOT NULL REFERENCES categoria(id_categoria),
  id_unidad SMALLINT NOT NULL REFERENCES unidad(id_unidad),
  cantidad_solicitada NUMERIC(10,2) NOT NULL CHECK (cantidad_solicitada > 0),
  UNIQUE (id_solicitud, id_categoria)
);

--aparte para una solicitud--
CREATE TABLE reserva (
  id_reserva INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_solicitud INT NOT NULL REFERENCES solicitud(id_solicitud),
  fecha_reserva TIMESTAMPTZ NOT NULL DEFAULT now(),
  estado VARCHAR(15) NOT NULL DEFAULT 'activa'
    CHECK (estado IN ('activa','entregada','cancelada','vencida'))
);

--de que lote sale lo reservado--
CREATE TABLE reserva_detalle (
  id_reserva_detalle INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_reserva INT NOT NULL REFERENCES reserva(id_reserva),
  id_lote INT NOT NULL REFERENCES lote(id_lote),
  cantidad NUMERIC(10,2) NOT NULL CHECK (cantidad > 0),--debe ser mayor a 0--
  UNIQUE (id_reserva, id_lote)
);

--confirmacion de entrega--
CREATE TABLE entrega (
  id_entrega INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_reserva INT NOT NULL UNIQUE REFERENCES reserva(id_reserva),
  id_usuario_gestor INT NOT NULL REFERENCES usuario(id_usuario),
  fecha_entrega TIMESTAMPTZ NOT NULL DEFAULT now(),
  observacion VARCHAR(300)
);

--entradas y salidas de inventario--
CREATE TABLE movimiento_inventario (
  id_movimiento BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_lote INT NOT NULL REFERENCES lote(id_lote),
  id_reserva INT REFERENCES reserva(id_reserva),
  id_usuario INT REFERENCES usuario(id_usuario),
  tipo VARCHAR(15) NOT NULL
    CHECK (tipo IN ('entrada','reserva','liberacion','salida','ajuste','vencimiento')),
  cantidad NUMERIC(10,2) NOT NULL CHECK (cantidad > 0),
  motivo VARCHAR(200),
  fecha TIMESTAMPTZ NOT NULL DEFAULT now()
);

--historial de cambios sensibles--
CREATE TABLE auditoria (
  id_auditoria BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tabla VARCHAR(50) NOT NULL,
  operacion VARCHAR(10) NOT NULL
    CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
  id_registro VARCHAR(50),
  datos_anteriores JSONB,
  datos_nuevos JSONB,
  id_usuario INT REFERENCES usuario(id_usuario),
  fecha TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;