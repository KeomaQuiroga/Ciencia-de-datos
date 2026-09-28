-- =====================================================================
-- 01_objetos_raw.sql
--
-- QUÉ HACE:  crea los esquemas del proyecto y la zona de aterrizaje
--            (RAW) donde la ingesta deja los datos tal como llegan.
-- QUIÉN:     el propio pipeline (Kestra), con el rol NYC_TAXI_ROLE.
-- CUÁNDO:    al inicio de cada ejecución. Es idempotente: usa
--            IF NOT EXISTS, así que re-ejecutarlo no borra ni duplica.
--
-- Lo ejecuta ingesta/crear_objetos_raw.py.
-- (Nota: no uses punto y coma ni dos guiones dentro de los textos
--  COMMENT, porque el script separa las sentencias por punto y coma.)
-- =====================================================================


-- ---------------------------------------------------------------------
-- Esquemas: uno por capa de la arquitectura
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS NYC_TAXI.RAW
    COMMENT = 'Aterrizaje: archivos originales y datos tal como llegan de NYC TLC';

CREATE SCHEMA IF NOT EXISTS NYC_TAXI.BRONZE
    COMMENT = 'dbt: datos cercanos a la fuente + metadata de origen y carga';

CREATE SCHEMA IF NOT EXISTS NYC_TAXI.SILVER
    COMMENT = 'dbt: datos limpios, tipados, deduplicados y estandarizados';

CREATE SCHEMA IF NOT EXISTS NYC_TAXI.GOLD
    COMMENT = 'dbt: esquema estrella para analizar los viajes';


-- ---------------------------------------------------------------------
-- Formatos de archivo
-- USE_VECTORIZED_SCANNER hace que Snowflake lea bien los tipos lógicos
-- de Parquet (por ejemplo, las fechas y horas de los viajes).
-- ---------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS NYC_TAXI.RAW.FF_PARQUET
    TYPE = PARQUET
    USE_VECTORIZED_SCANNER = TRUE
    COMMENT = 'Archivos mensuales de viajes (Parquet)';

CREATE FILE FORMAT IF NOT EXISTS NYC_TAXI.RAW.FF_CSV
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    COMMENT = 'Tabla de zonas de taxi (CSV)';


-- ---------------------------------------------------------------------
-- Stages internos: carpetas dentro de Snowflake donde se suben los
-- archivos ORIGINALES descargados, antes de copiarlos a las tablas.
-- ---------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS NYC_TAXI.RAW.STG_YELLOW_TRIPS
    FILE_FORMAT = NYC_TAXI.RAW.FF_PARQUET
    COMMENT = 'Archivos yellow_tripdata_AAAA-MM.parquet originales';

CREATE STAGE IF NOT EXISTS NYC_TAXI.RAW.STG_TAXI_ZONES
    FILE_FORMAT = NYC_TAXI.RAW.FF_CSV
    COMMENT = 'Archivo taxi_zone_lookup.csv original';


-- ---------------------------------------------------------------------
-- Tabla RAW de viajes
-- Mismos nombres de columna que el diccionario de datos de TLC.
-- Los tipos son los del Parquet (enteros, decimales, fechas y texto).
-- Las columnas que empiezan con _ son metadata que agrega la carga.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS NYC_TAXI.RAW.YELLOW_TRIPS (
    VendorID                NUMBER(38,0),
    tpep_pickup_datetime    TIMESTAMP_NTZ,
    tpep_dropoff_datetime   TIMESTAMP_NTZ,
    passenger_count         NUMBER(38,0),
    trip_distance           FLOAT,
    RatecodeID              NUMBER(38,0),
    store_and_fwd_flag      VARCHAR,
    PULocationID            NUMBER(38,0),
    DOLocationID            NUMBER(38,0),
    payment_type            NUMBER(38,0),
    fare_amount             FLOAT,
    extra                   FLOAT,
    mta_tax                 FLOAT,
    tip_amount              FLOAT,
    tolls_amount            FLOAT,
    improvement_surcharge   FLOAT,
    total_amount            FLOAT,
    congestion_surcharge    FLOAT,
    Airport_fee             FLOAT,
    cbd_congestion_fee      FLOAT,

    _source_file            VARCHAR,        -- archivo de origen
    _file_last_modified     TIMESTAMP_LTZ,  -- fecha del archivo en el stage
    _loaded_at              TIMESTAMP_LTZ   -- fecha y hora de la carga
)
COMMENT = 'Viajes Yellow Taxi tal como vienen en los Parquet de NYC TLC';


-- ---------------------------------------------------------------------
-- Tabla RAW de zonas (catálogo de LocationID -> barrio y zona)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS NYC_TAXI.RAW.TAXI_ZONES (
    LocationID      NUMBER(38,0),
    Borough         VARCHAR,
    Zone            VARCHAR,
    service_zone    VARCHAR,

    _source_file    VARCHAR,
    _loaded_at      TIMESTAMP_LTZ
)
COMMENT = 'Catálogo de zonas de taxi tal como viene en taxi_zone_lookup.csv';


-- ---------------------------------------------------------------------
-- Bitácora de la ingesta: una fila por cada intento de carga de cada
-- archivo. Sirve para auditar y para no recargar lo que ya está.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS NYC_TAXI.RAW.INGESTION_LOG (
    source_file     VARCHAR,
    source_period   DATE,
    source_url      VARCHAR,
    status          VARCHAR,        -- LOADED / NOT_AVAILABLE / FAILED
    rows_loaded     NUMBER(38,0),
    file_size_bytes NUMBER(38,0),
    started_at      TIMESTAMP_LTZ,
    finished_at     TIMESTAMP_LTZ,
    message         VARCHAR
)
COMMENT = 'Bitácora de cargas del pipeline de ingesta';