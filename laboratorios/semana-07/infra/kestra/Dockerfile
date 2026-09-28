# =====================================================================
# Imagen de Kestra para el laboratorio
#
# Parte de la imagen oficial de Kestra y le agrega un entorno de Python
# (/opt/pipeline-venv) con lo que necesita el pipeline:
#   - snowflake-connector-python -> ingesta a Snowflake
#   - dbt-core + dbt-snowflake    -> transformaciones Bronze/Silver/Gold
#
# Así Kestra puede ejecutar la ingesta y dbt directamente, sin
# instalar nada en tu computadora.
# =====================================================================
FROM kestra/kestra:v1.3.37

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt

RUN python3 -m venv /opt/pipeline-venv \
 && /opt/pipeline-venv/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/pipeline-venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt