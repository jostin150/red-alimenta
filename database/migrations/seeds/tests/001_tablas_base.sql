BEGIN;

CREATE TABLE rol (
    id_rol SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE usuario (
    id_usuario INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    correo VARCHAR(150) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE usuario_rol (
    id_usuario INT NOT NULL REFERENCES usuario(id_usuario),
    id_rol SMALLINT NOT NULL REFERENCES rol(id_rol),
    PRIMARY KEY (id_usuario, id_rol)
);

CREATE TABLE donante (
     id_donante INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     nombre VARCHAR(100) NOT NULL,
     nit VARCHAR(50) UNIQUE,
     tipo VARCHAR(50) NOT NULL,
        CHECK (tipo IN ('tienda', 'panaderia', 'restaurante', 'otro')),
        activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE sede (
    id_sede INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_donante INT NOT NULL REFERENCES donante(id_donante),
  nombre VARCHAR(100) NOT NULL,
  direccion VARCHAR(200) NOT NULL,
  barrio VARCHAR(80),
  UNIQUE (id_donante, nombre)
);

CREATE TABLE categoria (
  id_categoria SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE unidad (
  id_unidad SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre VARCHAR(30) NOT NULL UNIQUE,
  abreviatura VARCHAR(10) NOT NULL UNIQUE
);

CREATE TABLE beneficiario (
  id_beneficiario INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario INT NOT NULL UNIQUE REFERENCES usuario(id_usuario),
  documento VARCHAR(20) NOT NULL UNIQUE,
  programa VARCHAR(100),
  estado VARCHAR(15) NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo','suspendido','retirado'))
);

COMMIT;
