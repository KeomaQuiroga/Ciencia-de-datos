"""
crear_objetos_raw.py

Ejecuta infra/snowflake/01_objetos_raw.sql: crea (si no existen) los
esquemas RAW, BRONZE, SILVER y GOLD, los formatos de archivo, los
stages y las tablas de aterrizaje. Es seguro ejecutarlo muchas veces.
"""
from pathlib import Path

from conexion import conectar

CARPETA_LAB = Path(__file__).resolve().parent.parent
ARCHIVO_SQL = CARPETA_LAB / "infra" / "snowflake" / "01_objetos_raw.sql"


def main() -> None:
    sql = ARCHIVO_SQL.read_text(encoding="utf-8")
    print(f"Ejecutando {ARCHIVO_SQL.name} ...")

    with conectar("nyc_taxi_setup") as conn:
        # execute_string ejecuta varias sentencias separadas por ";"
        for cursor in conn.execute_string(sql, remove_comments=True):
            resultado = cursor.fetchone()
            print(f"  - {resultado[0] if resultado else 'OK'}")

    print("Objetos RAW listos.")


if __name__ == "__main__":
    main()