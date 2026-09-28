#!/usr/bin/env bash
# ---------------------------------------------------------------------
# generar_llaves.sh
#
# 1) Genera el par de llaves RSA del usuario de servicio NYC_TAXI_SVC:
#      keys/rsa_key.p8   -> llave PRIVADA (secreta, nunca se sube a GitHub)
#      keys/rsa_key.pub  -> llave PÚBLICA (se registra en Snowflake)
# 2) Crea keys/00_bootstrap_listo.sql: el script de bootstrap con tu
#    llave pública ya insertada, listo para copiar y pegar en Snowsight.
#
# Uso (desde la carpeta semana-07):   bash scripts/generar_llaves.sh
# ---------------------------------------------------------------------
set -euo pipefail

# Ir a la raíz de semana-07, sin importar desde dónde se ejecute el script
cd "$(dirname "$0")/.."
mkdir -p keys

if [[ -f keys/rsa_key.p8 ]]; then
    echo "Ya existe keys/rsa_key.p8, así que no la sobrescribo."
    echo "(Si quieres llaves nuevas, borra la carpeta keys/ y vuelve a ejecutar.)"
else
    # Llave privada RSA de 2048 bits en formato PKCS8, que es el que pide Snowflake
    openssl genrsa 2048 2>/dev/null \
        | openssl pkcs8 -topk8 -inform PEM -out keys/rsa_key.p8 -nocrypt
    # Llave pública derivada de la privada
    openssl rsa -in keys/rsa_key.p8 -pubout -out keys/rsa_key.pub 2>/dev/null
    chmod 600 keys/rsa_key.p8
    echo "Llaves creadas en keys/"
fi

# Snowflake quiere la llave pública en una sola línea y sin los
# encabezados "-----BEGIN/END PUBLIC KEY-----"
PUB=$(grep -v "PUBLIC KEY" keys/rsa_key.pub | tr -d '\n')

sed "s|__RSA_PUBLIC_KEY__|${PUB}|" infra/snowflake/00_bootstrap_admin.sql \
    > keys/00_bootstrap_listo.sql

echo "Listo. Copia el contenido de keys/00_bootstrap_listo.sql en Snowsight y ejecútalo completo."