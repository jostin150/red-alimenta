"""Punto de entrada de la aplicación Red Alimenta Medellín."""
import os
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask, render_template

from db import consultar

load_dotenv(Path(__file__).resolve().parent / ".env", override=True)

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "solo-para-desarrollo")


@app.route("/")
def inicio():
    total = consultar("SELECT count(*) AS total FROM lote")[0]["total"]
    return render_template("inicio.html", total_lotes=total)


@app.route("/inventario")
def inventario():
    # Usamos la vista que ya creaste en la base de datos
    filas = consultar("SELECT * FROM v_inventario_disponible ORDER BY fecha_vencimiento")
    columnas = list(filas[0].keys()) if filas else []
    return render_template("inventario.html", filas=filas, columnas=columnas)


if __name__ == "__main__":
    app.run(debug=True)