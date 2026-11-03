"""Prueba la conexión paso a paso y muestra el error REAL de PostgreSQL.

Uso:  python probar_conexion.py
"""
import os
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

RUTA_ENV = Path(__file__).resolve().parent / ".env"


def enmascarar(texto):
    if not texto:
        return "(vacía)"
    return texto[0] + "*" * (len(texto) - 2) + texto[-1] if len(texto) > 2 else "**"


def mensaje_real(error):
    """Si PostgreSQL contestó con tildes de Windows, las decodifica bien."""
    if isinstance(error, UnicodeDecodeError):
        return error.object.decode("cp1252", errors="replace")
    return str(error)


print("0) ¿De dónde salen los datos?")
print("   Busco el archivo en:", RUTA_ENV)
print("   ¿Existe con ese nombre exacto?:", "SÍ" if RUTA_ENV.exists() else "NO")
print("   DB_USER ya definido en Windows antes de leerlo:", os.environ.get("DB_USER") or "no")

load_dotenv(RUTA_ENV, override=True)

print()
print("Datos que usará el programa:")
print("  servidor:", os.getenv("DB_HOST"), "| puerto:", os.getenv("DB_PORT"))
print("  base:", os.getenv("DB_NAME"), "| usuario:", os.getenv("DB_USER"))
print("  contraseña:", enmascarar(os.getenv("DB_PASSWORD")),
      f"({len(os.getenv('DB_PASSWORD') or '')} caracteres)")
print()

# 1) ¿Se puede abrir la conexión?
try:
    conn = psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "alimenta"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        connect_timeout=5,
    )
    print("1) Conexión: OK")
except Exception as e:
    print("1) Conexión: FALLÓ")
    print("   Mensaje real:", mensaje_real(e))
    raise SystemExit

# 2) ¿Puede leer cada objeto que usa la aplicación?
for objeto in ("lote", "v_inventario_disponible"):
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT count(*) FROM {objeto}")
            print(f"2) Leer {objeto}: OK ({cur.fetchone()[0]} filas)")
        conn.rollback()
    except Exception as e:
        print(f"2) Leer {objeto}: FALLÓ")
        print("   Mensaje real:", mensaje_real(e))
        conn.rollback()

conn.close()