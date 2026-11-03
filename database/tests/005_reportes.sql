SELECT * FROM v_reporte_inventario_sede_categoria
ORDER BY saldo_por_vencer DESC NULLS LAST
LIMIT 10;