# Modelo entidad-relación — Red Alimenta Medellín

Diagrama de la base de datos `alimenta` (PostgreSQL), actualizado con las migraciones 001 a 017.

**Novedades frente a la versión anterior:**

| Elemento nuevo | Para qué sirve |
|---|---|
| `punto_entrega` | Sitios donde se recoge el alimento. Lo elige el beneficiario al solicitar (`solicitud.id_punto`) y el gestor confirma el punto real al entregar (`entrega.id_punto`). |
| `usuario_donante` | Vincula cada usuario con rol *donante* con su organización, para que solo registre lotes en sus propias sedes. |
| `tipo_alimento` | Tipos específicos dentro de cada categoría (Bebidas → Agua, Gaseosa…). El lote y el detalle de la solicitud guardan el tipo. |
| Categorías separadas | "Carnes y pescados" se separó en **Carnes** y **Pescados**. |

## Diagrama

Para verlo: abrir este archivo en VS Code con la extensión *Markdown Preview Mermaid Support*, o pegar el bloque en <https://mermaid.live> y exportar la imagen (PNG o SVG) para el informe.

```mermaid
erDiagram
  rol ||--o{ usuario_rol : tiene
  usuario ||--o{ usuario_rol : tiene
  usuario ||--o| beneficiario : "perfil"
  usuario ||--o| usuario_donante : "pertenece a"
  donante ||--o{ usuario_donante : "agrupa usuarios"
  donante ||--o{ sede : tiene
  sede ||--o{ lote : recibe
  categoria ||--o{ tipo_alimento : agrupa
  categoria ||--o{ lote : clasifica
  tipo_alimento ||--o{ lote : especifica
  unidad ||--o{ lote : mide
  beneficiario ||--o{ solicitud : realiza
  punto_entrega ||--o{ solicitud : "elegido en"
  solicitud ||--|{ solicitud_detalle : contiene
  categoria ||--o{ solicitud_detalle : pide
  tipo_alimento ||--o{ solicitud_detalle : pide
  unidad ||--o{ solicitud_detalle : mide
  solicitud ||--o{ reserva : genera
  reserva ||--|{ reserva_detalle : asigna
  lote ||--o{ reserva_detalle : aporta
  reserva ||--o| entrega : cierra
  usuario ||--o{ entrega : "confirma (gestor)"
  punto_entrega ||--o{ entrega : "se entrega en"
  lote ||--o{ movimiento_inventario : registra
  reserva ||--o{ movimiento_inventario : origina
  usuario ||--o{ movimiento_inventario : responsable
  usuario ||--o{ auditoria : actor

  rol {
    smallint id_rol PK
    varchar nombre
  }
  usuario {
    int id_usuario PK
    varchar nombre
    varchar correo
    text password_hash
    boolean activo
    timestamptz creado_en
  }
  usuario_rol {
    int id_usuario PK, FK
    smallint id_rol PK, FK
  }
  usuario_donante {
    int id_usuario PK, FK
    int id_donante FK
  }
  donante {
    int id_donante PK
    varchar nombre
    varchar nit
    varchar tipo
    boolean activo
  }
  sede {
    int id_sede PK
    int id_donante FK
    varchar nombre
    varchar direccion
    varchar barrio
  }
  categoria {
    smallint id_categoria PK
    varchar nombre
  }
  tipo_alimento {
    int id_tipo PK
    smallint id_categoria FK
    varchar nombre
    boolean activo
  }
  unidad {
    smallint id_unidad PK
    varchar nombre
    varchar abreviatura
  }
  punto_entrega {
    int id_punto PK
    varchar nombre
    varchar direccion
    varchar comuna
    boolean activo
  }
  beneficiario {
    int id_beneficiario PK
    int id_usuario FK
    varchar documento
    varchar programa
    varchar comuna
    varchar estado
    boolean consentimiento
    timestamptz fecha_consentimiento
  }
  lote {
    int id_lote PK
    int id_sede FK
    smallint id_categoria FK
    int id_tipo FK
    smallint id_unidad FK
    varchar descripcion
    numeric cantidad_inicial
    numeric saldo
    date fecha_recepcion
    date fecha_vencimiento
    varchar estado
  }
  solicitud {
    int id_solicitud PK
    int id_beneficiario FK
    int id_punto FK
    timestamptz fecha_solicitud
    varchar estado
    varchar observacion
  }
  solicitud_detalle {
    int id_detalle PK
    int id_solicitud FK
    smallint id_categoria FK
    int id_tipo FK
    smallint id_unidad FK
    numeric cantidad_solicitada
  }
  reserva {
    int id_reserva PK
    int id_solicitud FK
    timestamptz fecha_reserva
    varchar estado
  }
  reserva_detalle {
    int id_reserva_detalle PK
    int id_reserva FK
    int id_lote FK
    numeric cantidad
  }
  entrega {
    int id_entrega PK
    int id_reserva FK
    int id_usuario_gestor FK
    int id_punto FK
    timestamptz fecha_entrega
    varchar observacion
  }
  movimiento_inventario {
    bigint id_movimiento PK
    int id_lote FK
    int id_reserva FK
    int id_usuario FK
    varchar tipo
    numeric cantidad
    varchar motivo
    timestamptz fecha
  }
  auditoria {
    bigint id_auditoria PK
    varchar tabla
    varchar operacion
    varchar id_registro
    jsonb datos_anteriores
    jsonb datos_nuevos
    int id_usuario FK
    timestamptz fecha
  }
```

## Cómo leerlo

- **Personas y roles:** `usuario` se relaciona con `rol` por medio de `usuario_rol` (un usuario puede tener varios roles). Un usuario con perfil de beneficiario tiene una fila en `beneficiario`; uno con rol *donante* tiene una fila en `usuario_donante`.
- **Donantes e inventario:** `donante` → `sede` → `lote`. Cada lote tiene categoría, tipo y unidad. La pareja (tipo, categoría) está protegida por una llave foránea compuesta: no se puede guardar "Agua" dentro de "Lácteos".
- **Solicitar y recoger:** `beneficiario` → `solicitud` (con el `punto_entrega` elegido) → `solicitud_detalle` (tipo y cantidad pedidos). Al reservar nace una `reserva` con su `reserva_detalle`, que dice de qué lotes sale el alimento (el que vence primero sale primero). Al entregar se crea la `entrega`, que registra gestor y punto.
- **Trazabilidad:** cada entrada, reserva, liberación, salida y vencimiento queda en `movimiento_inventario`. Los cambios sensibles quedan en `auditoria`. Ambas tablas son de solo agregar: no se pueden modificar ni borrar.
- **Relaciones opcionales (`o|` y `o{`):** `solicitud.id_punto` es opcional en la base de datos porque existen solicitudes anteriores a la 013; la aplicación lo exige en toda solicitud nueva.
