{#-
    GOLD - Tabla de hechos de viajes.

    Grano: un viaje de taxi válido y sin duplicados (una fila por trip_id).
    Llaves foráneas hacia cada dimensión (fecha y hora de salida y llegada,
    zona de origen y destino, proveedor, tarifa y forma de pago).
    Métricas: pasajeros, distancia, duración y cada componente del cobro.
-#}
select
    -- Llave primaria (identificador del viaje)
    trip_id,

    -- Llaves foráneas
    {{ date_key('pickup_datetime') }}       as pickup_date_key,
    hour(pickup_datetime)                   as pickup_time_key,
    {{ date_key('dropoff_datetime') }}      as dropoff_date_key,
    hour(dropoff_datetime)                  as dropoff_time_key,
    pickup_location_id                      as pickup_zone_key,
    dropoff_location_id                     as dropoff_zone_key,
    vendor_id                               as vendor_key,
    rate_code_id                            as rate_code_key,
    payment_type_id                         as payment_type_key,

    -- Atributos del viaje
    pickup_datetime,
    dropoff_datetime,
    is_store_and_forward,
    has_reversal,

    -- Métricas
    passenger_count,
    trip_distance_miles,
    trip_duration_minutes,
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

    -- Linaje
    _source_file,
    _source_period
from {{ ref('silver_yellow_trips') }}
