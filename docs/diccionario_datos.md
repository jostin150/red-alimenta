# Diccionario de datos — Red Alimenta Medellín

Base de datos: `alimenta` (PostgreSQL). Estado después de las migraciones 001 a 017.

**Convenciones**

- *PK* = llave primaria · *FK* = llave foránea · *NN* = no admite nulos · *UQ* = valor único.
- Las llaves `id_*` son numéricas y se generan solas (`GENERATED ALWAYS AS IDENTITY`).
- Las fechas con hora usan `TIMESTAMPTZ` (con zona horaria). Las cantidades usan `NUMERIC(10,2)`.
- Los nombres de tablas y columnas van en minúscula, sin tildes y en singular.

## 1. Resumen de objetos

| Tipo de objeto | Cantidad | Detalle |
|---|---|---|
| Tablas | 19 | Secciones 2.1 a 2.6 |
| Vistas | 9 | Sección 3 |
| Funciones | 10 | Sección 4 |
| Procedimientos almacenados | 15 | Sección 5 |
| Disparadores (triggers) | 18 | Sección 6 |
| Índices adicionales | 12 | Sección 7 |
| Roles de base de datos | 2 | Sección 8 |

---

## 2. Tablas

### 2.1 Personas, roles y acceso

#### `rol`
Los cuatro perfiles de la aplicación: `donante`, `gestor`, `beneficiario` y `administrador`.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_rol | SMALLINT | NN | identidad | PK | Identificador del rol |
| nombre | VARCHAR(50) | NN | | UQ | Nombre del rol |

#### `usuario`
Toda persona que entra a la aplicación.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_usuario | INT | NN | identidad | PK | Identificador del usuario |
| nombre | VARCHAR(100) | NN | | | Nombre completo |
| correo | VARCHAR(150) | NN | | UQ | Correo; se usa para iniciar sesión |
| password_hash | TEXT | NN | | | Contraseña protegida con hash (nunca en texto plano) |
| activo | BOOLEAN | NN | TRUE | | Si es FALSE no puede iniciar sesión; el usuario no se borra |
| creado_en | TIMESTAMPTZ | NN | now() | | Fecha de creación |

#### `usuario_rol`
Qué roles tiene cada usuario (relación muchos a muchos).

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_usuario | INT | NN | | PK, FK → usuario | Usuario |
| id_rol | SMALLINT | NN | | PK, FK → rol | Rol asignado |

#### `usuario_donante`
Organización donante a la que pertenece un usuario con rol *donante*. *(Migración 012)*

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_usuario | INT | NN | | PK, FK → usuario | Usuario donante (uno solo por organización a la vez) |
| id_donante | INT | NN | | FK → donante | Organización a la que pertenece |

Regla: un usuario pertenece a una sola organización; una organización puede tener varios usuarios. `registrar_lote` solo deja a un donante registrar lotes en las sedes de su organización.

#### `beneficiario`
Perfil de la persona que recibe alimento.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_beneficiario | INT | NN | identidad | PK | Identificador del beneficiario |
| id_usuario | INT | NN | | UQ, FK → usuario | Usuario con el que ingresa |
| documento | VARCHAR(20) | NN | | UQ | Documento de identidad |
| programa | VARCHAR(100) | | | | Programa social al que pertenece |
| estado | VARCHAR(15) | NN | 'activo' | CHECK: `activo`, `suspendido`, `retirado` | Estado del beneficiario |
| comuna | VARCHAR(60) | | | | Comuna de residencia *(Migración 007)* |
| consentimiento | BOOLEAN | NN | FALSE | | Si aceptó el tratamiento de sus datos *(Migración 010)* |
| fecha_consentimiento | TIMESTAMPTZ | | | CHECK `ck_consentimiento_fecha`: si hay consentimiento, la fecha es obligatoria | Cuándo lo aceptó |

### 2.2 Donantes

#### `donante`
Organización que dona alimento.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_donante | INT | NN | identidad | PK | Identificador del donante |
| nombre | VARCHAR(100) | NN | | | Nombre de la organización |
| nit | VARCHAR(50) | | | UQ | NIT |
| tipo | VARCHAR(50) | NN | | CHECK: `tienda`, `panaderia`, `restaurante`, `otro` | Clase de donante |
| activo | BOOLEAN | NN | TRUE | | Si sigue participando |

#### `sede`
Lugar físico donde un donante entrega sus donaciones.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_sede | INT | NN | identidad | PK | Identificador de la sede |
| id_donante | INT | NN | | FK → donante | Donante dueño de la sede |
| nombre | VARCHAR(100) | NN | | UQ junto con id_donante | Nombre de la sede |
| direccion | VARCHAR(200) | NN | | | Dirección |
| barrio | VARCHAR(80) | | | | Barrio |

### 2.3 Catálogos

#### `categoria`
Grupo grande de alimentos (Panadería, Frutas y verduras, Lácteos, Carnes, Pescados, Granos y cereales, Comida preparada, Enlatados y empacados, Bebidas).

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_categoria | SMALLINT | NN | identidad | PK | Identificador de la categoría |
| nombre | VARCHAR(60) | NN | | UQ | Nombre |

#### `tipo_alimento`
Tipo específico dentro de una categoría (por ejemplo, Bebidas → Agua, Gaseosa, Jugo). Cada categoría tiene además un tipo "Otro". *(Migración 013)*

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_tipo | INT | NN | identidad | PK | Identificador del tipo |
| id_categoria | SMALLINT | NN | | FK → categoria | Categoría a la que pertenece |
| nombre | VARCHAR(80) | NN | | UQ junto con id_categoria | Nombre del tipo |
| activo | BOOLEAN | NN | TRUE | | Si es FALSE deja de ofrecerse en los formularios |

Restricción adicional: `UNIQUE (id_tipo, id_categoria)`, necesaria para las llaves compuestas de `lote` y `solicitud_detalle`.

#### `unidad`
Unidad de medida de las cantidades.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_unidad | SMALLINT | NN | identidad | PK | Identificador de la unidad |
| nombre | VARCHAR(30) | NN | | UQ | Nombre (Kilogramo, Litro…) |
| abreviatura | VARCHAR(10) | NN | | UQ | Abreviatura (kg, l…) |

#### `punto_entrega`
Sitio donde el beneficiario recoge su alimento. *(Migración 010)*

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_punto | INT | NN | identidad | PK | Identificador del punto |
| nombre | VARCHAR(100) | NN | | UQ | Nombre del punto |
| direccion | VARCHAR(200) | NN | | | Dirección |
| comuna | VARCHAR(60) | | | | Comuna donde está |
| activo | BOOLEAN | NN | TRUE | | Si es FALSE deja de ofrecerse |

### 2.4 Inventario

#### `lote`
Tanda de alimento donada. Es la unidad del inventario.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_lote | INT | NN | identidad | PK | Identificador del lote |
| id_sede | INT | NN | | FK → sede | Sede donde se recibió |
| id_categoria | SMALLINT | NN | | FK → categoria | Categoría |
| id_tipo | INT | NN | | FK compuesta `fk_lote_tipo` (id_tipo, id_categoria) → tipo_alimento | Tipo de alimento *(Migración 013)* |
| id_unidad | SMALLINT | NN | | FK → unidad | Unidad de medida |
| descripcion | VARCHAR(150) | NN | | | Descripción del lote |
| cantidad_inicial | NUMERIC(10,2) | NN | | CHECK > 0 | Cantidad recibida |
| saldo | NUMERIC(10,2) | NN | | CHECK ≥ 0 y CHECK ≤ cantidad_inicial | Cantidad disponible (nunca negativa) |
| fecha_recepcion | DATE | NN | CURRENT_DATE | | Día en que llegó |
| fecha_vencimiento | DATE | NN | | CHECK ≥ fecha_recepcion | Día en que vence (no se recibe comida ya vencida) |
| estado | VARCHAR(15) | NN | 'activo' | CHECK: `activo`, `agotado`, `vencido`, `rechazado`, `cancelado` | Estado del lote |
| creado_en | TIMESTAMPTZ | NN | now() | | Fecha de registro |

#### `movimiento_inventario`
Libro de movimientos: cada vez que el inventario cambia queda una fila. **Solo se agrega: no se modifica ni se borra.**

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_movimiento | BIGINT | NN | identidad | PK | Identificador del movimiento |
| id_lote | INT | NN | | FK → lote | Lote afectado |
| id_reserva | INT | | | FK → reserva | Reserva que lo originó, si aplica |
| id_usuario | INT | | | FK → usuario | Quién lo hizo |
| tipo | VARCHAR(15) | NN | | CHECK: `entrada`, `reserva`, `liberacion`, `salida`, `ajuste`, `vencimiento` | Clase de movimiento |
| cantidad | NUMERIC(10,2) | NN | | CHECK > 0 | Cantidad movida |
| motivo | VARCHAR(200) | | | | Explicación |
| fecha | TIMESTAMPTZ | NN | now() | | Cuándo ocurrió |

### 2.5 Solicitudes, reservas y entregas

#### `solicitud`
Pedido de alimento hecho por un beneficiario.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_solicitud | INT | NN | identidad | PK | Identificador de la solicitud |
| id_beneficiario | INT | NN | | FK → beneficiario | Quién la hizo |
| id_punto | INT | | | FK → punto_entrega | Punto donde el beneficiario quiere recoger *(Migración 013)*. Opcional en la base por las solicitudes anteriores; la aplicación lo exige en las nuevas |
| fecha_solicitud | TIMESTAMPTZ | NN | now() | | Cuándo se hizo |
| estado | VARCHAR(15) | NN | 'pendiente' | CHECK: `pendiente`, `reservada`, `entregada`, `cancelada`, `rechazada` | Estado de la solicitud |
| observacion | VARCHAR(300) | | | | Nota o motivo de cancelación |

#### `solicitud_detalle`
Qué pidió el beneficiario (tipo y cantidad).

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_detalle | INT | NN | identidad | PK | Identificador del detalle |
| id_solicitud | INT | NN | | FK → solicitud | Solicitud a la que pertenece |
| id_categoria | SMALLINT | NN | | FK → categoria | Categoría pedida (se deduce del tipo) |
| id_tipo | INT | NN | | FK compuesta `fk_detalle_tipo` (id_tipo, id_categoria) → tipo_alimento | Tipo pedido *(Migración 013)* |
| id_unidad | SMALLINT | NN | | FK → unidad | Unidad |
| cantidad_solicitada | NUMERIC(10,2) | NN | | CHECK > 0 | Cantidad pedida |

Restricción adicional: `UNIQUE (id_solicitud, id_tipo)` (`uq_detalle_solicitud_tipo`): un tipo no se repite dentro de una solicitud.

#### `reserva`
Apartado de inventario para una solicitud.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_reserva | INT | NN | identidad | PK | Identificador de la reserva |
| id_solicitud | INT | NN | | FK → solicitud | Solicitud atendida |
| fecha_reserva | TIMESTAMPTZ | NN | now() | | Cuándo se reservó |
| estado | VARCHAR(15) | NN | 'activa' | CHECK: `activa`, `entregada`, `cancelada`, `vencida` | Estado de la reserva |

#### `reserva_detalle`
De qué lotes sale lo reservado.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_reserva_detalle | INT | NN | identidad | PK | Identificador |
| id_reserva | INT | NN | | FK → reserva | Reserva |
| id_lote | INT | NN | | FK → lote | Lote que aporta |
| cantidad | NUMERIC(10,2) | NN | | CHECK > 0 | Cantidad tomada del lote |

Restricción adicional: `UNIQUE (id_reserva, id_lote)`.

#### `entrega`
Confirmación de que el beneficiario recibió su alimento.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_entrega | INT | NN | identidad | PK | Identificador de la entrega |
| id_reserva | INT | NN | | UQ, FK → reserva | Reserva entregada (una reserva se entrega una sola vez) |
| id_usuario_gestor | INT | NN | | FK → usuario | Gestor que confirmó |
| id_punto | INT | | | FK → punto_entrega | Punto donde se entregó *(Migración 010)* |
| fecha_entrega | TIMESTAMPTZ | NN | now() | | Cuándo se entregó |
| observacion | VARCHAR(300) | | | | Nota |

### 2.6 Control

#### `auditoria`
Historial de cambios sensibles. **Solo se agrega.** Solo la puede consultar un administrador, mediante `ver_auditoria`.

| Columna | Tipo | Nulo | Por defecto | Restricciones | Descripción |
|---|---|---|---|---|---|
| id_auditoria | BIGINT | NN | identidad | PK | Identificador |
| tabla | VARCHAR(50) | NN | | | Tabla afectada |
| operacion | VARCHAR(10) | NN | | CHECK: `INSERT`, `UPDATE`, `DELETE` | Operación |
| id_registro | VARCHAR(50) | | | | Identificador del registro afectado |
| datos_anteriores | JSONB | | | | Contenido antes del cambio |
| datos_nuevos | JSONB | | | | Contenido después del cambio |
| id_usuario | INT | | | FK → usuario | Quién hizo el cambio |
| fecha | TIMESTAMPTZ | NN | now() | | Cuándo |

### 2.7 Estados y sus transiciones

| Entidad | Estados | Cómo se pasa de uno a otro |
|---|---|---|
| `solicitud` | pendiente → reservada → entregada; también cancelada y rechazada | `reservar_inventario` (pendiente → reservada), `confirmar_entrega` (→ entregada), `cancelar_reserva` y `cancelar_solicitud` (→ cancelada) |
| `reserva` | activa → entregada / cancelada / vencida | Solo se permite salir de *activa*; cualquier otro cambio lo rechaza el trigger `trg_validar_estado_reserva` |
| `lote` | activo → agotado / vencido; agotado → activo (al devolver saldo); también rechazado y cancelado | `reservar_inventario` (agotado cuando el saldo llega a 0), cancelaciones (agotado → activo), `marcar_lotes_vencidos` (→ vencido) |
| `beneficiario` | activo, suspendido, retirado | Solo `activo` puede solicitar y recibir reservas |

---

## 3. Vistas

| Vista | Qué muestra | Columnas |
|---|---|---|
| `v_inventario_disponible` | Lotes activos, con saldo y no vencidos | id_lote, donante, sede, categoria, descripcion, saldo, unidad, fecha_vencimiento, dias_para_vencer |
| `v_alertas_vencimiento` | Los de la anterior que vencen en 3 días o menos | Las mismas de `v_inventario_disponible` |
| `v_historial_movimientos` | Movimientos con datos legibles | id_movimiento, fecha, tipo, cantidad, unidad, id_lote, descripcion, id_reserva, usuario, motivo |
| `v_indicador_mensual` | Donado, entregado y perdido por mes y unidad | mes, unidad, donado, entregado, perdido |
| `v_reporte_inventario_sede_categoria` | Inventario por donante, sede y categoría | donante, sede, categoria, unidad, lotes, saldo_disponible, saldo_por_vencer, proximo_vencimiento |
| `v_reporte_balance_mensual` | Recibido, entregado, cancelado y perdido por mes | mes, unidad, recibido, entregado, cancelado, perdido |
| `v_reporte_aprovechamiento` | Tasa de aprovechamiento y días promedio hasta la entrega | mes, unidad, recibido, entregado, tasa_aprovechamiento, dias_medios_hasta_entrega |
| `v_reporte_beneficiarios_comuna` | Beneficiarios atendidos y entregas por comuna (solo comunas con 3 o más beneficiarios, para proteger la privacidad) | comuna, beneficiarios_atendidos, entregas |
| `v_reporte_donantes` | Ranking de donantes por lotes y regularidad | posicion, donante, lotes, kg_donados, meses_activos, regularidad_pct, ultima_donacion |

---

## 4. Funciones

| Función | Parámetros | Devuelve | Descripción |
|---|---|---|---|
| `saldo_lote_a_fecha` | p_id_lote INT, p_fecha DATE | NUMERIC(10,2) | Saldo que tenía un lote en una fecha, reconstruido con los movimientos |
| `tasa_aprovechamiento` | p_desde DATE, p_hasta DATE, p_unidad VARCHAR = 'kg' | NUMERIC(5,2) | (Entregado ÷ recibido) × 100 en un período |
| `trazabilidad_lote` | p_id_lote INT | Tabla: fecha, tipo, cantidad, unidad, id_reserva, id_solicitud, comuna, registrado_por, saldo_despues | Recorrido completo de un lote, de la entrada a la entrega |
| `ver_auditoria` | p_id_usuario INT, p_limite INT = 100 | Tabla con las columnas de `auditoria` | Solo un administrador activo puede consultarla |
| `verificar_admin` | p_id_usuario INT | VOID | Interna: lanza error si quien llama no es administrador activo *(Migración 016)* |
| `auditar_cambio` | (trigger) | TRIGGER | Guarda en `auditoria` el antes y el después de un cambio |
| `validar_cambio_estado_reserva` | (trigger) | TRIGGER | Solo deja pasar una reserva de *activa* a entregada, cancelada o vencida |
| `validar_lote_en_reserva` | (trigger) | TRIGGER | Rechaza reservar de un lote inactivo, vencido o con menos saldo del pedido |
| `impedir_borrado` | (trigger) | TRIGGER | Lanza error al intentar borrar una fila de una tabla protegida |
| `impedir_modificacion` | (trigger) | TRIGGER | Lanza error al intentar modificar o borrar filas de una tabla de solo agregar |

---

## 5. Procedimientos almacenados

Todos se ejecutan con los permisos de su dueño (`SECURITY DEFINER`) y fijan `search_path = public, pg_temp`. La aplicación no escribe directamente en las tablas del negocio: llama a estos procedimientos, que primero comprueban quién es la persona y qué puede hacer.

### 5.1 Inventario

| Procedimiento | Parámetros | Quién puede | Qué hace |
|---|---|---|---|
| `registrar_lote` | p_id_usuario, p_id_sede, p_id_tipo, p_id_unidad, p_descripcion, p_cantidad, p_fecha_vencimiento, **INOUT** p_id_lote | donante, gestor, administrador | Crea el lote y su movimiento de entrada. La categoría sale del tipo. Un donante solo registra en sedes de su organización |
| `marcar_lotes_vencidos` | p_id_usuario, **INOUT** p_lotes_marcados | gestor, administrador | Pasa a *vencido* los lotes caducados con saldo y registra la pérdida como movimiento |

### 5.2 Solicitudes, reservas y entregas

| Procedimiento | Parámetros | Quién puede | Qué hace |
|---|---|---|---|
| `crear_solicitud` | p_id_usuario, p_id_tipo, p_id_unidad, p_cantidad, p_id_punto, **INOUT** p_id_solicitud | beneficiario activo con consentimiento | Crea la solicitud y su detalle. Valida cantidad, unidad, tipo activo y punto activo |
| `reservar_inventario` | p_id_solicitud, p_id_usuario, **INOUT** p_id_reserva | gestor, administrador (desde la aplicación) | Reserva el inventario del tipo pedido eligiendo primero los lotes que vencen antes (FEFO). Exige solicitud pendiente, beneficiario activo y con consentimiento. Si falta inventario, no reserva nada |
| `cancelar_solicitud` | p_id_solicitud, p_id_usuario, p_motivo = NULL | el propio beneficiario | Cancela su solicitud si está pendiente o reservada. Si estaba reservada, devuelve el inventario y anota las liberaciones |
| `cancelar_reserva` | p_id_reserva, p_id_usuario, p_motivo = NULL | gestor, administrador | Cancela una reserva activa, devuelve el saldo a los lotes y anota las liberaciones |
| `confirmar_entrega` | p_id_reserva, p_id_usuario, p_id_punto, p_observacion = NULL, **INOUT** p_id_entrega | gestor, administrador | Crea la entrega en un punto activo, anota las salidas de inventario y cierra la reserva y la solicitud. Rechaza reservas con lotes vencidos |

### 5.3 Administración *(Migración 016; solo administrador)*

Todos comienzan con `verificar_admin`. Los cambios de catálogos quedan en `auditoria`.

| Procedimiento | Parámetros | Qué hace |
|---|---|---|
| `admin_guardar_categoria` | p_admin, p_id, p_nombre | Crea (p_id nulo) o renombra una categoría |
| `admin_guardar_tipo` | p_admin, p_id, p_id_categoria, p_nombre, p_activo | Crea un tipo o cambia su nombre y estado (la categoría no cambia) |
| `admin_guardar_unidad` | p_admin, p_id, p_nombre, p_abreviatura | Crea o edita una unidad |
| `admin_guardar_punto` | p_admin, p_id, p_nombre, p_direccion, p_comuna, p_activo | Crea o edita un punto de entrega |
| `admin_crear_usuario` | p_admin, p_nombre, p_correo, p_password_hash, p_rol, p_id_donante, **INOUT** p_id_usuario | Crea un usuario administrador, gestor o donante (el donante exige organización activa) |
| `admin_estado_usuario` | p_admin, p_id_usuario, p_activo | Activa o desactiva un usuario. No permite desactivarse a sí mismo ni dejar la red sin administrador activo |
| `admin_asignar_rol` | p_admin, p_id_usuario, p_rol, p_id_donante | Agrega un rol (administrador, gestor o donante) |
| `admin_quitar_rol` | p_admin, p_id_usuario, p_rol | Quita un rol. No permite quitarse a sí mismo el de administrador ni dejar la red sin administrador |

El rol *beneficiario* no se asigna ni se quita desde la administración: los beneficiarios se registran con documento y consentimiento.

---

## 6. Disparadores (triggers)

| Trigger | Tabla | Momento | Qué hace |
|---|---|---|---|
| `trg_auditoria_reserva` | reserva | Después de cambiar el estado | Guarda el cambio en `auditoria` |
| `trg_auditoria_entrega` | entrega | Después de insertar | Guarda la entrega en `auditoria` |
| `trg_auditoria_usuario_rol` | usuario_rol | Después de insertar o borrar | Guarda la asignación o retiro de roles |
| `trg_auditoria_lote` | lote | Después de cambiar el estado | Guarda el cambio de estado |
| `trg_auditoria_categoria` | categoria | Después de insertar o actualizar | Guarda el cambio *(Migración 016)* |
| `trg_auditoria_tipo_alimento` | tipo_alimento | Después de insertar o actualizar | Guarda el cambio *(016)* |
| `trg_auditoria_unidad` | unidad | Después de insertar o actualizar | Guarda el cambio *(016)* |
| `trg_auditoria_punto_entrega` | punto_entrega | Después de insertar o actualizar | Guarda el cambio *(016)* |
| `trg_validar_estado_reserva` | reserva | Antes de cambiar el estado | Solo permite activa → entregada, cancelada o vencida |
| `trg_validar_lote_en_reserva` | reserva_detalle | Antes de insertar | Rechaza lotes inactivos, vencidos o sin saldo suficiente |
| `trg_no_borrar` (6) | lote, solicitud, solicitud_detalle, reserva, reserva_detalle, entrega | Antes de borrar | Prohíbe borrar: se usan estados o anulaciones trazables |
| `trg_solo_agregar` (2) | movimiento_inventario, auditoria | Antes de actualizar o borrar | Son tablas de solo agregar |

En total son 18: 8 de auditoría, 2 de validación, 6 de `trg_no_borrar` (uno por tabla) y 2 de `trg_solo_agregar`. La tabla `usuario` no se audita para no copiar contraseñas al historial.

---

## 7. Índices adicionales

Además de los que PostgreSQL crea solos para llaves primarias y valores únicos.

| Índice | Tabla | Columnas | Para qué |
|---|---|---|---|
| `idx_lote_fefo` | lote | (id_categoria, fecha_vencimiento) donde estado = 'activo' y saldo > 0 | Elegir rápido los lotes que vencen primero |
| `idx_lote_tipo_vence` | lote | (id_tipo, fecha_vencimiento) | Lo mismo, por tipo *(013)* |
| `idx_lote_sede` | lote | id_sede | Lotes de una sede |
| `idx_movimiento_lote` | movimiento_inventario | (id_lote, fecha) | Historial de un lote |
| `idx_solicitud_beneficiario` | solicitud | (id_beneficiario, estado) | Solicitudes de una persona |
| `idx_solicitud_punto` | solicitud | id_punto | Solicitudes por punto *(013)* |
| `idx_reserva_solicitud` | reserva | id_solicitud | Reservas de una solicitud |
| `idx_reserva_detalle_lote` | reserva_detalle | id_lote | Reservas que usan un lote |
| `idx_auditoria_tabla` | auditoria | (tabla, fecha) | Consultar la auditoría |
| `idx_entrega_punto` | entrega | id_punto | Entregas por punto *(010)* |
| `idx_tipo_categoria` | tipo_alimento | id_categoria | Tipos de una categoría *(013)* |
| `idx_usuario_donante_donante` | usuario_donante | id_donante | Usuarios de un donante *(012)* |

---

## 8. Roles de base de datos y permisos

| Rol | Uso | Permisos |
|---|---|---|
| `alimenta_app` | La aplicación web | Lee las tablas del negocio (no la auditoría); escribe solo mediante procedimientos, salvo operaciones puntuales de personas y catálogos; ejecuta los procedimientos y las funciones de consulta |
| `alimenta_lectura` | Reportes | Solo lee las vistas agregadas (sin datos personales) y ejecuta `tasa_aprovechamiento` |

Por defecto se retira todo permiso al grupo `PUBLIC`: lo que no se concede, no se puede hacer.

## 9. Reglas de integridad principales

| Regla | Dónde se hace cumplir |
|---|---|
| El saldo de un lote nunca es negativo ni mayor a lo recibido | CHECK en `lote` |
| No se recibe comida ya vencida | CHECK en `lote` |
| Se entrega primero lo que vence primero (FEFO) | `reservar_inventario` |
| No se reserva de lotes vencidos, inactivos o sin saldo | `trg_validar_lote_en_reserva` |
| Si no hay inventario suficiente, no se reserva nada | `reservar_inventario` (la transacción se deshace) |
| Solo un beneficiario activo y con consentimiento solicita y recibe reservas | `crear_solicitud`, `reservar_inventario` |
| El tipo de alimento pertenece a su categoría | Llaves compuestas `fk_lote_tipo` y `fk_detalle_tipo` |
| Una reserva se entrega una sola vez | UNIQUE en `entrega.id_reserva` y `trg_validar_estado_reserva` |
| El historial no se borra ni se altera | `trg_no_borrar` y `trg_solo_agregar` |
| Un donante solo registra en las sedes de su organización | `registrar_lote` y `usuario_donante` |
| Siempre queda al menos un administrador activo | `admin_estado_usuario`, `admin_quitar_rol` |
| Los cambios sensibles quedan registrados con su autor | `auditar_cambio` y la variable `app.id_usuario` que fija la aplicación |
