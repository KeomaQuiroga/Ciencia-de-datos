{#-
    BRONZE: catálogo de zonas tal como viene en taxi_zone_lookup.csv,
    más la metadata de origen y carga. Es una tabla pequeña (265 filas),
    así que se reconstruye completa en cada ejecución.
-#}
{{ config(materialized = 'table') }}

select
    locationid,
    borough,
    zone,
    service_zone,

    _source_file,
    _loaded_at,
    current_timestamp() as _bronze_loaded_at

from {{ source('raw', 'taxi_zones') }}
