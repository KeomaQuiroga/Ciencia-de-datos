{#-
    Validez de SILVER: ningún viaje limpio puede incumplir las reglas de
    calidad. Devuelve (y hace fallar la prueba) cualquier fila que las rompa.
-#}
select
    trip_id,
    pickup_datetime,
    dropoff_datetime,
    trip_distance_miles,
    passenger_count,
    fare_amount,
    total_amount
from {{ ref('silver_yellow_trips') }}
where total_amount < 0
   or fare_amount < 0
   or total_amount > 1000
   or dropoff_datetime < pickup_datetime
   or datediff('second', pickup_datetime, dropoff_datetime) > 24 * 60 * 60
   or date_trunc('month', pickup_datetime)::date <> _source_period
   or trip_distance_miles <= 0
   or trip_distance_miles > 200
   or trip_duration_minutes <= 0
   or passenger_count not between 1 and 6
