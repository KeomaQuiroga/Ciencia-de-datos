{#-
    SILVER: viajes limpios, válidos y sin duplicados.

    Grano: un viaje (trip_id único).
    Toma las filas válidas de silver_yellow_trips_evaluated y corrige los
    valores puntuales que son imposibles, sin descartar el viaje:
      - passenger_count fuera de 1..6        -> NULL (dato desconocido)
      - trip_distance_miles = 0              -> NULL (distancia no registrada)
      - duración = 0 segundos                -> NULL (hora de llegada no registrada)
      - rate_code_id NULL (viajes Flex Fare) -> 99 (código "Null/unknown" de TLC)
-#}
{{ config(materialized = 'table') }}

select
    trip_id,
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    iff(duration_seconds > 0, duration_seconds / 60, null)::number(18, 2)  as trip_duration_minutes,
    iff(passenger_count between 1 and 6, passenger_count, null)            as passenger_count,
    nullif(trip_distance_miles, 0)                                         as trip_distance_miles,
    coalesce(rate_code_id, 99)                                             as rate_code_id,
    is_store_and_forward,
    pickup_location_id,
    dropoff_location_id,
    payment_type_id,
    fare_amount,
    extra_amount,
    mta_tax_amount,
    tip_amount,
    tolls_amount,
    improvement_surcharge_amount,
    congestion_surcharge_amount,
    airport_fee_amount,
    cbd_congestion_fee_amount,
    total_amount,
    has_reversal,
    _source_file,
    _source_period,
    _loaded_at,
    _silver_loaded_at
from {{ ref('silver_yellow_trips_evaluated') }}
where rejection_reason is null
