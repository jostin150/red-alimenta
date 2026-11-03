"""Prueba rápida de db.ejecutar().  Uso:  python probar_procedimientos.py

Supone que el usuario 1 es el administrador y el 2 es un gestor
(así quedan con los datos de prueba del proyecto).
"""
from db import ejecutar, ErrorDeNegocio

# 1) Debe FALLAR con un mensaje claro: la solicitud 999999 no existe.
try:
    ejecutar("CALL reservar_inventario(%s, %s, NULL)", (999999, 2), id_usuario=2)
    print("1) PROBLEMA: debía dar error y no lo dio")
except ErrorDeNegocio as e:
    print("1) OK, la base rechazó la reserva y dijo:", e)

# 2) Debe FUNCIONAR: un gestor marca los lotes vencidos.
try:
    filas = ejecutar("CALL marcar_lotes_vencidos(%s, 0)", (2,), id_usuario=2)
    print("2) OK, lotes marcados como vencidos:", filas[0]["p_lotes_marcados"])
except ErrorDeNegocio as e:
    print("2) PROBLEMA:", e)

# 3) Debe FUNCIONAR: el administrador ve la auditoría.
try:
    filas = ejecutar("SELECT * FROM ver_auditoria(%s, 3)", (1,))
    print("3) OK, el administrador ve", len(filas), "registros de auditoría")
except ErrorDeNegocio as e:
    print("3) PROBLEMA:", e)

# 4) Debe FALLAR: un gestor NO puede ver la auditoría.
try:
    ejecutar("SELECT * FROM ver_auditoria(%s, 3)", (2,))
    print("4) PROBLEMA: el gestor pudo ver la auditoría")
except ErrorDeNegocio as e:
    print("4) OK, al gestor se le negó el acceso y dijo:", e)
