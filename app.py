"""Punto de entrada de la aplicación Red Alimenta Medellín."""
import os
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash

from auth import login_requerido
from db import consultar

load_dotenv(Path(__file__).resolve().parent / ".env", override=True)

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
