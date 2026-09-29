{#-
    SILVER: catálogo de zonas limpio.

    Las zonas 264 y 265 son zonas especiales de TLC (desconocida y fuera de
    NYC) y vienen con campos vacíos. Se rellenan con etiquetas explícitas
    para que ningún viaje quede con barrio o zona NULL, y se marcan con
    is_identified_zone = FALSE para poder filtrarlas en los análisis.
-#}
{{ config(materialized = 'table') }}

with zonas as (

    select
        locationid::integer                 as location_id,
        nullif(trim(borough), '')           as borough,
        nullif(trim(zone), '')              as zone_name,
        nullif(trim(service_zone), '')      as service_zone,
        _source_file,
        _loaded_at
    from {{ ref('bronze_taxi_zones') }}

)

select
    location_id,
    coalesce(borough,
             iff(location_id = 265, 'Outside of NYC', 'Unknown'))    as borough,
    coalesce(zone_name,
             iff(location_id = 265, 'Outside of NYC', 'Unknown'))    as zone_name,
    coalesce(service_zone, 'N/A')                                    as service_zone,
    location_id not in (264, 265)                                    as is_identified_zone,
    _source_file,
    _loaded_at
from zonas
