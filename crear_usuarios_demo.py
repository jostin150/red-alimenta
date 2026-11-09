"""Pone una contraseña de DEMOSTRACIÓN a los usuarios de prueba.

Uso:  python crear_usuarios_demo.py

Solo toca a los usuarios con correo @alimenta.test (los inventados).
La contraseña se guarda protegida (hash), nunca en texto plano.
"""
from werkzeug.security import generate_password_hash

from db import consultar, ejecutar

CLAVE_DEMO = "Demo2026!"   # contraseña inventada

usuarios = consultar(
    "SELECT id_usuario, correo FROM usuario WHERE correo LIKE %s ORDER BY id_usuario",
    ("%@alimenta.test",),
)

for u in usuarios:
    # Cada usuario recibe su propio hash (con su propia sal aleatoria)
    ejecutar(
        "UPDATE usuario SET password_hash = %s WHERE id_usuario = %s",
        (generate_password_hash(CLAVE_DEMO), u["id_usuario"]),
    )

print(f"Listo: {len(usuarios)} usuarios de prueba con la contraseña de demostración.")
print("Prueba con  admin@alimenta.test  o  gestor1@alimenta.test")
