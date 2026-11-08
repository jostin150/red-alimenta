# Red Alimenta Medellín

Aplicación web para registrar donaciones de alimentos, controlar el inventario por lotes, recibir solicitudes de beneficiarios, reservar existencias con la regla FEFO (primero vence, primero sale) y dejar trazabilidad de cada entrega.

Proyecto integrador del curso Bases de datos II. Todos los datos son ficticios.

- **Base de datos:** PostgreSQL
- **Aplicación:** Python 3.13 + Flask

## Documentación

| Documento | Contenido |
|---|---|
| [Manual de usuario](docs/manual_usuario.md) | Cómo usar la aplicación según el rol, con capturas |
| [Manual técnico](docs/manual_tecnico.md) | Arquitectura, rutas, seguridad, migraciones y mantenimiento |
| [Modelo entidad-relación](docs/modelo_er.md) | Diagrama de la base de datos |
| [Diccionario de datos](docs/diccionario_datos.md) | Tablas, columnas, vistas, funciones, procedimientos y triggers |
| [Matriz de trazabilidad](docs/matriz_trazabilidad.md) | Requerimientos, dónde se cumplen y cómo se prueban |

---

## 1. Requisitos

- PostgreSQL 16 o superior (con pgAdmin).
- Python 3.13.
- VS Code (recomendado) y un navegador.

## 2. Instalación paso a paso

### 2.0 Antes de empezar: la idea general

Instalar el proyecto es armar la base de datos en **tres bloques, siempre en este orden**, y luego encender la aplicación:

| Bloque | Qué se hace | Archivos |
|---|---|---|
| **A. Estructura** | Se construyen las tablas y las reglas | Migraciones `001` a `012` |
| **B. Datos** | Se cargan catálogos y datos de prueba | Seeds `001` a `005` |
| **C. Mejoras** | Se agregan tipos de alimento, punto de entrega, administración y correcciones | Migraciones `013` a `017` |

El bloque B va **antes** que el C porque los datos de prueba se crearon antes de que existieran los tipos de alimento. La migración `013` se encarga de asignarles un tipo a esos datos. Si cargas los datos después del bloque C, fallan.

Cada archivo SQL se ejecuta **una sola vez**. Si lo repites, aparecen errores como "ya existe".

### 2.1 Crear la base de datos

En pgAdmin, con el usuario `postgres`, crea una base de datos llamada **`alimenta`**. El nombre debe ser ese.

### 2.2 Crear los roles y ponerles contraseña

1. Abre un Query Tool sobre la base `alimenta` y ejecuta `database/setup/01_crear_roles.sql`. Crea dos roles sin contraseña: `alimenta_app` (la aplicación) y `alimenta_lectura` (solo lectura).
2. Asígnale una contraseña a `alimenta_app` (escribe la tuya en lugar de `USA_TU_CONTRASENA`):

```sql
ALTER ROLE alimenta_app PASSWORD 'USA_TU_CONTRASENA';
```

### 2.3 Cómo ejecutar cada archivo SQL

1. En pgAdmin, haz clic derecho sobre la base `alimenta` → **Query Tool**.
2. Pulsa el ícono de la carpeta (**Open File**) y elige el archivo.
3. Pulsa **F5** (o el botón ▶).
4. Espera el mensaje verde "Query returned successfully". Si sale un mensaje rojo, **detente** y revisa el error antes de seguir.

### 2.4 Bloque A: estructura (migraciones 001 a 012)

Ejecuta en este orden, desde `database/migrations/`:

| Orden | Archivo | Qué hace |
|---|---|---|
| 1 | `001_tablas_base.sql` | Roles, usuarios, donantes, sedes, catálogos y beneficiarios |
| 2 | `002_tablas_inventario.sql` | Lotes, solicitudes, reservas, entregas, movimientos y auditoría |
| 3 | `003_indices_y_vistas.sql` | Índices y 4 vistas |
| 4 | `004_procedimiento_reservar.sql` | Reserva FEFO (primera versión) |
| 5 | `005_procedimientos_entrega_cancelacion.sql` | Confirmar entrega y cancelar reserva |
| 6 | `006_funciones_y_triggers.sql` | Funciones y triggers (auditoría, estados, lote válido) |
| 7 | `007_comuna_beneficiario.sql` | Comuna del beneficiario |
| 8 | `008_reportes.sql` | Reportes y trazabilidad |
| 9 | `009_roles_y_permisos.sql` | Permisos mínimos por rol |
| 10 | `010_lo_que_faltaba.sql` | Puntos de entrega, consentimiento, lotes vencidos, historial protegido |
| 11 | `011_crear_solicitud.sql` | Procedimiento para crear solicitudes (primera versión) |
| 12 | `012_usuario_donante.sql` | Vínculo usuario–donante y registro de lotes por donantes |

### 2.5 Bloque B: datos (seeds 001 a 005)

Ejecuta en este orden, desde `database/seeds/`:

| Orden | Archivo | Qué hace |
|---|---|---|
| 13 | `001_catalogos.sql` | Categorías y unidades |
| 14 | `002_datos_prueba.sql` | Usuarios, donantes, sedes, lotes, solicitudes, reservas y movimientos de prueba |
| 15 | `003_comunas.sql` | Comunas de los beneficiarios |
| 16 | `004_puntos_y_consentimiento.sql` | Puntos de entrega y consentimiento |
| 17 | `005_usuarios_donantes.sql` | Dos usuarios donantes de demostración |

> **No ejecutes** `database/seeds/000_limpiar_datos_prueba.sql`: borra todos los datos de prueba.

### 2.6 Bloque C: mejoras (migraciones 013 a 017)

Ejecuta en este orden, desde `database/migrations/`:

| Orden | Archivo | Qué hace |
|---|---|---|
| 18 | `013_tipos_y_punto_solicitud.sql` | Tipos de alimento, punto de entrega en la solicitud, Carnes y Pescados separadas |
| 19 | `014_solicitud_con_tipo_punto_y_cancelacion.sql` | Solicitud con tipo y punto, reserva por tipo, cancelación del beneficiario |
| 20 | `015_registrar_lote_con_tipo.sql` | Registro de lotes con tipo de alimento |
| 21 | `016_administracion.sql` | Administración de catálogos, usuarios y roles |
| 22 | `017_corregir_reserva_consentimiento.sql` | Exige consentimiento al reservar |

### 2.7 (Opcional) Repartir los tipos de los datos de prueba

Ejecuta `database/seeds/006_repartir_tipos_prueba.sql`. Los lotes de prueba quedan con el tipo "Otro" tras la migración 013; este archivo los reparte entre tipos reales (Agua, Gaseosa, Arroz…) para que las listas de la aplicación tengan variedad.

### 2.8 Comprobar que la base quedó completa

Ejecuta estas dos consultas en el Query Tool:

```sql
SELECT count(*) AS tablas
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

SELECT count(*) AS procedimientos
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'p';
```

Deben dar **19 tablas** y **15 procedimientos**. Si los números no coinciden, falta o sobra algún archivo: revisa las tablas de arriba.

### 2.9 Preparar la aplicación

En la terminal, dentro de la carpeta del proyecto:

```
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

`DB_PASSWORD` debe ser la misma que pusiste en el paso 2.2. Para generar una `SECRET_KEY`:

```
python -c "import secrets; print(secrets.token_hex(32))"
```

El archivo `.env` nunca se sube a git (está en `.gitignore`).

### 2.10 Dar contraseña a los usuarios de demostración

```
python crear_usuarios_demo.py
```

Guarda la contraseña de demostración, protegida con hash, para todos los usuarios `@alimenta.test`.

### 2.11 (Opcional) Verificar la conexión

```
python probar_conexion.py
```

### 2.12 Iniciar la aplicación

```
python app.py
```

Abre http://127.0.0.1:5000 en el navegador. No cierres la terminal mientras uses la aplicación.

---

## 3. Instalar en otro computador: lista de verificación

Marca cada paso al terminarlo.

- [ ] **1.** Instalar PostgreSQL 16+ (con pgAdmin) y Python 3.13.
- [ ] **2.** Copiar la carpeta del proyecto **sin** la subcarpeta `venv` (se vuelve a crear en el paso 9).
- [ ] **3.** En pgAdmin, crear la base `alimenta`.
- [ ] **4.** Ejecutar `setup/01_crear_roles.sql` y poner contraseña a `alimenta_app` (sección 2.2).
- [ ] **5.** Ejecutar las migraciones `001` a `012` (sección 2.4).
- [ ] **6.** Ejecutar los seeds `001` a `005` (sección 2.5).
- [ ] **7.** Ejecutar las migraciones `013` a `017` (sección 2.6).
- [ ] **8.** Comprobar 19 tablas y 15 procedimientos (sección 2.8).
- [ ] **9.** En la terminal: crear el entorno, instalar las librerías y crear el `.env` (sección 2.9).
- [ ] **10.** Ejecutar `python crear_usuarios_demo.py` y luego `python app.py`.

## 4. Usuarios de demostración

Todos usan la contraseña de demostración **`Demo2026!`** (solo para pruebas).

| Rol | Correo |
|---|---|
| Administrador | `admin@alimenta.test` |
| Gestor | `gestor1@alimenta.test`, `gestor2@alimenta.test` |
| Donante | `donante2@alimenta.test`, `donante3@alimenta.test` |
| Beneficiario | `beneficiario1@alimenta.test` … `beneficiario60@alimenta.test` |

## 5. Recorrido de prueba (flujo completo)

1. Entra como `beneficiario1@alimenta.test`.
2. Ve a **Inventario** y mira lo disponible (solo lotes activos, no vencidos y con saldo).
3. Ve a **Solicitudes**: elige una categoría, luego un tipo, escribe la cantidad, elige el punto de entrega y envía. Queda *pendiente*. (Aquí también puedes cancelarla.)
4. Cierra sesión y entra como `gestor1@alimenta.test`.
5. En **Solicitudes**, pulsa **Reservar** en la solicitud nueva. El sistema reserva con FEFO y crea la reserva.
6. En **Reservas**, revisa lo que pidió el beneficiario ("Ver lo que pidió"), confirma el punto de entrega (ya viene marcado el que eligió) y confirma la **entrega**, o cancela la reserva.
7. En **Entregas** verás el historial; "Ver detalle" muestra todo lo que pidió el beneficiario.
8. Entra como `admin@alimenta.test` y prueba **Catálogos** y **Usuarios**.

Casos que la base rechaza: reservar más de lo disponible, reservar un lote vencido, reservar para quien no dio su consentimiento, confirmar dos veces la misma entrega, cancelar una reserva ya entregada, borrar historial.

## 6. Pruebas

Los scripts están en `database/tests/`. Se ejecutan en el Query Tool de pgAdmin sobre la base `alimenta`. Los marcados con **ROLLBACK** no dejan datos guardados.

| Archivo | Qué prueba | ROLLBACK |
|---|---|:---:|
| `001_reservar_inventario.sql` | Prepara una solicitud para probar la reserva FEFO | No |
| `002_concurrencia.sql` | Dos sesiones intentan reservar el mismo saldo (instrucciones dentro del archivo) | No |
| `003_entrega_y_cancelacion.sql` | Prepara una solicitud para probar entrega y cancelación | No |
| `005_reportes.sql` | Reportes | — |
| `006_cerrar_lo_que_faltaba.sql` | Marcado de lotes vencidos | No |
| `007_pruebas_funciones_y_triggers.sql` | Funciones y triggers (casos positivos y negativos) | — |
| `011_pruebas_crear_solicitud.sql` | Creación de solicitudes (5 casos) | Sí |
| `012_pruebas_registrar_lote_donante.sql` | Registro de lotes por donantes, gestores y beneficiarios | Sí |
| `013_pruebas_tipos.sql` | Tipos de alimento y su vínculo con la categoría | Sí |
| `014_pruebas_solicitud_y_cancelacion.sql` | Crear y cancelar solicitudes | Sí |
| `015_pruebas_registrar_lote_tipo.sql` | Registro de lotes con tipo | Sí |
| `016_pruebas_administracion.sql` | Administración de catálogos, usuarios y roles | Sí |
| `017_pruebas_reserva_consentimiento.sql` | Reserva sin consentimiento rechazada | Sí |

`001_catalogos.sql` de esa carpeta carga los catálogos iniciales y **no se repite** después de la migración 013.

Los casos manuales de la interfaz están en la [matriz de trazabilidad](docs/matriz_trazabilidad.md).

## 7. Estructura del proyecto

```
app.py, auth.py, db.py      Aplicación Flask, control de roles y conexión
templates/, static/         Pantallas y estilos (html, css)
database/setup/             Creación de roles
database/migrations/        Estructura y objetos programables (numerados)
database/seeds/             Catálogos y datos de prueba
database/tests/             Pruebas SQL
database/queries/           Consultas de ejemplo
docs/                       Manuales, modelo ER, diccionario, matriz, capturas y evidencias
```

## 8. Seguridad

- Contraseñas guardadas con hash (no en texto plano).
- Consultas parametrizadas: no se concatenan datos del usuario en el SQL.
- La aplicación se conecta con un rol de mínimo privilegio (`alimenta_app`) y cambia datos mediante procedimientos que verifican el rol de quien los llama.
- Formularios protegidos contra CSRF; la identidad de quien opera sale siempre de la sesión.
- Reglas críticas (saldo no negativo, estados válidos, historial inmutable, consentimiento) las protege la base de datos, no solo la interfaz.
- Datos ficticios.

## 9. Problemas frecuentes

| Síntoma | Qué hacer |
|---|---|
| `Falta SECRET_KEY` al iniciar | Crea el `.env` desde `.env.example` y completa `SECRET_KEY` |
| `password authentication failed` | La contraseña de `.env` no es la del rol: repite `ALTER ROLE alimenta_app PASSWORD '…'` y corrige el `.env` |
| `relation … does not exist` | Falta ejecutar alguna migración: revisa el orden de la sección 2 |
| "ya existe" al ejecutar un archivo | Ya lo ejecutaste antes; no lo repitas |
| "No tienes permiso para hacer esta operación" | Revisa que se ejecutaron todas las migraciones, incluida la 017 |
| La lista de tipos sale vacía al solicitar | No hay inventario: registra lotes o ejecuta el seed 006 |

Más detalle en el [manual técnico](docs/manual_tecnico.md#93-problemas-frecuentes).
