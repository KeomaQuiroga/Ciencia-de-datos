{#-
    Conciliación SILVER vs GOLD: la tabla de hechos debe tener exactamente
    los mismos viajes y el mismo monto total que Silver. Si algo se pierde
    o se duplica al construir Gold, la prueba falla y muestra los números.
-#}
with silver as (
    select count(*) as filas, sum(total_amount) as total
    from {{ ref('silver_yellow_trips') }}
),

gold as (
    select count(*) as filas, sum(total_amount) as total
    from {{ ref('fct_trips') }}
)

select
    silver.filas as filas_silver,
    gold.filas   as filas_gold,
    silver.total as total_silver,
    gold.total   as total_gold
from silver
cross join gold
where silver.filas <> gold.filas
   or silver.total <> gold.total
