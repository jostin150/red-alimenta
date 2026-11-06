# Red Alimenta Medellín

Aplicación web para registrar donaciones de alimentos, controlar el inventario por lotes, recibir solicitudes de beneficiarios, reservar existencias con la regla FEFO (primero vence, primero sale) y dejar trazabilidad de cada entrega.

Proyecto integrador del curso Bases de datos II. Todos los datos son ficticios.

- **Base de datos:** PostgreSQL 
- **Aplicación:** Python 3.13 + Flask.

---

## 1. Requisitos

- PostgreSQL 16 o superior (Con pgAdmin).
- Python 3.13.


## 2. Instalación paso a paso

### 2.1 Crear la base de datos

En pgAdmin, con el usuario `postgres`, crea una base de datos llamada **`alimenta`**.
El nombre debe ser ese

### 2.2 Crear los roles y ponerles contraseña

1. Abre un Query Tool sobre la base `alimenta` y ejecuta `database/setup/01_crear_roles.sql`.
   Crea dos roles sin contraseña: `alimenta_app` (la aplicación) y `alimenta_lectura` (solo lectura).
2. Asígnale una contraseña a `alimenta_app` (escribe la tuya en lugar de `USA_TU_CONTRASENA`):

```sql
ALTER ROLE alimenta_app PASSWORD 'USA_TU_CONTRASENA';
```

### 2.3 Ejecutar las migraciones y los datos de prueba

En el Query Tool de `alimenta`, abre y ejecuta **en este orden**:

| Orden | Archivo | Qué hace |
|---|---|---|
| 1 | `database/migrations/001_tablas_base.sql` | Tablas base: roles, usuarios, donantes, sedes, catálogos, beneficiarios |
| 2 | `database/migrations/002_tablas_inventario.sql` | Lotes, solicitudes, reservas, entregas, movimientos y auditoría |
| 3 | `database/migrations/003_indices_y_vistas.sql` | Índices y 4 vistas |
| 4 | `database/migrations/004_procedimiento_reservar.sql` | Procedimiento de reserva FEFO |
| 5 | `database/migrations/005_procedimientos_entrega_cancelacion.sql` | Confirmar entrega y cancelar reserva |
| 6 | `database/migrations/006_funciones_y_triggers.sql` | Funciones y triggers (auditoría, estados, lote válido) |
| 7 | `database/migrations/007_comuna_beneficiario.sql` | Comuna del beneficiario |
| 8 | `database/migrations/008_reportes.sql` | Los 6 reportes obligatorios |
| 9 | `database/migrations/009_roles_y_permisos.sql` | Permisos mínimos por rol |
| 10 | `database/migrations/010_lo_que_faltaba.sql` | Puntos de entrega, consentimiento, lotes vencidos, historial protegido |
| 11 | `database/migrations/011_crear_solicitud.sql` | Procedimiento para crear solicitudes |
| 12 | `database/seeds/001_catalogos.sql` | Categorías y unidades |
| 13 | `database/seeds/002_datos_prueba.sql` | Usuarios, donantes, sedes, lotes, solicitudes, reservas y movimientos de prueba |
| 14 | `database/seeds/003_comunas.sql` | Comunas de los beneficiarios |
| 15 | `database/seeds/004_puntos_y_consentimiento.sql` | Puntos de entrega y consentimiento |

> NO EJECUTAR `database/seeds/000_limpiar_datos_prueba.sql`: borra todos los datos de prueba.

### 2.4 Preparar la aplicación

En la terminal, dentro de la carpeta del proyecto:


python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
```

Abre `.env` y completa:

```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=alimenta
DB_USER=alimenta_app
DB_PASSWORD=USA_TU_CONTRASENA
SECRET_KEY=una_frase_larga_y_secreta
```

Para generar una `SECRET_KEY`:

```terminal
python -c "import secrets; print(secrets.token_hex(32))"
```

El archivo `.env` nunca se sube a git (está en `.gitignore`).

### 2.5 Dar contraseña a los usuarios de demostración

```terminal
python crear_usuarios_demo.py
```

Guarda la contraseña de demostración protegida con hash para todos los usuarios `@alimenta.test`.

### 2.6 (Opcional) Verificar la conexión

```terminal
python probar_conexion.py
```

### 2.7 Iniciar la aplicación

```terminal
python app.py
```

Abrir http://127.0.0.1:5000 en el navegador.

## 3. Usuarios de demostración

Todos usan la contraseña de demostración **`Demo2026!`** (solo para pruebas,sirve por el moemnto).

| Rol | Correo |
|---|---|
| Administrador | `admin@alimenta.test` |
| Gestor | `gestor1@alimenta.test`, `gestor2@alimenta.test` |
| Beneficiario | `beneficiario1@alimenta.test` … `beneficiario60@alimenta.test` |

## 4. Recorrido de prueba (flujo completo)

1. Entra como `beneficiario1@alimenta.test`.
2. Ve a **Inventario** y mira lo disponible (solo lotes activos, no vencidos y con saldo).
3. Ve a **Solicitudes**, elige una categoría, escribe una cantidad y envía la solicitud. Queda en estado *pendiente*.
4. Cierra sesión y entra como `gestor1@alimenta.test`.
5. En **Solicitudes**, pulsa **Reservar** en la solicitud nueva. El sistema reserva con FEFO y crea la reserva.
6. En **Reservas**, elige el punto de entrega y confirma la **entrega** (o cancela la reserva con un motivo).
7. En **Entregas** verás el historial con el gestor responsable.

Casos que la base rechaza: reservar más de lo disponible, reservar un lote vencido, confirmar dos veces la misma entrega, cancelar una reserva ya entregada, borrar historial.

## 5. Pruebas

Los scripts están en `database/tests/`. Se ejecutan en el Query Tool de pgAdmin sobre la base `alimenta`.

| Archivo | Qué prueba |
|---|---|
| `001_catalogos.sql` | Catálogos cargados |
| `001_reservar_inventario.sql` | Reserva FEFO |
| `002_concurrencia.sql` | Dos sesiones intentan reservar el mismo saldo (instrucciones dentro del archivo) |
| `003_entrega_y_cancelacion.sql` | Entrega y cancelación |
| `005_reportes.sql` | Reportes |
| `006_cerrar_lo_que_faltaba.sql` | Marcado de lotes vencidos |
| `007_pruebas_funciones_y_triggers.sql` | Funciones y triggers (casos positivos y negativos) |
| `011_pruebas_crear_solicitud.sql` | Creación de solicitudes (4 casos). Al final se deshace todo con ROLLBACK |


## 6. Estructura del proyecto

```
app.py, auth.py, db.py      Aplicación Flask, control de roles y conexión
templates/, static/         Pantallas y estilos (html,css)
database/setup/             Creación de roles
database/migrations/        Estructura y objetos programables (numerados)
database/seeds/             Catálogos y datos de prueba
database/tests/             Pruebas SQL
database/queries/           Consultas de ejemplo
docs/                       Modelo entidad-relación y evidencias
```

## 7. Seguridad

- Contraseñas guardadas con hash (no en texto plano).
- Consultas parametrizadas: no se concatenan datos del usuario en el SQL.
- La aplicación se conecta con un rol de mínimo privilegio (`alimenta_app`).
- Reglas críticas (saldo no negativo, estados válidos, historial inmutable) las protege la base de datos, no solo la interfaz.
- Datos ficticios.
