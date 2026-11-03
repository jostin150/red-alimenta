"""Punto de entrada de la aplicación Red Alimenta Medellín."""
import os
import secrets
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path

from dotenv import load_dotenv
from flask import (Flask, abort, flash, redirect, render_template, request,
                   session, url_for)
from werkzeug.security import check_password_hash

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


# ---------------------------------------------------------------------------
# Inicio e inventario
# ---------------------------------------------------------------------------
@app.route("/")
@login_requerido
def inicio():
    total = consultar("SELECT count(*) AS total FROM lote")[0]["total"]
    return render_template("inicio.html", total_lotes=total)


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
                   string_agg(c.nombre || ' · ' ||
                              replace(round(sd.cantidad_solicitada, 2)::text, '.', ',') ||
                              ' ' || u.abreviatura, '; ' ORDER BY c.nombre) AS pedido
            FROM solicitud s
            JOIN beneficiario b       ON b.id_beneficiario = s.id_beneficiario
            JOIN usuario us           ON us.id_usuario = b.id_usuario
            JOIN solicitud_detalle sd ON sd.id_solicitud = s.id_solicitud
            JOIN categoria c          ON c.id_categoria = sd.id_categoria
            JOIN unidad u             ON u.id_unidad = sd.id_unidad
            WHERE s.estado = 'pendiente'
            GROUP BY s.id_solicitud, s.fecha_solicitud, us.nombre
            ORDER BY s.fecha_solicitud
            """
        )
        return render_template("solicitudes_gestion.html", pendientes=pendientes)

    if "beneficiario" not in session.get("roles", []):
        abort(403)

    propias = consultar(
        """
        SELECT s.id_solicitud, s.fecha_solicitud, s.estado,
               string_agg(c.nombre || ' · ' ||
                          replace(round(sd.cantidad_solicitada, 2)::text, '.', ',') ||
                          ' ' || u.abreviatura, '; ' ORDER BY c.nombre) AS pedido
        FROM solicitud s
        JOIN beneficiario b       ON b.id_beneficiario = s.id_beneficiario
        JOIN solicitud_detalle sd ON sd.id_solicitud = s.id_solicitud
        JOIN categoria c          ON c.id_categoria = sd.id_categoria
        JOIN unidad u             ON u.id_unidad = sd.id_unidad
        WHERE b.id_usuario = %s
        GROUP BY s.id_solicitud, s.fecha_solicitud, s.estado
        ORDER BY s.fecha_solicitud DESC
        LIMIT 20
        """,
        (session["id_usuario"],),   # siempre de la sesión
    )
    # Solo ofrecemos lo que hoy tiene inventario: categoría + unidad
    opciones = consultar(
        """
        SELECT c.id_categoria, c.nombre AS categoria,
               u.id_unidad, u.nombre AS unidad, u.abreviatura,
               sum(l.saldo) AS disponible
        FROM lote l
        JOIN categoria c ON c.id_categoria = l.id_categoria
        JOIN unidad u    ON u.id_unidad = l.id_unidad
        WHERE l.estado = 'activo' AND l.saldo > 0
          AND l.fecha_vencimiento >= CURRENT_DATE
        GROUP BY c.id_categoria, c.nombre, u.id_unidad, u.nombre, u.abreviatura
        ORDER BY c.nombre, u.nombre
        """
    )
    return render_template("solicitudes_beneficiario.html", propias=propias,
                           opciones=opciones)


@app.route("/solicitudes/nueva", methods=["POST"])
@rol_requerido("beneficiario")
def solicitud_nueva():
    # La opción llega como "idCategoría-idUnidad", por ejemplo "2-1"
    try:
        categoria, unidad = (int(x) for x in request.form.get("opcion", "").split("-"))
    except ValueError:
        categoria = unidad = None
    try:
        cantidad = Decimal(request.form.get("cantidad", "").replace(",", ".").strip())
        if not cantidad.is_finite():
            cantidad = None
    except InvalidOperation:
        cantidad = None

    if categoria is None or unidad is None or cantidad is None:
        flash("Elige qué necesitas y escribe una cantidad válida.", "error")
        return redirect(url_for("solicitudes"))

    uid = session["id_usuario"]
    try:
        filas = ejecutar("CALL crear_solicitud(%s, %s, %s, %s, NULL)",
                         (uid, categoria, unidad, cantidad), id_usuario=uid)
        flash(f"Solicitud #{filas[0]['p_id_solicitud']} creada. "
              "Un gestor la revisará.", "ok")
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
        SELECT r.id_reserva, r.fecha_reserva, s.id_solicitud,
               us.nombre AS beneficiario,
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
        WHERE r.estado = 'activa'
        GROUP BY r.id_reserva, r.fecha_reserva, s.id_solicitud, us.nombre
        ORDER BY r.fecha_reserva
        """
    )
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
        SELECT e.id_entrega, e.fecha_entrega, e.id_reserva,
               us.nombre AS beneficiario, g.nombre AS gestor,
               p.nombre AS punto, e.observacion
        FROM entrega e
        JOIN usuario g          ON g.id_usuario = e.id_usuario_gestor
        JOIN reserva r          ON r.id_reserva = e.id_reserva
        JOIN solicitud s        ON s.id_solicitud = r.id_solicitud
        JOIN beneficiario b     ON b.id_beneficiario = s.id_beneficiario
        JOIN usuario us         ON us.id_usuario = b.id_usuario
        LEFT JOIN punto_entrega p ON p.id_punto = e.id_punto
        ORDER BY e.fecha_entrega DESC
        LIMIT 50
        """
    )
    return render_template("entregas.html", filas=filas)


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
    unidades = consultar("SELECT id_unidad, nombre, abreviatura FROM unidad ORDER BY nombre")
    recientes = consultar(
        """
        SELECT l.id_lote, l.descripcion, c.nombre AS categoria, s.nombre AS sede,
               l.cantidad_inicial, l.saldo, u.abreviatura,
               l.fecha_vencimiento, l.estado
        FROM lote l
        JOIN sede s      ON s.id_sede = l.id_sede
        JOIN categoria c ON c.id_categoria = l.id_categoria
        JOIN unidad u    ON u.id_unidad = l.id_unidad
        WHERE %s OR s.id_donante IN (
                SELECT id_donante FROM usuario_donante WHERE id_usuario = %s)
        ORDER BY l.creado_en DESC
        LIMIT 15
        """,
        (es_gestion(), uid),
    )
    return render_template("lotes.html", sedes=sedes, categorias=categorias,
                           unidades=unidades, recientes=recientes,
                           hoy=date.today().isoformat())


@app.route("/lotes/nuevo", methods=["POST"])
@rol_requerido(*ROLES_DONACION)
def lote_nuevo():
    sede = request.form.get("sede", type=int)
    categoria = request.form.get("categoria", type=int)
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

    if None in (sede, categoria, unidad) or not descripcion or len(descripcion) > 150:
        flash("Elige la sede, la categoría y la unidad, y escribe una "
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
                (uid, sede, categoria, unidad, descripcion, cantidad, vence),
                id_usuario=uid,
            )
            flash(f"Lote #{filas[0]['p_id_lote']} registrado. ¡Gracias por la donación!", "ok")
        except ErrorDeNegocio as e:
            flash(str(e), "error")
    return redirect(url_for("lotes"))


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
