# Matriz de trazabilidad — Red Alimenta Medellín

Conecta cada **requerimiento** con lo que lo cumple: las tablas, los objetos de base de datos, la pantalla de la aplicación y la prueba que lo comprueba.

**Cómo usarla:** se lee de izquierda a derecha. Si un profesor pregunta "¿dónde se cumple esto?", la fila indica en qué tabla, procedimiento, pantalla y prueba buscar.

- **RF** = requerimiento funcional (lo que el sistema hace). **RNF** = requerimiento no funcional (cómo lo hace: seguridad, integridad, protección de datos).
- Las pruebas SQL están en `database/tests/`. Los casos manuales (M-01 a M-14) están en la sección 3.
- Los códigos RF y RNF de este documento son una numeración propia del proyecto. La regla **RN-10** (historial protegido) conserva el código que ya tenía la migración 010.

## 1. Requerimientos funcionales

### Acceso y roles

| ID | Requerimiento | Rol | Tablas | Objetos de base de datos | Ruta y pantalla | Prueba |
|---|---|---|---|---|---|---|
| RF-01 | Iniciar y cerrar sesión con correo y contraseña protegida con hash | Todos | usuario | — | `/entrar`, `/salir` · `entrar.html` | M-01 |
| RF-02 | Cada persona accede solo a lo que su rol permite (donante, gestor, beneficiario, administrador) | Todos | rol, usuario_rol | Roles de base de datos `alimenta_app` y `alimenta_lectura` (009) | Menú en `base.html`; decorador `rol_requerido` en `auth.py`; página de error 403 · `error.html` | M-02 |
| RF-03 | Tablero de inicio distinto para cada rol | Todos | solicitud, reserva, entrega, lote, usuario, donante, beneficiario, punto_entrega | `v_alertas_vencimiento` | `/` · `inicio.html` | M-03 |

### Inventario

| ID | Requerimiento | Rol | Tablas | Objetos de base de datos | Ruta y pantalla | Prueba |
|---|---|---|---|---|---|---|
| RF-04 | Registrar un lote de alimento con categoría y tipo, y dejar su movimiento de entrada | Donante, gestor, administrador | lote, tipo_alimento, categoria, unidad, movimiento_inventario | `registrar_lote` (015) | `/lotes`, `/lotes/nuevo` · `lotes.html` | `015_pruebas_registrar_lote_tipo.sql`, `012_pruebas_registrar_lote_donante.sql`, `013_pruebas_tipos.sql`, M-04 |
| RF-05 | Un donante solo registra lotes en las sedes de su propia organización | Donante | usuario_donante, sede, donante | `registrar_lote` | `/lotes/nuevo` | `012_pruebas_registrar_lote_donante.sql` |
| RF-06 | Consultar el inventario disponible (activo, con saldo y no vencido) | Todos | lote, sede, donante, categoria, unidad | `v_inventario_disponible` | `/inventario` · `inventario.html` | M-05 |
| RF-07 | Ver alertas de vencimiento (3 días) y marcar como vencidos los lotes caducados, registrando la pérdida | Gestor, administrador | lote, movimiento_inventario | `v_alertas_vencimiento`, `marcar_lotes_vencidos` | `/alertas`, `/alertas/marcar-vencidos` · `alertas.html` | `006_cerrar_lo_que_faltaba.sql`, M-11 |

### Solicitudes, reservas y entregas

| ID | Requerimiento | Rol | Tablas | Objetos de base de datos | Ruta y pantalla | Prueba |
|---|---|---|---|---|---|---|
| RF-08 | Solicitar alimento eligiendo categoría, luego un tipo específico, la cantidad y el punto de entrega donde recogerá | Beneficiario | solicitud, solicitud_detalle, tipo_alimento, punto_entrega | `crear_solicitud` (014) | `/solicitudes`, `/solicitudes/nueva` · `solicitudes_beneficiario.html` | `011_pruebas_crear_solicitud.sql`, `014_pruebas_solicitud_y_cancelacion.sql`, M-06 |
| RF-09 | El beneficiario cancela su propia solicitud (pendiente o reservada); si estaba reservada, el inventario vuelve a los lotes | Beneficiario | solicitud, reserva, reserva_detalle, lote, movimiento_inventario | `cancelar_solicitud` (014) | `/solicitudes/<id>/cancelar` · `solicitudes_beneficiario.html` | `014_pruebas_solicitud_y_cancelacion.sql`, M-07 |
| RF-10 | Reservar inventario para una solicitud, tomando primero los lotes que vencen antes (FEFO) y del tipo pedido | Gestor, administrador | reserva, reserva_detalle, lote, movimiento_inventario | `reservar_inventario` (017), `validar_lote_en_reserva`, `idx_lote_fefo`, `idx_lote_tipo_vence` | `/solicitudes/<id>/reservar` · `solicitudes_gestion.html` | `001_reservar_inventario.sql`, `002_concurrencia.sql`, M-08 |
| RF-11 | Solo un beneficiario activo y con consentimiento de datos puede solicitar y recibir reservas | Beneficiario, gestor | beneficiario | `crear_solicitud`, `reservar_inventario` | `/solicitudes/nueva`, `/solicitudes/<id>/reservar` | `011_pruebas_crear_solicitud.sql`, `017_pruebas_reserva_consentimiento.sql` |
| RF-12 | Confirmar la entrega en un punto de entrega (ya marcado el que eligió el beneficiario), registrando la salida de inventario | Gestor, administrador | entrega, punto_entrega, reserva, solicitud, movimiento_inventario | `confirmar_entrega` | `/reservas/<id>/entregar` · `reservas.html` | `003_entrega_y_cancelacion.sql`, M-09 |
| RF-13 | El gestor cancela una reserva activa con un motivo; el inventario vuelve a los lotes | Gestor, administrador | reserva, reserva_detalle, lote, movimiento_inventario | `cancelar_reserva`, `trg_validar_estado_reserva` | `/reservas/<id>/cancelar` · `reservas.html` | `003_entrega_y_cancelacion.sql`, `007_pruebas_funciones_y_triggers.sql` |
| RF-14 | Ver el detalle de lo que pidió el beneficiario, los lotes asignados y la entrega, en un desplegable | Gestor, administrador | solicitud_detalle, tipo_alimento, reserva_detalle, lote, entrega | Consultas del módulo `con_detalle` en `app.py` | `/entregas`, `/reservas` · `entregas.html`, `reservas.html`, `_detalle.html` | M-10 |

### Administración

| ID | Requerimiento | Rol | Tablas | Objetos de base de datos | Ruta y pantalla | Prueba |
|---|---|---|---|---|---|---|
| RF-15 | Administrar catálogos: categorías, tipos de alimento, unidades y puntos de entrega | Administrador | categoria, tipo_alimento, unidad, punto_entrega | `admin_guardar_categoria`, `admin_guardar_tipo`, `admin_guardar_unidad`, `admin_guardar_punto`, `verificar_admin` (016) | `/admin/catalogos` · `admin_catalogos.html` | `016_pruebas_administracion.sql`, M-12 |
| RF-16 | Administrar usuarios y roles: crear, activar o desactivar, asignar y quitar roles | Administrador | usuario, usuario_rol, usuario_donante, donante | `admin_crear_usuario`, `admin_estado_usuario`, `admin_asignar_rol`, `admin_quitar_rol` (016) | `/admin/usuarios` · `admin_usuarios.html` | `016_pruebas_administracion.sql`, M-13 |

### Trazabilidad, reportes y auditoría

| ID | Requerimiento | Rol | Tablas | Objetos de base de datos | Ruta y pantalla | Prueba |
|---|---|---|---|---|---|---|
| RF-17 | Reconstruir el recorrido completo de un lote y su saldo en cualquier fecha | Gestor, administrador | movimiento_inventario, lote | `trazabilidad_lote`, `saldo_lote_a_fecha`, `v_historial_movimientos` | Consulta SQL (sin pantalla) | `007_pruebas_funciones_y_triggers.sql` |
| RF-18 | Reportes e indicadores: inventario por sede y categoría, balance mensual, aprovechamiento, beneficiarios por comuna y ranking de donantes | Administrador, rol de lectura | movimiento_inventario, lote, entrega, beneficiario, donante | `v_indicador_mensual`, `v_reporte_inventario_sede_categoria`, `v_reporte_balance_mensual`, `v_reporte_aprovechamiento`, `v_reporte_beneficiarios_comuna`, `v_reporte_donantes`, `tasa_aprovechamiento` | Consulta SQL (sin pantalla) | `005_reportes.sql`, `007_pruebas_funciones_y_triggers.sql` |
| RF-19 | Auditar quién cambió qué en estados, entregas, roles y catálogos | Administrador | auditoria | `auditar_cambio`, `trg_auditoria_*`, `ver_auditoria` | Consulta SQL (sin pantalla) | `007_pruebas_funciones_y_triggers.sql`, `016_pruebas_administracion.sql` |

## 2. Requerimientos no funcionales

| ID | Requerimiento | Cómo se cumple | Dónde | Prueba |
|---|---|---|---|---|
| RNF-01 (RN-10) | El historial no se borra ni se altera | Triggers que lanzan error al borrar filas de las tablas del flujo y al modificar o borrar `movimiento_inventario` y `auditoria` | `trg_no_borrar`, `trg_solo_agregar` (010) | M-14 |
| RNF-02 | Integridad y concurrencia: no se vende dos veces el mismo inventario | Bloqueo de filas al reservar (`FOR UPDATE`), restricciones CHECK en `lote`, llaves compuestas tipo/categoría | `reservar_inventario`, `lote`, `fk_lote_tipo`, `fk_detalle_tipo` | `002_concurrencia.sql`, `013_pruebas_tipos.sql` |
| RNF-03 | Mínimo privilegio: la aplicación solo hace lo que necesita | Todo cambio pasa por procedimientos `SECURITY DEFINER` que verifican el rol; el grupo `PUBLIC` no tiene permisos | `009_roles_y_permisos.sql`, `verificar_admin` | `016_pruebas_administracion.sql` (rechazo de no administradores) |
| RNF-04 | Protección de datos personales | Contraseñas con hash; consentimiento obligatorio; reportes agregados sin datos personales; comunas con menos de 3 beneficiarios no se publican; auditoría solo para administradores | `usuario.password_hash`, `beneficiario.consentimiento`, `v_reporte_beneficiarios_comuna`, `ver_auditoria` | `017_pruebas_reserva_consentimiento.sql` |
| RNF-05 | Protección de los formularios y la sesión | Token CSRF en todos los formularios que envían datos; la identidad de quien opera sale siempre de la sesión y nunca del formulario | `token_csrf` y `revisar_csrf` en `app.py` | Inspección de código |
| RNF-06 | Uso en pantallas de distintos tamaños | Diseño adaptable; las tablas se reorganizan en pantallas pequeñas | `static/css/estilo.css` | M-03 (ver en celular) |

## 3. Casos de prueba manuales (interfaz)

Usuarios de demostración: contraseña `Demo2026!`. Rol de cada uno: `admin@alimenta.test`, `gestor1@alimenta.test`, `donante2@alimenta.test`, `beneficiario1@alimenta.test`.

| ID | Requerimiento | Pasos | Resultado esperado |
|---|---|---|---|
| M-01 | RF-01 | Entrar con una contraseña incorrecta; luego con la correcta; luego pulsar **Salir** | Primero aparece "Correo o contraseña incorrectos"; luego entra al inicio; al salir vuelve a la pantalla de ingreso |
| M-02 | RF-02 | Entrar como beneficiario y escribir en la barra `/admin/usuarios` | Aparece un error 403 (sin permiso). El menú del beneficiario no muestra Registrar lote, Alertas, Reservas, Entregas, Catálogos ni Usuarios |
| M-03 | RF-03, RNF-06 | Entrar con cada uno de los cuatro usuarios | Cada uno ve bloques distintos: beneficiario "Mis solicitudes"; donante "Mis donaciones"; gestor "Gestión"; administrador "Gestión" y "Administración". Repetir en el celular |
| M-04 | RF-04 | Como donante, **Registrar lote**: categoría Bebidas, tipo Agua, 5 litros, vence en 7 días | Aparece en "Lotes recientes" como "Bebidas · Agua" |
| M-05 | RF-06 | Entrar a **Inventario** | El lote de M-04 aparece con sus días para vencer |
| M-06 | RF-08 | Como beneficiario, **Solicitudes**: categoría Bebidas, tipo Agua, 2 litros, un punto de entrega | Mensaje "Solicitud creada"; aparece en el historial como pendiente, con su punto |
| M-07 | RF-09 | Crear una solicitud, pulsar **Cancelar** y confirmar. Repetirlo con una solicitud ya reservada | Pasa a cancelada. En el segundo caso, el saldo del lote vuelve a subir en **Inventario** |
| M-08 | RF-10 | Como gestor, **Solicitudes**, pulsar **Reservar** en la solicitud de M-06 | La solicitud pasa a reservada y el saldo del lote baja en 2 litros |
| M-09 | RF-12 | Como gestor, **Reservas**: la lista de punto de entrega sale ya marcada con el que eligió el beneficiario; confirmar la entrega | La solicitud pasa a entregada y la entrega aparece en **Entregas** |
| M-10 | RF-14 | En **Reservas** pulsar "Ver lo que pidió"; en **Entregas** pulsar "Ver detalle" | Muestra beneficiario, punto elegido, tipo y cantidad pedidos, lotes asignados y, en Entregas, el gestor y el punto de la entrega |
| M-11 | RF-07 | En **Alertas**, revisar los lotes que vencen pronto; si hay vencidos, pulsar **Registrar pérdida de N lotes** | Los lotes caducados pasan a vencidos, su saldo queda en cero y se registra la pérdida |
| M-12 | RF-15 | Como administrador, **Catálogos**: agregar el tipo "Té" en Bebidas; luego desactivarlo | Aparece en el formulario de lotes mientras esté activo y desaparece al desactivarlo |
| M-13 | RF-16 | Como administrador, **Usuarios**: crear un gestor, desactivarlo y volverlo a activar; intentar desactivar tu propio usuario | El gestor se crea y cambia de estado; al desactivarte a ti mismo aparece "No puedes desactivar tu propio usuario" |
| M-14 | RNF-01 | En pgAdmin ejecutar `BEGIN; DELETE FROM lote; ROLLBACK;` | Error: "No se permite borrar registros de lote: use estados o anulación trazable". No se pierde ningún dato |

## 4. Cobertura de las pruebas SQL

| Archivo en `database/tests/` | Qué comprueba | Cómo se ejecuta |
|---|---|---|
| `001_catalogos.sql` | Carga los catálogos iniciales (roles, categorías y unidades). Es de la instalación inicial: **no repetirlo después de la migración 013**, porque volvería a crear "Carnes y pescados" | Solo en una instalación nueva, antes de la 013 |
| `001_reservar_inventario.sql` | Crea una solicitud de prueba para reservar con FEFO | Ejecutar; luego `CALL reservar_inventario(<id>, <gestor>, NULL)` |
| `002_concurrencia.sql` | Dos reservas simultáneas sobre un mismo lote: la segunda debe fallar | Con dos sesiones de pgAdmin, siguiendo los comentarios del archivo |
| `003_entrega_y_cancelacion.sql` | Prepara una solicitud para probar entrega y cancelación de reserva | Ejecutar y seguir con `confirmar_entrega` o `cancelar_reserva` |
| `005_reportes.sql` | Reporte de inventario por sede y categoría | Ejecutar y revisar |
| `006_cerrar_lo_que_faltaba.sql` | Lote vencido de prueba y `marcar_lotes_vencidos` | Ejecutar y revisar |
| `007_pruebas_funciones_y_triggers.sql` | Funciones de saldo y aprovechamiento, estados de reserva, auditoría | Ejecutar y revisar la tabla de resultados |
| `011_pruebas_crear_solicitud.sql` | `crear_solicitud`: caso válido, cantidad cero, usuario no beneficiario, tipo falso, sin punto | Ejecutar; no deja datos |
| `012_pruebas_registrar_lote_donante.sql` | `registrar_lote` con donante, gestor y beneficiario; sede ajena, cantidad cero y fecha pasada | Ejecutar; no deja datos |
| `013_pruebas_tipos.sql` | Carnes y Pescados separadas, tipo "Otro", combinación tipo/categoría inválida | Ejecutar y leer **Messages**; no deja datos |
| `014_pruebas_solicitud_y_cancelacion.sql` | Crear y cancelar solicitud; rechazo de un usuario ajeno | Ejecutar y leer **Messages**; no deja datos |
| `015_pruebas_registrar_lote_tipo.sql` | `registrar_lote` con tipo; tipo inexistente | Ejecutar y leer **Messages**; no deja datos |
| `016_pruebas_administracion.sql` | Procedimientos de administración y sus protecciones | Ejecutar y leer **Messages**; no deja datos |
| `017_pruebas_reserva_consentimiento.sql` | No se reserva para quien no dio su consentimiento | Ejecutar y leer **Messages**; no deja datos |

**Limitaciones conocidas:** los reportes (RF-17, RF-18) y la auditoría (RF-19) se consultan con SQL; la aplicación web no tiene pantallas para ellos. Las pruebas de interfaz (sección 3) son manuales.
