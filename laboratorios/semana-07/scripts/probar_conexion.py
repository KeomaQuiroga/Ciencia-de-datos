"""
probar_conexion.py

Prueba rápida: ¿el usuario de servicio NYC_TAXI_SVC puede entrar a
Snowflake usando su llave privada?

Se ejecuta dentro de un contenedor de Docker (ver instrucciones del
Paso 2), así no necesitas instalar Python en tu computadora.
"""
import os

import snowflake.connector

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    authenticator="SNOWFLAKE_JWT",  # = autenticación con par de llaves
    private_key_file=os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH", "/keys/rsa_key.p8"),
    role=os.environ["SNOWFLAKE_ROLE"],
    warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
    database=os.environ["SNOWFLAKE_DATABASE"],
)

try:
    cur = conn.cursor()
    cur.execute(
        "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(), "
        "CURRENT_DATABASE(), CURRENT_VERSION()"
    )
    usuario, rol, warehouse, base, version = cur.fetchone()
    print("Conexión exitosa a Snowflake")
    print(f"  Usuario:   {usuario}")
    print(f"  Rol:       {rol}")
    print(f"  Warehouse: {warehouse}")
    print(f"  Base:      {base}")
    print(f"  Versión:   {version}")
finally:
    conn.close()