{#-
    BRONZE: viajes tal como vienen en la fuente + metadata de origen y carga.

    - Columnas originales: mismos nombres y valores que en RAW, sin limpiar.
    - Metadata agregada:
        _source_file       archivo de origen
        _source_period     período (mes) del archivo, sacado de su nombre
        _file_last_modified fecha del archivo en el stage
        _loaded_at         cuándo se cargó el archivo a RAW
        _bronze_loaded_at  cuándo dbt lo escribió en Bronze

    Carga incremental "por archivo" (delete+insert con unique_key = _source_file):
    en cada ejecución solo se procesan los archivos cargados o recargados en RAW
    desde la última vez. Primero se borran de Bronze todas las filas de esos
    archivos y luego se insertan de nuevo. Así, re-ejecutar nunca duplica filas.
-#}
{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'delete+insert',
        unique_key = '_source_file'
    )
}}

with raw as (

    select *
    from {{ source('raw', 'yellow_trips') }}

    {% if is_incremental() %}
    -- Solo archivos que llegaron a RAW después de la última carga a Bronze
    where _loaded_at > (
        select coalesce(max(_loaded_at), '1900-01-01'::timestamp_ltz)
        from {{ this }}
    )
    {% endif %}

)

select
    -- Columnas originales (diccionario de datos de TLC), sin cambios
    vendorid,
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    passenger_count,
    trip_distance,
    ratecodeid,
    store_and_fwd_flag,
    pulocationid,
    dolocationid,
    payment_type,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    total_amount,
    congestion_surcharge,
    airport_fee,
    cbd_congestion_fee,

    -- Metadata de origen y de carga
    _source_file,
    to_date(regexp_substr(_source_file, '[0-9]{4}-[0-9]{2}') || '-01') as _source_period,
    _file_last_modified,
    _loaded_at,
    current_timestamp() as _bronze_loaded_at

from raw
