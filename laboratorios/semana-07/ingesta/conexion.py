"""
conexion.py

Una sola función, conectar(), que abre una sesión en Snowflake con el
usuario de servicio y su llave privada. La usan todos los scripts de
ingesta, así la forma de conectarse está definida en un solo lugar.

Lee la configuración de variables de entorno (Kestra se las pasa):
    SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_ROLE,
    SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE, SNOWFLAKE_PRIVATE_KEY_PATH
"""
import os

import snowflake.connector


def _variable(nombre: str) -> str:
    valor = os.environ.get(nombre)
    if not valor:
        raise RuntimeError(f"Falta la variable de entorno {nombre}")
    return valor


def conectar(etiqueta: str = "nyc_taxi_pipeline"):
    """Abre una conexión a Snowflake autenticando con par de llaves."""
    return snowflake.connector.connect(
        account=_variable("SNOWFLAKE_ACCOUNT"),
        user=_variable("SNOWFLAKE_USER"),
        authenticator="SNOWFLAKE_JWT",  # = autenticación con par de llaves
        private_key_file=_variable("SNOWFLAKE_PRIVATE_KEY_PATH"),
        role=_variable("SNOWFLAKE_ROLE"),
        warehouse=_variable("SNOWFLAKE_WAREHOUSE"),
        database=_variable("SNOWFLAKE_DATABASE"),
        session_parameters={
            # La etiqueta aparece en el historial de consultas de Snowflake,
            # así puedes filtrar qué consultas hizo el pipeline.
            "QUERY_TAG": etiqueta,
            # Trabajamos en UTC para que ninguna fecha u hora de los viajes
            # se desplace por la zona horaria de la sesión.
            "TIMEZONE": "UTC",
        },
    )