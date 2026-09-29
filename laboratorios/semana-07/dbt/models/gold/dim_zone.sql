{#-
    GOLD - Dimensión de zonas de taxi.

    Grano: una zona de TLC. PK: zone_key (el LocationID oficial de TLC).
    Se usa dos veces desde la tabla de hechos: zona de origen y de destino.
-#}
select
    location_id                             as zone_key,
    borough,
    zone_name,
    service_zone,
    service_zone in ('Airports', 'EWR')     as is_airport,
    is_identified_zone
from {{ ref('silver_taxi_zones') }}
