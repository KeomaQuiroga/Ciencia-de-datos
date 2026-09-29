{#-
    Prueba de conciliación RAW vs BRONZE.

    Para cada archivo de origen compara cuántas filas hay en RAW y cuántas en
    Bronze. Si algún archivo tiene números distintos (filas perdidas o
    duplicadas), la prueba devuelve ese archivo y falla.
-#}
with raw as (
    select _source_file, count(*) as filas_raw
    from {{ source('raw', 'yellow_trips') }}
    group by 1
),

bronze as (
    select _source_file, count(*) as filas_bronze
    from {{ ref('bronze_yellow_trips') }}
    group by 1
)

select
    coalesce(raw._source_file, bronze._source_file) as _source_file,
    raw.filas_raw,
    bronze.filas_bronze
from raw
full outer join bronze
    on raw._source_file = bronze._source_file
where raw.filas_raw is distinct from bronze.filas_bronze
