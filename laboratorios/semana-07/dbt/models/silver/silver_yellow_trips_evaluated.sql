{#-
    SILVER (paso 1 de 2): todos los viajes de Bronze, estandarizados y evaluados.

    Contiene TODAS las filas de Bronze (ninguna se pierde) con:
      - nombres en snake_case y tipos correctos (dinero en NUMBER, no FLOAT)
      - trip_id: identificador del viaje (proveedor + salida + llegada + origen + destino)
      - rejection_reason: por qué la fila NO pasa a Silver (NULL = fila válida)
      - has_reversal: el viaje tiene un reverso (anulación con montos negativos)

    A partir de esta tabla:
      silver_yellow_trips          = filas con rejection_reason NULL (+ correcciones)
      silver_yellow_trips_rejected = filas con rejection_reason (cuarentena)

    Las reglas y su justificación están en docs/decisiones_de_limpieza.md.
    Se reconstruye completa en cada ejecución: es determinista, así que
    re-ejecutar produce exactamente el mismo resultado.
-#}
{{ config(materialized = 'table') }}

with bronze as (

    select * from {{ ref('bronze_yellow_trips') }}

),

-- 1) Nombres y tipos estandarizados (los valores todavía no se corrigen)
tipado as (

    select
        vendorid::integer                               as vendor_id,
        tpep_pickup_datetime                            as pickup_datetime,
        tpep_dropoff_datetime                           as dropoff_datetime,
        datediff('second', tpep_pickup_datetime,
                           tpep_dropoff_datetime)       as duration_seconds,
        passenger_count::integer                        as passenger_count,
        trip_distance::number(18, 2)                    as trip_distance_miles,
        ratecodeid::integer                             as rate_code_id,
        case upper(trim(store_and_fwd_flag))
            when 'Y' then true
            when 'N' then false
        end                                             as is_store_and_forward,
        pulocationid::integer                           as pickup_location_id,
        dolocationid::integer                           as dropoff_location_id,
        payment_type::integer                           as payment_type_id,
        fare_amount::number(18, 2)                      as fare_amount,
        extra::number(18, 2)                            as extra_amount,
        mta_tax::number(18, 2)                          as mta_tax_amount,
        tip_amount::number(18, 2)                       as tip_amount,
        tolls_amount::number(18, 2)                     as tolls_amount,
        improvement_surcharge::number(18, 2)            as improvement_surcharge_amount,
        congestion_surcharge::number(18, 2)             as congestion_surcharge_amount,
        airport_fee::number(18, 2)                      as airport_fee_amount,
        cbd_congestion_fee::number(18, 2)               as cbd_congestion_fee_amount,
        total_amount::number(18, 2)                     as total_amount,
        _source_file,
        _source_period,
        _loaded_at
    from bronze

),

-- 2) Identificador del viaje y reglas de validez (la primera que se incumple)
evaluado as (

    select
        md5(concat_ws('|',
            vendor_id::varchar,
            to_varchar(pickup_datetime, 'YYYY-MM-DD HH24:MI:SS'),
            to_varchar(dropoff_datetime, 'YYYY-MM-DD HH24:MI:SS'),
            pickup_location_id::varchar,
            dropoff_location_id::varchar
        ))                                                          as trip_id,
        *,
        case
            when total_amount < 0                                   then 'reverso_monto_negativo'
            when fare_amount < 0                                    then 'tarifa_negativa'
            when dropoff_datetime < pickup_datetime                 then 'llegada_antes_de_salida'
            when duration_seconds > 24 * 60 * 60                    then 'duracion_mayor_24h'
            when date_trunc('month', pickup_datetime)::date
                 <> _source_period                                  then 'fuera_del_periodo_del_archivo'
            when duration_seconds = 0 and trip_distance_miles = 0   then 'sin_movimiento'
            when trip_distance_miles > 200                          then 'distancia_mayor_200_millas'
            when total_amount > 1000                                then 'total_mayor_1000'
        end                                                         as regla_incumplida,
        -- Huella de la fila completa: desempate final para que la
        -- deduplicación sea siempre la misma en cada ejecución
        hash(*)                                                     as fila_hash
    from tipado

),

-- 3) Duplicados: entre las filas válidas con el mismo trip_id se conserva una
deduplicado as (

    select
        *,
        row_number() over (
            partition by trip_id, (regla_incumplida is null)
            order by total_amount desc, _loaded_at desc, _source_file, fila_hash
        )                                                           as orden_duplicado,
        max(iff(total_amount < 0, 1, 0)) over (partition by trip_id) = 1
                                                                    as has_reversal
    from evaluado

)

select
    trip_id,
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    duration_seconds,
    passenger_count,
    trip_distance_miles,
    rate_code_id,
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
    case
        when regla_incumplida is not null then regla_incumplida
        when orden_duplicado > 1          then 'duplicado'
    end                                                             as rejection_reason,
    _source_file,
    _source_period,
    _loaded_at,
    current_timestamp()                                             as _silver_loaded_at
from deduplicado
