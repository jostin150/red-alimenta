"""Conexión a PostgreSQL. Todo el proyecto usa estas funciones:

- consultar(): para LEER datos (SELECT).
- ejecutar():  para CAMBIAR datos o llamar procedimientos (CALL ...).
"""
import os
from pathlib import Path

import psycopg2
from psycopg2 import errors
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

# Lee el archivo .env que está junto a este archivo y deja que mande sobre
# cualquier variable que Windows ya tenga con el mismo nombre.
load_dotenv(Path(__file__).resolve().parent / ".env", override=True)


class ErrorDeNegocio(Exception):
    """Un error con un mensaje que SÍ se le puede mostrar a la persona."""


def get_conn():
    """Abre una conexión nueva con los datos del archivo .env."""
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "alimenta"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )


def consultar(sql, params=None):
    """Ejecuta un SELECT y devuelve una lista de diccionarios.

    Los valores van SIEMPRE en `params`, nunca pegados dentro del texto SQL.
    Eso se llama consulta parametrizada y evita la inyección SQL.
    """
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            return cur.fetchall()
    finally:
        conn.close()


def _mensaje_legible(error):
    """Convierte un error de PostgreSQL en un mensaje que una persona entienda."""
    # Errores que escribimos nosotros con RAISE EXCEPTION en los procedimientos:
    # su mensaje ya está pensado para mostrarse tal cual.
    if isinstance(error, errors.RaiseException):
        return error.diag.message_primary

    if isinstance(error, errors.CheckViolation):
        return "Algún valor no cumple las reglas (por ejemplo, una cantidad negativa)."
    if isinstance(error, errors.UniqueViolation):
        return "Ese dato ya existe y no se puede repetir."
    if isinstance(error, errors.ForeignKeyViolation):
        return "Se hace referencia a algo que no existe."
    if isinstance(error, errors.NotNullViolation):
        return "Falta llenar un campo obligatorio."
    if isinstance(error, errors.InsufficientPrivilege):
        return "No tienes permiso para hacer esta operación."

    # Cualquier otro error: no mostramos detalles técnicos a la persona.
    return "Ocurrió un error inesperado en la base de datos."


def ejecutar(sql, params=None, id_usuario=None):
    """Ejecuta un cambio (INSERT, UPDATE o CALL a un procedimiento).

    - Si pasas `id_usuario`, la base lo anota para la auditoría. Ese número
      debe salir de la SESIÓN de quien inició sesión, nunca de un formulario.
    - Si todo sale bien, confirma los cambios (commit) y devuelve las filas
      que haya producido (por ejemplo, el id de la reserva creada).
    - Si algo falla, deshace todo (rollback) y lanza ErrorDeNegocio con un
      mensaje que se puede mostrar en la página.
    """
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if id_usuario is not None:
                # 'true' = el dato solo vale dentro de esta transacción
                cur.execute("SELECT set_config('app.id_usuario', %s, true)",
                            (str(id_usuario),))
            cur.execute(sql, params)
            filas = cur.fetchall() if cur.description else []
        conn.commit()
        return filas
    except psycopg2.Error as e:
        conn.rollback()
        print("Error de base de datos:", e)  # solo para ti, en la terminal
        raise ErrorDeNegocio(_mensaje_legible(e)) from e
    finally:
        conn.close()
