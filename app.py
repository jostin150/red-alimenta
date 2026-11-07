"""Punto de entrada de la aplicación Red Alimenta Medellín."""
import os
import secrets
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path

from dotenv import load_dotenv
from flask import (Flask, abort, flash, redirect, render_template, request,
                   session, url_for)
from werkzeug.security import check_password_hash, generate_password_hash

from auth import login_requerido, rol_requerido
from db import ErrorDeNegocio, consultar, ejecutar

load_dotenv(Path(__file__).resolve().parent / ".env", override=True)

ROLES_GESTION = ("gestor", "administrador")
ROLES_DONACION = ("donante", "gestor", "administrador")

app = Flask(__name__)

# La llave secreta firma la sesión. Si alguien la conoce, puede fabricar
# sesiones falsas, así que NO se deja una por defecto: va en el archivo .env.
app.secret_key = os.getenv("SECRET_KEY")
if not app.secret_key:
    raise RuntimeError(
        "Falta SECRET_KEY en el archivo .env. Genera una con: "
        'python -c "import secrets; print(secrets.token_hex(32))"'
    )

app.config.update(
    SESSION_COOKIE_HTTPONLY=True,   # JavaScript no puede leer la cookie
    SESSION_COOKIE_SAMESITE="Lax",  # no se envía desde otros sitios
)


# ---------------------------------------------------------------------------
# Protección contra formularios falsos (CSRF)
# Cada formulario lleva un código secreto que solo conoce esta sesión.
# Si una página ajena intenta enviar un formulario por ti, no tendrá el código.
# ---------------------------------------------------------------------------
def token_csrf():
    if "csrf" not in session:
        session["csrf"] = secrets.token_hex(16)
    return session["csrf"]


app.jinja_env.globals["token_csrf"] = token_csrf


@app.before_request
def revisar_csrf():
    if request.method == "POST":
        enviado = request.form.get("csrf", "").encode()
        esperado = session.get("csrf", "").encode()
        if not esperado or not secrets.compare_digest(enviado, esperado):
            abort(400)


def es_gestion():
    return bool(set(session.get("roles", [])) & set(ROLES_GESTION))


def agrupar(filas, clave):
    """Agrupa una lista de filas en un diccionario {valor_de_clave: [filas]}."""
    grupos = {}
    for f in filas:
        grupos.setdefault(f[clave], []).append(f)
    return grupos


def con_detalle(filas):
    """A cada fila (reserva o entrega) le agrega lo que pidió el beneficiario
    (`pedido`) y los lotes asignados (`lotes_detalle`), para el "Ver detalle"."""
    if not filas:
        return filas
    pedido = agrupar(consultar(
        """
        SELECT sd.id_solicitud, t.nombre AS tipo, c.nombre AS categoria,
               sd.cantidad_solicitada AS cantidad, u.abreviatura
        FROM solicitud_detalle sd
        JOIN tipo_alimento t ON t.id_tipo = sd.id_tipo
        JOIN categoria c     ON c.id_categoria = sd.id_categoria
        JOIN unidad u        ON u.id_unidad = sd.id_unidad
        WHERE sd.id_solicitud = ANY(%s)
        ORDER BY t.nombre
        """,
        ([f["id_solicitud"] for f in filas],),
    ), "id_solicitud")
    lotes = agrupar(consultar(
        """
        SELECT rd.id_reserva, l.id_lote, l.descripcion, rd.cantidad,
               un.abreviatura, l.fecha_vencimiento,
               d.nombre AS donante, s.nombre AS sede
        FROM reserva_detalle rd
        JOIN lote l    ON l.id_lote = rd.id_lote
        JOIN sede s    ON s.id_sede = l.id_sede
        JOIN donante d ON d.id_donante = s.id_donante
        JOIN unidad un ON un.id_unidad = l.id_unidad
        WHERE rd.id_reserva = ANY(%s)
        ORDER BY l.fecha_vencimiento, l.id_lote
        """,
        ([f["id_reserva"] for f in filas],),
    ), "id_reserva")
    for f in filas:
        f["pedido"] = pedido.get(f["id_solicitud"], [])
        f["lotes_detalle"] = lotes.get(f["id_reserva"], [])
    return filas


# ---------------------------------------------------------------------------
# Inicio e inventario
# ---------------------------------------------------------------------------
def contar(sql, params=None):
    """Ejecuta un SELECT que devuelve un solo número (un conteo o una suma)."""
    fila = consultar(sql, params)[0]
    return list(fila.values())[0] or 0


@app.route("/")
@login_requerido
def inicio():
    """Tablero de inicio: muestra un bloque por cada rol que tenga la persona."""
    roles = session.get("roles", [])
    uid = session["id_usuario"]
    tableros = []

    # --- Gestión (gestor y administrador) -------------------------------
    if es_gestion():
        vencidos = contar(
            """SELECT count(*) FROM lote
               WHERE fecha_vencimiento < CURRENT_DATE AND saldo > 0
                 AND estado IN ('activo', 'vencido')""")
        tableros.append({
            "titulo": "Gestión",
            "texto": "Lo que necesita atención hoy.",
            "tarjetas": [
                {"etiqueta": "Solicitudes pendientes", "enlace": "solicitudes",
                 "valor": contar("SELECT count(*) FROM solicitud WHERE estado = 'pendiente'"),
                 "urgente": False},
                {"etiqueta": "Reservas por entregar", "enlace": "reservas",
                 "valor": contar("SELECT count(*) FROM reserva WHERE estado = 'activa'"),
                 "urgente": False},
                {"etiqueta": "Lotes por vencer (3 días)", "enlace": "alertas",
                 "valor": contar("SELECT count(*) FROM v_alertas_vencimiento"),
                 "urgente": False},
                {"etiqueta": "Vencidos sin registrar", "enlace": "alertas",
                 "valor": vencidos, "urgente": vencidos > 0},
                {"etiqueta": "Entregas este mes", "enlace": "entregas",
                 "valor": contar("""SELECT count(*) FROM entrega
                                    WHERE fecha_entrega >= date_trunc('month', now())"""),
                 "urgente": False},
            ],
        })

    # --- Administración (solo administrador) -----------------------------
    if "administrador" in roles:
        tableros.append({
            "titulo": "Administración",
            "texto": "Resumen general de la red.",
            "tarjetas": [
                {"etiqueta": "Usuarios activos", "enlace": "admin_usuarios", "urgente": False,
                 "valor": contar("SELECT count(*) FROM usuario WHERE activo")},
                {"etiqueta": "Beneficiarios activos", "enlace": None, "urgente": False,
                 "valor": contar("SELECT count(*) FROM beneficiario WHERE estado = 'activo'")},
                {"etiqueta": "Donantes activos", "enlace": None, "urgente": False,
                 "valor": contar("SELECT count(*) FROM donante WHERE activo")},
                {"etiqueta": "Puntos de entrega", "enlace": "admin_catalogos", "urgente": False,
                 "valor": contar("SELECT count(*) FROM punto_entrega WHERE activo")},
                {"etiqueta": "Lotes con inventario", "enlace": "inventario", "urgente": False,
                 "valor": contar("""SELECT count(*) FROM lote
                                    WHERE estado = 'activo' AND saldo > 0""")},
            ],
        })

    # --- Donante ----------------------------------------------------------
    if "donante" in roles:
        propios = """FROM lote l
                     JOIN sede s ON s.id_sede = l.id_sede
                     WHERE s.id_donante IN (
                       SELECT id_donante FROM usuario_donante WHERE id_usuario = %s)"""
        tableros.append({
            "titulo": "Mis donaciones",
            "texto": "Lo que ha donado tu organización.",
            "tarjetas": [
                {"etiqueta": "Lotes registrados", "enlace": "lotes", "urgente": False,
                 "valor": contar("SELECT count(*) " + propios, (uid,))},
                {"etiqueta": "Lotes con inventario", "enlace": "lotes", "urgente": False,
                 "valor": contar("SELECT count(*) " + propios +
                                 " AND l.estado = 'activo' AND l.saldo > 0", (uid,))},
                {"etiqueta": "Por vencer (3 días)", "enlace": "lotes", "urgente": False,
                 "valor": contar("SELECT count(*) " + propios +
                                 """ AND l.estado = 'activo' AND l.saldo > 0
                                     AND l.fecha_vencimiento BETWEEN CURRENT_DATE
                                         AND CURRENT_DATE + 3""", (uid,))},
            ],
        })

    # --- Beneficiario -----------------------------------------------------
    listas_para_recoger = []
    if "beneficiario" in roles:
        por_estado = {f["estado"]: f["n"] for f in consultar(
            """SELECT s.estado, count(*) AS n
               FROM solicitud s
               JOIN beneficiario b ON b.id_beneficiario = s.id_beneficiario
               WHERE b.id_usuario = %s
               GROUP BY s.estado""", (uid,))}
        tableros.append({
            "titulo": "Mis solicitudes",
            "texto": "Cómo van tus pedidos de alimento.",
            "tarjetas": [
                {"etiqueta": "Pendientes", "enlace": "solicitudes", "urgente": False,
                 "valor": por_estado.get("pendiente", 0)},
                {"etiqueta": "Listas para recoger", "enlace": "solicitudes", "urgente": False,
                 "valor": por_estado.get("reservada", 0)},
                {"etiqueta": "Entregadas", "enlace": "solicitudes", "urgente": False,
                 "valor": por_estado.get("entregada", 0)},
                {"etiqueta": "Canceladas", "enlace": "solicitudes", "urgente": False,
                 "valor": por_estado.get("cancelada", 0)},
            ],
        })
        listas_para_recoger = consultar(
            """SELECT s.id_solicitud, p.nombre AS punto, p.direccion
               FROM solicitud s
               JOIN beneficiario b ON b.id_beneficiario = s.id_beneficiario
               LEFT JOIN punto_entrega p ON p.id_punto = s.id_punto
               WHERE b.id_usuario = %s AND s.estado = 'reservada'
               ORDER BY s.fecha_solicitud""", (uid,))

    return render_template("inicio.html", tableros=tableros,
                           listas_para_recoger=listas_para_recoger)


@app.route("/inventario")
@login_requerido
def inventario():
    # Usamos la vista que ya creaste en la base de datos
    filas = consultar("SELECT * FROM v_inventario_disponible ORDER BY fecha_vencimiento")
    columnas = list(filas[0].keys()) if filas else []
    return render_template("inventario.html", filas=filas, columnas=columnas)


# ---------------------------------------------------------------------------
# Ingreso y salida
# ---------------------------------------------------------------------------
@app.route("/entrar", methods=["GET", "POST"])
def entrar():
    if request.method == "POST":
        correo = request.form.get("correo", "").strip().lower()
        clave = request.form.get("clave", "")

        filas = consultar(
            """
            SELECT u.id_usuario, u.nombre, u.password_hash, u.activo,
                   array_remove(array_agg(r.nombre), NULL) AS roles
            FROM usuario u
            LEFT JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
            LEFT JOIN rol r          ON r.id_rol = ur.id_rol
            WHERE u.correo = %s
            GROUP BY u.id_usuario
            """,
            (correo,),
        )
        usuario = filas[0] if filas else None

        if (usuario and usuario["activo"]
                and check_password_hash(usuario["password_hash"], clave)):
            session.clear()
            session["id_usuario"] = usuario["id_usuario"]
            session["nombre"] = usuario["nombre"]
            session["roles"] = list(usuario["roles"])
            return redirect(url_for("inicio"))

        # El mismo mensaje si falla el correo o la clave, para no dar pistas.
        flash("Correo o contraseña incorrectos.", "error")

    return render_template("entrar.html")


@app.route("/salir", methods=["POST"])
def salir():
    session.clear()
    return redirect(url_for("entrar"))


# ---------------------------------------------------------------------------
# Solicitudes
#   - El beneficiario ve las suyas y crea nuevas.
#   - El gestor ve las pendientes y reserva inventario (FEFO) para ellas.
# ---------------------------------------------------------------------------
@app.route("/solicitudes")
@login_requerido
def solicitudes():
    if es_gestion():
        pendientes = consultar(
            """
            SELECT s.id_solicitud, s.fecha_solicitud, us.nombre AS beneficiario,
                   p.nombre AS punto,
                   string_agg(t.nombre || ' (' || c.nombre || ') · ' ||
                              replace(round(sd.cantidad_solicitada, 2)::text, '.', ',') ||
                              ' ' || u.abreviatura, '; ' ORDER BY t.nombre) AS pedido
            FROM solicitud s
            JOIN beneficiario b       ON b.id_beneficiario = s.id_beneficiario
            JOIN usuario us           ON us.id_usuario = b.id_usuario
            JOIN solicitud_detalle sd ON sd.id_solicitud = s.id_solicitud
            JOIN tipo_alimento t      ON t.id_tipo = sd.id_tipo
            JOIN categoria c          ON c.id_categoria = sd.id_categoria
            JOIN unidad u             ON u.id_unidad = sd.id_unidad
            LEFT JOIN punto_entrega p ON p.id_punto = s.id_punto
            WHERE s.estado = 'pendiente'
            GROUP BY s.id_solicitud, s.fecha_solicitud, us.nombre, p.nombre
            ORDER BY s.fecha_solicitud
            """
        )
        return render_template("solicitudes_gestion.html", pendientes=pendientes)

    if "beneficiario" not in session.get("roles", []):
        abort(403)

    uid = session["id_usuario"]
    propias = consultar(
        """
        SELECT s.id_solicitud, s.fecha_solicitud, s.estado,
               p.nombre AS punto,
               string_agg(t.nombre || ' (' || c.nombre || ') · ' ||
                          replace(round(sd.cantidad_solicitada, 2)::text, '.', ',') ||
                          ' ' || u.abreviatura, '; ' ORDER BY t.nombre) AS pedido
        FROM solicitud s
        JOIN beneficiario b       ON b.id_beneficiario = s.id_beneficiario
        JOIN solicitud_detalle sd ON sd.id_solicitud = s.id_solicitud
        JOIN tipo_alimento t      ON t.id_tipo = sd.id_tipo
        JOIN categoria c          ON c.id_categoria = sd.id_categoria
        JOIN unidad u             ON u.id_unidad = sd.id_unidad
        LEFT JOIN punto_entrega p ON p.id_punto = s.id_punto
        WHERE b.id_usuario = %s
        GROUP BY s.id_solicitud, s.fecha_solicitud, s.estado, p.nombre
        ORDER BY s.fecha_solicitud DESC
        LIMIT 20
        """,
        (uid,),   # siempre de la sesión
    )

    # Solo ofrecemos lo que hoy tiene inventario: categoría + tipo + unidad
    filas = consultar(
        """
        SELECT c.id_categoria, c.nombre AS categoria,
               t.id_tipo, t.nombre AS tipo,
               u.id_unidad, u.nombre AS unidad, u.abreviatura,
               sum(l.saldo) AS disponible
        FROM lote l
        JOIN tipo_alimento t ON t.id_tipo = l.id_tipo
        JOIN categoria c     ON c.id_categoria = l.id_categoria
        JOIN unidad u        ON u.id_unidad = l.id_unidad
        WHERE l.estado = 'activo' AND l.saldo > 0
          AND l.fecha_vencimiento >= CURRENT_DATE
          AND t.activo
        GROUP BY c.id_categoria, c.nombre, t.id_tipo, t.nombre,
                 u.id_unidad, u.nombre, u.abreviatura
        ORDER BY c.nombre, t.nombre, u.nombre
        """
    )
    # Las categorías para la primera lista (sin repetir)
    categorias, vistas = [], set()
    for f in filas:
        if f["id_categoria"] not in vistas:
            vistas.add(f["id_categoria"])
            categorias.append({"id": f["id_categoria"], "nombre": f["categoria"]})
    # Los tipos para la segunda lista; el navegador los filtra según la categoría
    opciones_js = [
        {
            "id_categoria": f["id_categoria"],
            "valor": f"{f['id_tipo']}-{f['id_unidad']}",
            "etiqueta": (f"{f['tipo']} · {f['unidad']} "
                         f"({f['disponible']:.2f}".replace(".", ",")
                         + f" {f['abreviatura']} disponibles)"),
        }
        for f in filas
    ]

    # Puntos de entrega; dejamos marcado el de la comuna del beneficiario
    puntos = consultar(
        "SELECT id_punto, nombre, direccion, comuna FROM punto_entrega "
        "WHERE activo ORDER BY comuna, nombre"
    )
    ben = consultar("SELECT comuna FROM beneficiario WHERE id_usuario = %s", (uid,))
    comuna = ben[0]["comuna"] if ben else None

    return render_template("solicitudes_beneficiario.html", propias=propias,
                           categorias=categorias, opciones_js=opciones_js,
                           puntos=puntos, comuna=comuna)


@app.route("/solicitudes/nueva", methods=["POST"])
@rol_requerido("beneficiario")
def solicitud_nueva():
    # El tipo llega como "idTipo-idUnidad", por ejemplo "12-3"
    try:
        tipo, unidad = (int(x) for x in request.form.get("opcion", "").split("-"))
    except ValueError:
        tipo = unidad = None
    punto = request.form.get("punto", type=int)
    try:
        cantidad = Decimal(request.form.get("cantidad", "").replace(",", ".").strip())
        if not cantidad.is_finite():
            cantidad = None
    except InvalidOperation:
        cantidad = None

    if tipo is None or unidad is None or cantidad is None or punto is None:
        flash("Elige la categoría, el tipo de alimento, una cantidad válida "
              "y el punto de entrega.", "error")
        return redirect(url_for("solicitudes"))

    uid = session["id_usuario"]
    try:
        filas = ejecutar("CALL crear_solicitud(%s, %s, %s, %s, %s, NULL)",
                         (uid, tipo, unidad, cantidad, punto), id_usuario=uid)
        flash(f"Solicitud #{filas[0]['p_id_solicitud']} creada. "
              "Un gestor la revisará.", "ok")
    except ErrorDeNegocio as e:
        flash(str(e), "error")
    return redirect(url_for("solicitudes"))


@app.route("/solicitudes/<int:id_solicitud>/cancelar", methods=["POST"])
@rol_requerido("beneficiario")
def solicitud_cancelar(id_solicitud):
    uid = session["id_usuario"]   # siempre de la sesión: solo cancelas las TUYAS
    try:
        ejecutar("CALL cancelar_solicitud(%s, %s, NULL)",
                 (id_solicitud, uid), id_usuario=uid)
        flash(f"Solicitud #{id_solicitud} cancelada.", "ok")
    except ErrorDeNegocio as e:
        flash(str(e), "error")
    return redirect(url_for("solicitudes"))


@app.route("/solicitudes/<int:id_solicitud>/reservar", methods=["POST"])
@rol_requerido(*ROLES_GESTION)
def solicitud_reservar(id_solicitud):
    uid = session["id_usuario"]
    try:
        filas = ejecutar("CALL reservar_inventario(%s, %s, NULL)",
                         (id_solicitud, uid), id_usuario=uid)
        flash(f"Reserva #{filas[0]['p_id_reserva']} creada para la "
              f"solicitud #{id_solicitud}.", "ok")
        return redirect(url_for("reservas"))
    except ErrorDeNegocio as e:
        flash(str(e), "error")
        return redirect(url_for("solicitudes"))


# ---------------------------------------------------------------------------
# Reservas activas: confirmar entrega o cancelar
# ---------------------------------------------------------------------------
@app.route("/reservas")
@rol_requerido(*ROLES_GESTION)
def reservas():
    activas = consultar(
        """
        SELECT r.id_reserva, r.fecha_reserva, s.id_solicitud, s.fecha_solicitud,
               us.nombre AS beneficiario, b.documento, b.comuna,
               s.id_punto AS id_punto_solicitado, ps.nombre AS punto_solicitado,
               string_agg(l.descripcion || ' (' ||
                          replace(rd.cantidad::text, '.', ',') || ' ' || un.abreviatura ||
                          ', vence ' || to_char(l.fecha_vencimiento, 'DD/MM') || ')',
                          '; ' ORDER BY l.fecha_vencimiento) AS lotes
        FROM reserva r
        JOIN solicitud s        ON s.id_solicitud = r.id_solicitud
        JOIN beneficiario b     ON b.id_beneficiario = s.id_beneficiario
        JOIN usuario us         ON us.id_usuario = b.id_usuario
        JOIN reserva_detalle rd ON rd.id_reserva = r.id_reserva
        JOIN lote l             ON l.id_lote = rd.id_lote
        JOIN unidad un          ON un.id_unidad = l.id_unidad
        LEFT JOIN punto_entrega ps ON ps.id_punto = s.id_punto
        WHERE r.estado = 'activa'
        GROUP BY r.id_reserva, r.fecha_reserva, s.id_solicitud, s.fecha_solicitud,
                 us.nombre, b.documento, b.comuna, s.id_punto, ps.nombre
        ORDER BY r.fecha_reserva
        """
    )
    activas = con_detalle(activas)
    puntos = consultar("SELECT id_punto, nombre FROM punto_entrega WHERE activo ORDER BY nombre")
    return render_template("reservas.html", activas=activas, puntos=puntos)


@app.route("/reservas/<int:id_reserva>/entregar", methods=["POST"])
@rol_requerido(*ROLES_GESTION)
def reserva_entregar(id_reserva):
    punto = request.form.get("punto", type=int)
    observacion = request.form.get("observacion", "").strip()[:300] or None
    if punto is None:
        flash("Elige el punto de entrega.", "error")
        return redirect(url_for("reservas"))

    uid = session["id_usuario"]
    try:
        filas = ejecutar("CALL confirmar_entrega(%s, %s, %s, %s, NULL)",
                         (id_reserva, uid, punto, observacion), id_usuario=uid)
        flash(f"Entrega #{filas[0]['p_id_entrega']} registrada para la "
              f"reserva #{id_reserva}.", "ok")
    except ErrorDeNegocio as e:
        flash(str(e), "error")
    return redirect(url_for("reservas"))


@app.route("/reservas/<int:id_reserva>/cancelar", methods=["POST"])
@rol_requerido(*ROLES_GESTION)
def reserva_cancelar(id_reserva):
    motivo = request.form.get("motivo", "").strip()[:300] or None
    uid = session["id_usuario"]
    try:
        ejecutar("CALL cancelar_reserva(%s, %s, %s)",
                 (id_reserva, uid, motivo), id_usuario=uid)
        flash(f"Reserva #{id_reserva} cancelada. El inventario quedó libre otra vez.", "ok")
    except ErrorDeNegocio as e:
        flash(str(e), "error")
    return redirect(url_for("reservas"))


# ---------------------------------------------------------------------------
# Historial de entregas
# ---------------------------------------------------------------------------
@app.route("/entregas")
@rol_requerido(*ROLES_GESTION)
def entregas():
    filas = consultar(
        """
        SELECT e.id_entrega, e.fecha_entrega, e.id_reserva, e.observacion,
               s.id_solicitud, s.fecha_solicitud,
               us.nombre AS beneficiario, b.documento, b.comuna,
               g.nombre AS gestor, p.nombre AS punto,
               ps.nombre AS punto_solicitado
        FROM entrega e
        JOIN usuario g          ON g.id_usuario = e.id_usuario_gestor
        JOIN reserva r          ON r.id_reserva = e.id_reserva
        JOIN solicitud s        ON s.id_solicitud = r.id_solicitud
        JOIN beneficiario b     ON b.id_beneficiario = s.id_beneficiario
        JOIN usuario us         ON us.id_usuario = b.id_usuario
        LEFT JOIN punto_entrega p  ON p.id_punto = e.id_punto
        LEFT JOIN punto_entrega ps ON ps.id_punto = s.id_punto
        ORDER BY e.fecha_entrega DESC
        LIMIT 50
        """
    )
    return render_template("entregas.html", filas=con_detalle(filas))


# ---------------------------------------------------------------------------
# Administración (solo administrador): catálogos, usuarios y roles
# ---------------------------------------------------------------------------
def _admin_llamar(sql, params, mensaje_ok, destino):
    """Llama a un procedimiento de administración. Quien lo ejecuta sale
    SIEMPRE de la sesión (nunca del formulario) y es el primer parámetro."""
    uid = session["id_usuario"]
    try:
        ejecutar(sql, (uid,) + params, id_usuario=uid)
        flash(mensaje_ok, "ok")
    except ErrorDeNegocio as e:
        flash(str(e), "error")
    return redirect(url_for(destino))


@app.route("/admin/catalogos")
@rol_requerido("administrador")
def admin_catalogos():
    return render_template(
        "admin_catalogos.html",
        categorias=consultar("SELECT id_categoria, nombre FROM categoria ORDER BY nombre"),
        tipos=consultar(
            """SELECT t.id_tipo, t.nombre, t.activo, c.nombre AS categoria
               FROM tipo_alimento t JOIN categoria c ON c.id_categoria = t.id_categoria
               ORDER BY c.nombre, t.nombre"""),
        unidades=consultar("SELECT id_unidad, nombre, abreviatura FROM unidad ORDER BY nombre"),
        puntos=consultar(
            "SELECT id_punto, nombre, direccion, comuna, activo FROM punto_entrega ORDER BY nombre"),
    )


@app.route("/admin/categoria", methods=["POST"])
@rol_requerido("administrador")
def admin_categoria():
    return _admin_llamar(
        "CALL admin_guardar_categoria(%s, %s, %s)",
        (request.form.get("id", type=int), request.form.get("nombre", "")),
        "Categoría guardada.", "admin_catalogos")


@app.route("/admin/tipo", methods=["POST"])
@rol_requerido("administrador")
def admin_tipo():
    return _admin_llamar(
        "CALL admin_guardar_tipo(%s, %s, %s, %s, %s)",
        (request.form.get("id", type=int), request.form.get("id_categoria", type=int),
         request.form.get("nombre", ""), "activo" in request.form),
        "Tipo de alimento guardado.", "admin_catalogos")


@app.route("/admin/unidad", methods=["POST"])
@rol_requerido("administrador")
def admin_unidad():
    return _admin_llamar(
        "CALL admin_guardar_unidad(%s, %s, %s, %s)",
        (request.form.get("id", type=int), request.form.get("nombre", ""),
         request.form.get("abreviatura", "")),
        "Unidad guardada.", "admin_catalogos")


@app.route("/admin/punto", methods=["POST"])
@rol_requerido("administrador")
def admin_punto():
    return _admin_llamar(
        "CALL admin_guardar_punto(%s, %s, %s, %s, %s, %s)",
        (request.form.get("id", type=int), request.form.get("nombre", ""),
         request.form.get("direccion", ""), request.form.get("comuna", ""),
         "activo" in request.form),
        "Punto de entrega guardado.", "admin_catalogos")


@app.route("/admin/usuarios")
@rol_requerido("administrador")
def admin_usuarios():
    q = request.args.get("q", "").strip()
    usuarios = consultar(
        """
        SELECT u.id_usuario, u.nombre, u.correo, u.activo,
               array_remove(array_agg(r.nombre ORDER BY r.nombre), NULL) AS roles,
               d.nombre AS donante
        FROM usuario u
        LEFT JOIN usuario_rol ur     ON ur.id_usuario = u.id_usuario
        LEFT JOIN rol r              ON r.id_rol = ur.id_rol
        LEFT JOIN usuario_donante ud ON ud.id_usuario = u.id_usuario
        LEFT JOIN donante d          ON d.id_donante = ud.id_donante
        WHERE %s = '' OR u.nombre ILIKE %s OR u.correo ILIKE %s
        GROUP BY u.id_usuario, d.nombre
        ORDER BY u.activo DESC, u.nombre
        LIMIT 100
        """,
        (q, f"%{q}%", f"%{q}%"),
    )
    donantes = consultar("SELECT id_donante, nombre FROM donante WHERE activo ORDER BY nombre")
    return render_template("admin_usuarios.html", usuarios=usuarios,
                           donantes=donantes, q=q,
                           roles_asignables=["administrador", "gestor", "donante"])


@app.route("/admin/usuarios/crear", methods=["POST"])
@rol_requerido("administrador")
def admin_usuario_crear():
    clave = request.form.get("clave", "")
    if len(clave) < 8:
        flash("La contraseña debe tener al menos 8 caracteres.", "error")
        return redirect(url_for("admin_usuarios"))
    return _admin_llamar(
        "CALL admin_crear_usuario(%s, %s, %s, %s, %s, %s, NULL)",
        (request.form.get("nombre", ""), request.form.get("correo", ""),
         generate_password_hash(clave), request.form.get("rol", ""),
         request.form.get("id_donante", type=int)),
        "Usuario creado.", "admin_usuarios")


@app.route("/admin/usuarios/<int:id_usuario>/estado", methods=["POST"])
@rol_requerido("administrador")
def admin_usuario_estado(id_usuario):
    activo = request.form.get("activo") == "1"
    return _admin_llamar(
        "CALL admin_estado_usuario(%s, %s, %s)", (id_usuario, activo),
        "Usuario activado." if activo else "Usuario desactivado.", "admin_usuarios")


@app.route("/admin/usuarios/<int:id_usuario>/rol", methods=["POST"])
@rol_requerido("administrador")
def admin_usuario_rol(id_usuario):
    rol = request.form.get("rol", "")
    if request.form.get("accion") == "quitar":
        return _admin_llamar("CALL admin_quitar_rol(%s, %s, %s)", (id_usuario, rol),
                             "Rol quitado.", "admin_usuarios")
    return _admin_llamar("CALL admin_asignar_rol(%s, %s, %s, %s)",
                         (id_usuario, rol, request.form.get("id_donante", type=int)),
                         "Rol asignado.", "admin_usuarios")


# ---------------------------------------------------------------------------
# Registrar lotes (donaciones)
#   - El donante solo puede registrar en las sedes de SU organización.
#   - El gestor y el administrador pueden registrar en cualquier sede.
#   La regla final la hace cumplir la base de datos (registrar_lote), así
#   que aunque alguien manipule el formulario, la base lo rechaza.
# ---------------------------------------------------------------------------
@app.route("/lotes")
@rol_requerido(*ROLES_DONACION)
def lotes():
    uid = session["id_usuario"]
    sedes = consultar(
        """
        SELECT s.id_sede, s.nombre AS sede, s.direccion, d.nombre AS donante
        FROM sede s
        JOIN donante d ON d.id_donante = s.id_donante
        WHERE d.activo
          AND (%s OR s.id_donante IN (
                SELECT id_donante FROM usuario_donante WHERE id_usuario = %s))
        ORDER BY d.nombre, s.nombre
        """,
        (es_gestion(), uid),        # el usuario sale siempre de la sesión
    )
    categorias = consultar("SELECT id_categoria, nombre FROM categoria ORDER BY nombre")
    tipos_js = consultar(
        "SELECT id_tipo, id_categoria, nombre FROM tipo_alimento "
        "WHERE activo ORDER BY (nombre = 'Otro'), nombre"
    )
    unidades = consultar("SELECT id_unidad, nombre, abreviatura FROM unidad ORDER BY nombre")
    recientes = consultar(
        """
        SELECT l.id_lote, l.descripcion, c.nombre AS categoria, t.nombre AS tipo,
               s.nombre AS sede,
               l.cantidad_inicial, l.saldo, u.abreviatura,
               l.fecha_vencimiento, l.estado
        FROM lote l
        JOIN sede s      ON s.id_sede = l.id_sede
        JOIN categoria c ON c.id_categoria = l.id_categoria
        JOIN tipo_alimento t ON t.id_tipo = l.id_tipo
        JOIN unidad u    ON u.id_unidad = l.id_unidad
        WHERE %s OR s.id_donante IN (
                SELECT id_donante FROM usuario_donante WHERE id_usuario = %s)
        ORDER BY l.creado_en DESC
        LIMIT 15
        """,
        (es_gestion(), uid),
    )
    return render_template("lotes.html", sedes=sedes, categorias=categorias,
                           unidades=unidades, tipos_js=tipos_js, recientes=recientes,
                           hoy=date.today().isoformat())


@app.route("/lotes/nuevo", methods=["POST"])
@rol_requerido(*ROLES_DONACION)
def lote_nuevo():
    sede = request.form.get("sede", type=int)
    tipo = request.form.get("tipo", type=int)
    unidad = request.form.get("unidad", type=int)
    descripcion = request.form.get("descripcion", "").strip()
    try:
        cantidad = Decimal(request.form.get("cantidad", "").replace(",", ".").strip())
        cantidad = cantidad.quantize(Decimal("0.01")) if cantidad.is_finite() else None
    except InvalidOperation:
        cantidad = None
    try:
        vence = date.fromisoformat(request.form.get("vence", ""))
    except ValueError:
        vence = None

    if None in (sede, tipo, unidad) or not descripcion or len(descripcion) > 150:
        flash("Elige la sede, la categoría, el tipo de alimento y la unidad, y escribe una "
              "descripción de máximo 150 letras.", "error")
    elif cantidad is None or cantidad <= 0 or cantidad >= Decimal("100000000"):
        flash("Escribe una cantidad válida, mayor que cero.", "error")
    elif vence is None or vence < date.today():
        flash("Escribe una fecha de vencimiento de hoy en adelante.", "error")
    else:
        uid = session["id_usuario"]
        try:
            filas = ejecutar(
                "CALL registrar_lote(%s, %s, %s, %s, %s, %s, %s, NULL)",
                (uid, sede, tipo, unidad, descripcion, cantidad, vence),
                id_usuario=uid,
            )
            flash(f"Lote #{filas[0]['p_id_lote']} registrado. ¡Gracias por la donación!", "ok")
        except ErrorDeNegocio as e:
            flash(str(e), "error")
    return redirect(url_for("lotes"))


# ---------------------------------------------------------------------------
# Alertas de vencimiento (solo gestión)
#   - "Por vencer": lotes que vencen en 3 días o menos (vista de la base).
#   - "Vencidos sin registrar": lotes cuya fecha ya pasó y aún tienen saldo.
#     El botón llama a marcar_lotes_vencidos, que los pasa a "vencido" y
#     anota la pérdida en el historial de movimientos.
# ---------------------------------------------------------------------------
@app.route("/alertas")
@rol_requerido(*ROLES_GESTION)
def alertas():
    por_vencer = consultar("SELECT * FROM v_alertas_vencimiento ORDER BY fecha_vencimiento")
    vencidos = consultar(
        """
        SELECT l.id_lote, l.descripcion, d.nombre AS donante, s.nombre AS sede,
               c.nombre AS categoria, l.saldo, u.abreviatura AS unidad,
               l.fecha_vencimiento,
               (CURRENT_DATE - l.fecha_vencimiento) AS dias_vencido
        FROM lote l
        JOIN sede s      ON s.id_sede = l.id_sede
        JOIN donante d   ON d.id_donante = s.id_donante
        JOIN categoria c ON c.id_categoria = l.id_categoria
        JOIN unidad u    ON u.id_unidad = l.id_unidad
        WHERE l.fecha_vencimiento < CURRENT_DATE
          AND l.saldo > 0
          AND l.estado IN ('activo', 'vencido')
        ORDER BY l.fecha_vencimiento
        """
    )
    return render_template("alertas.html", por_vencer=por_vencer, vencidos=vencidos)


@app.route("/alertas/marcar-vencidos", methods=["POST"])
@rol_requerido(*ROLES_GESTION)
def marcar_vencidos():
    uid = session["id_usuario"]
    try:
        filas = ejecutar("CALL marcar_lotes_vencidos(%s, NULL)", (uid,), id_usuario=uid)
        n = filas[0]["p_lotes_marcados"]
        if n:
            flash(f"{n} lote{'s' if n != 1 else ''} marcado{'s' if n != 1 else ''} "
                  "como vencido y la pérdida quedó registrada.", "ok")
        else:
            flash("No había lotes vencidos por registrar.", "info")
    except ErrorDeNegocio as e:
        flash(str(e), "error")
    return redirect(url_for("alertas"))


# ---------------------------------------------------------------------------
# Páginas de error
# ---------------------------------------------------------------------------
@app.errorhandler(400)
def solicitud_invalida(_error):
    return render_template(
        "error.html", titulo="Formulario no válido",
        mensaje="El formulario caducó o no es válido. Vuelve a cargar la página "
                "e inténtalo de nuevo."), 400


@app.errorhandler(403)
def sin_permiso(_error):
    return render_template(
        "error.html", titulo="Sin permiso",
        mensaje="Tu usuario no tiene permiso para entrar a esta página."), 403


@app.errorhandler(404)
def no_encontrada(_error):
    return render_template(
        "error.html", titulo="No encontrada",
        mensaje="Esa página no existe."), 404


if __name__ == "__main__":
    app.run(debug=True)
