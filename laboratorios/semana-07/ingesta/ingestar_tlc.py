"""
ingestar_tlc.py

Ingesta automática de NYC TLC a Snowflake (capa RAW).

Para cada mes del rango pedido:
  1. Pregunta a TLC si el archivo existe y cuánto pesa (petición HEAD).
  2. Si ese mes ya está cargado igual (mismo tamaño de archivo y las
     mismas filas en RAW), lo salta.
  3. Si no, descarga el Parquet, lo sube tal cual al stage de Snowflake
     (así el archivo original queda guardado) y lo copia a
     RAW.YELLOW_TRIPS agregando metadata: archivo de origen, fecha del
     archivo y fecha de carga.
     Antes de copiar borra lo que hubiera de ese mismo archivo. El DELETE
     y el COPY van en una transacción, así que un mes nunca queda a
     medias ni duplicado.
  4. Registra el resultado en RAW.INGESTION_LOG.

También recarga el catálogo de zonas (taxi_zone_lookup.csv).

Uso:
    python ingestar_tlc.py --desde 2025-01 --hasta 2026-08 [--forzar]
"""
import argparse
import re
import sys
import tempfile
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from conexion import conectar

URL_BASE = "https://d37ci6vzurychx.cloudfront.net"
URL_ZONAS = f"{URL_BASE}/misc/taxi_zone_lookup.csv"
ARCHIVO_ZONAS = "taxi_zone_lookup.csv"

# TLC publica cada mes con unos dos meses de retraso. Si falta un mes
# reciente es normal (NOT_AVAILABLE). Si falta uno más antiguo que esto,
# algo anda mal (por ejemplo, un bloqueo de red) y se marca como FAILED.
MESES_DE_GRACIA = 4

# Estados que se guardan en RAW.INGESTION_LOG
LOADED, NOT_AVAILABLE, FAILED, SKIPPED = "LOADED", "NOT_AVAILABLE", "FAILED", "SKIPPED"


@dataclass
class Resultado:
    archivo: str
    estado: str
    filas: int | None = None
    detalle: str = ""


# ---------------------------------------------------------------------
# Utilidades de fechas y nombres
# ---------------------------------------------------------------------
def leer_mes(texto: str) -> date:
    """'2025-01' -> date(2025, 1, 1)."""
    if not re.fullmatch(r"\d{4}-\d{2}", texto):
        raise argparse.ArgumentTypeError(f"'{texto}' no tiene el formato AAAA-MM")
    anio, mes = map(int, texto.split("-"))
    if not 1 <= mes <= 12:
        raise argparse.ArgumentTypeError(f"'{texto}' tiene un mes inválido")
    return date(anio, mes, 1)


def meses_entre(desde: date, hasta: date) -> list[date]:
    """Lista de primeros de mes entre desde y hasta, ambos incluidos."""
    if desde > hasta:
        raise ValueError("--desde no puede ser posterior a --hasta")
    meses, actual = [], desde
    while actual <= hasta:
        meses.append(actual)
        actual = date(actual.year + actual.month // 12, actual.month % 12 + 1, 1)
    return meses


def sumar_meses(dia: date, n: int) -> date:
    total = dia.year * 12 + (dia.month - 1) + n
    return date(total // 12, total % 12 + 1, 1)


def nombre_archivo(periodo: date) -> str:
    return f"yellow_tripdata_{periodo:%Y-%m}.parquet"


def url_archivo(periodo: date) -> str:
    return f"{URL_BASE}/trip-data/{nombre_archivo(periodo)}"


# ---------------------------------------------------------------------
# Descargas
# ---------------------------------------------------------------------
def crear_sesion_http() -> requests.Session:
    """Sesión HTTP que reintenta sola ante errores temporales del servidor."""
    sesion = requests.Session()
    reintentos = Retry(
        total=4,
        backoff_factor=3,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["HEAD", "GET"],
    )
    sesion.mount("https://", HTTPAdapter(max_retries=reintentos))
    sesion.headers["User-Agent"] = "Mozilla/5.0 (nyc-taxi-lab; ingesta academica)"
    return sesion


def tamano_remoto(sesion: requests.Session, url: str) -> int | None:
    """Tamaño en bytes del archivo publicado, o None si no existe (403/404)."""
    respuesta = sesion.head(url, timeout=30, allow_redirects=True)
    if respuesta.status_code in (403, 404):
        return None
    respuesta.raise_for_status()
    largo = respuesta.headers.get("Content-Length")
    return int(largo) if largo else -1


def descargar(sesion: requests.Session, url: str, destino: Path) -> int:
    """Descarga url a destino por partes (sin cargar todo en memoria)."""
    with sesion.get(url, stream=True, timeout=(30, 300)) as respuesta:
        respuesta.raise_for_status()
        esperado = int(respuesta.headers.get("Content-Length", 0))
        escrito = 0
        with open(destino, "wb") as archivo:
            for bloque in respuesta.iter_content(chunk_size=1024 * 1024):
                archivo.write(bloque)
                escrito += len(bloque)
    if esperado and escrito != esperado:
        raise IOError(f"descarga incompleta: {escrito} de {esperado} bytes")
    return escrito


# ---------------------------------------------------------------------
# Snowflake
# ---------------------------------------------------------------------
def registrar(cur, archivo, periodo, url, estado, filas, tamano, inicio, mensaje):
    """Agrega una fila a la bitácora RAW.INGESTION_LOG."""
    cur.execute(
        """
        INSERT INTO RAW.INGESTION_LOG
            (source_file, source_period, source_url, status, rows_loaded,
             file_size_bytes, started_at, finished_at, message)
        VALUES (%s, %s, %s, %s, %s, %s, %s::TIMESTAMP_LTZ, CURRENT_TIMESTAMP(), %s)
        """,
        (archivo, periodo, url, estado, filas, tamano, inicio.isoformat(), mensaje[:1000]),
    )


def cargas_previas(cur) -> dict[str, tuple[int, int]]:
    """Última carga exitosa de cada archivo: {archivo: (bytes, filas)}."""
    cur.execute(
        """
        SELECT source_file, file_size_bytes, rows_loaded
        FROM RAW.INGESTION_LOG
        WHERE status = 'LOADED'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY source_file ORDER BY finished_at DESC) = 1
        """
    )
    return {archivo: (tamano, filas) for archivo, tamano, filas in cur.fetchall()}


def filas_en_raw(cur) -> dict[str, int]:
    """Filas que hay hoy en RAW.YELLOW_TRIPS por archivo de origen."""
    cur.execute("SELECT _source_file, COUNT(*) FROM RAW.YELLOW_TRIPS GROUP BY 1")
    return dict(cur.fetchall())


def subir_a_stage(cur, ruta: Path, stage: str) -> None:
    """PUT: sube el archivo original, sin comprimir, al stage interno."""
    cur.execute(f"PUT 'file://{ruta}' @{stage} AUTO_COMPRESS = FALSE OVERWRITE = TRUE")
    columnas = [c[0].lower() for c in cur.description]
    estado = cur.fetchone()[columnas.index("status")]
    if estado not in ("UPLOADED", "SKIPPED"):
        raise RuntimeError(f"PUT terminó con estado {estado}")


def filas_copiadas(cur) -> int:
    """Suma rows_loaded del resultado de un COPY INTO."""
    columnas = [c[0].lower() for c in cur.description]
    if "rows_loaded" not in columnas:
        raise RuntimeError("COPY no procesó ningún archivo (¿el archivo está en el stage?)")
    i = columnas.index("rows_loaded")
    return sum(fila[i] for fila in cur.fetchall())


def en_transaccion(cur, sentencias):
    """Ejecuta funciones sobre el cursor dentro de BEGIN/COMMIT; ROLLBACK si falla."""
    cur.execute("BEGIN")
    try:
        resultado = sentencias()
        cur.execute("COMMIT")
        return resultado
    except Exception:
        cur.execute("ROLLBACK")
        raise


# ---------------------------------------------------------------------
# Carga de un mes de viajes
# ---------------------------------------------------------------------
def cargar_mes(cur, sesion, periodo, carpeta, forzar, previas, en_raw, hoy) -> Resultado:
    archivo, url = nombre_archivo(periodo), url_archivo(periodo)
    inicio = datetime.now(timezone.utc)
    tamano = None

    try:
        tamano = tamano_remoto(sesion, url)

        # 1) ¿Está publicado?
        if tamano is None:
            if periodo >= sumar_meses(hoy.replace(day=1), -MESES_DE_GRACIA):
                msg = "TLC aún no publica este mes"
                registrar(cur, archivo, periodo, url, NOT_AVAILABLE, None, None, inicio, msg)
                return Resultado(archivo, NOT_AVAILABLE, detalle=msg)
            raise RuntimeError(
                "TLC respondió que el archivo no existe, pero es un mes antiguo. "
                "Revisa tu conexión a internet o si TLC cambió la URL."
            )

        # 2) ¿Ya está cargado igual? -> no hace falta repetir
        if not forzar and archivo in previas:
            tamano_prev, filas_prev = previas[archivo]
            if tamano_prev == tamano and en_raw.get(archivo) == filas_prev:
                return Resultado(archivo, SKIPPED, filas_prev, "ya cargado, sin cambios")

        # 3) Descargar, subir al stage y copiar a RAW
        ruta = carpeta / archivo
        print(f"  descargando {url} ...", flush=True)
        tamano = descargar(sesion, url, ruta)
        print(f"  subiendo {tamano / 1e6:.1f} MB al stage ...", flush=True)
        subir_a_stage(cur, ruta, "RAW.STG_YELLOW_TRIPS")
        ruta.unlink()

        def reemplazar_mes():
            cur.execute("DELETE FROM RAW.YELLOW_TRIPS WHERE _source_file = %s", (archivo,))
            cur.execute(
                f"""
                COPY INTO RAW.YELLOW_TRIPS
                FROM @RAW.STG_YELLOW_TRIPS
                FILES = ('{archivo}')
                FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_PARQUET')
                MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
                INCLUDE_METADATA = (
                    _source_file        = METADATA$FILENAME,
                    _file_last_modified = METADATA$FILE_LAST_MODIFIED,
                    _loaded_at          = METADATA$START_SCAN_TIME
                )
                ON_ERROR = ABORT_STATEMENT
                FORCE = TRUE
                """
            )
            return filas_copiadas(cur)

        print("  copiando a RAW.YELLOW_TRIPS ...", flush=True)
        filas = en_transaccion(cur, reemplazar_mes)
        registrar(cur, archivo, periodo, url, LOADED, filas, tamano, inicio, "ok")
        return Resultado(archivo, LOADED, filas)

    except Exception as error:  # se registra y se sigue con el próximo mes
        registrar(cur, archivo, periodo, url, FAILED, None, tamano, inicio, str(error))
        return Resultado(archivo, FAILED, detalle=str(error))


# ---------------------------------------------------------------------
# Carga del catálogo de zonas (reemplazo completo, es una tabla pequeña)
# ---------------------------------------------------------------------
def cargar_zonas(cur, sesion, carpeta) -> Resultado:
    inicio = datetime.now(timezone.utc)
    tamano = None
    try:
        ruta = carpeta / ARCHIVO_ZONAS
        tamano = descargar(sesion, URL_ZONAS, ruta)
        subir_a_stage(cur, ruta, "RAW.STG_TAXI_ZONES")
        ruta.unlink()

        def reemplazar_zonas():
            cur.execute("DELETE FROM RAW.TAXI_ZONES")
            cur.execute(
                f"""
                COPY INTO RAW.TAXI_ZONES
                    (LocationID, Borough, Zone, service_zone, _source_file, _loaded_at)
                FROM (
                    SELECT $1, $2, $3, $4, METADATA$FILENAME, METADATA$START_SCAN_TIME
                    FROM @RAW.STG_TAXI_ZONES
                )
                FILES = ('{ARCHIVO_ZONAS}')
                FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV')
                FORCE = TRUE
                """
            )
            return filas_copiadas(cur)

        filas = en_transaccion(cur, reemplazar_zonas)
        registrar(cur, ARCHIVO_ZONAS, None, URL_ZONAS, LOADED, filas, tamano, inicio, "ok")
        return Resultado(ARCHIVO_ZONAS, LOADED, filas)
    except Exception as error:
        registrar(cur, ARCHIVO_ZONAS, None, URL_ZONAS, FAILED, None, tamano, inicio, str(error))
        return Resultado(ARCHIVO_ZONAS, FAILED, detalle=str(error))


# ---------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(description="Ingesta NYC Yellow Taxi -> Snowflake RAW")
    parser.add_argument("--desde", type=leer_mes, default=leer_mes("2025-01"))
    parser.add_argument("--hasta", type=leer_mes, default=leer_mes("2026-08"))
    parser.add_argument("--forzar", action="store_true",
                        help="recarga los meses aunque ya estén cargados")
    args = parser.parse_args()

    periodos = meses_entre(args.desde, args.hasta)
    hoy = date.today()
    print(f"Meses a procesar: {len(periodos)} ({args.desde:%Y-%m} a {args.hasta:%Y-%m})"
          f"{' | recarga forzada' if args.forzar else ''}", flush=True)

    resultados: list[Resultado] = []
    sesion = crear_sesion_http()

    with conectar("nyc_taxi_ingesta") as conn, tempfile.TemporaryDirectory() as tmp:
        cur = conn.cursor()
        carpeta = Path(tmp)

        print("\n[zonas] taxi_zone_lookup.csv", flush=True)
        resultados.append(cargar_zonas(cur, sesion, carpeta))

        previas = cargas_previas(cur)
        en_raw = filas_en_raw(cur)
        for periodo in periodos:
            print(f"\n[{periodo:%Y-%m}] {nombre_archivo(periodo)}", flush=True)
            resultado = cargar_mes(cur, sesion, periodo, carpeta, args.forzar,
                                   previas, en_raw, hoy)
            print(f"  -> {resultado.estado} {resultado.filas or ''} {resultado.detalle}",
                  flush=True)
            resultados.append(resultado)

    # Resumen final
    print("\nResumen")
    print("-" * 72)
    for r in resultados:
        filas = f"{r.filas:,}" if r.filas is not None else "-"
        print(f"{r.archivo:<34} {r.estado:<14} {filas:>12}  {r.detalle}")
    total = sum(r.filas or 0 for r in resultados
                if r.estado in (LOADED, SKIPPED) and r.archivo != ARCHIVO_ZONAS)
    print("-" * 72)
    print(f"Filas de viajes en RAW para el rango: {total:,}")

    fallidos = [r for r in resultados if r.estado == FAILED]
    if fallidos:
        print(f"\n{len(fallidos)} archivo(s) fallaron. Revisa los mensajes de arriba.")
        return 1  # Kestra marcará la tarea como fallida
    return 0


if __name__ == "__main__":
    sys.exit(main())