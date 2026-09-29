{#-
    Conciliación BRONZE vs SILVER: ninguna fila se pierde ni se inventa.
    Cada fila de Bronze debe terminar en Silver (válida) o en la cuarentena
    (rechazada). Si la suma no cuadra, la prueba falla y muestra los conteos.
-#}
with conteos as (
    select
        (select count(*) from {{ ref('bronze_yellow_trips') }})           as filas_bronze,
        (select count(*) from {{ ref('silver_yellow_trips') }})           as filas_silver,
        (select count(*) from {{ ref('silver_yellow_trips_rejected') }})  as filas_rechazadas
)

select *
from conteos
where filas_bronze <> filas_silver + filas_rechazadas
