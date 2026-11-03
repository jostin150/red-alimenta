"""Ayudas para saber quién inició sesión y qué puede hacer."""
from functools import wraps

from flask import abort, flash, redirect, session, url_for


def login_requerido(vista):
    """Si no hay sesión iniciada, manda a la persona a la pantalla de ingreso."""
    @wraps(vista)
    def envoltura(*args, **kwargs):
        if "id_usuario" not in session:
            flash("Inicia sesión para continuar.", "info")
            return redirect(url_for("entrar"))
        return vista(*args, **kwargs)
    return envoltura


def rol_requerido(*roles_permitidos):
    """Además de tener sesión, exige alguno de los roles indicados.

    Ejemplo:  @rol_requerido("gestor", "administrador")
    """
    def decorador(vista):
        @wraps(vista)
        def envoltura(*args, **kwargs):
            if "id_usuario" not in session:
                flash("Inicia sesión para continuar.", "info")
                return redirect(url_for("entrar"))
            if not set(session.get("roles", [])) & set(roles_permitidos):
                abort(403)
            return vista(*args, **kwargs)
        return envoltura
    return decorador
