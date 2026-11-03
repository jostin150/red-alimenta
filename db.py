"""Conexión a PostgreSQL. Todo el proyecto usa estas dos funciones."""
import os
from pathlib import Path

import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

# Lee el archivo .env que está junto a este archivo y deja que mande sobre
# cualquier variable que Windows ya tenga con el mismo nombre.
load_dotenv(Path(__file__).resolve().parent / ".env", override=True)


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