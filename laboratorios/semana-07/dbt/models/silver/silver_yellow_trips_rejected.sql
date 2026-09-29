{#-
    SILVER: cuarentena. Filas de Bronze que no pasaron a silver_yellow_trips,
    con sus valores originales (solo renombrados y tipados) y el motivo.
    Nada se borra: aquí se puede auditar cada exclusión.
-#}
{{ config(materialized = 'view') }}

select *
from {{ ref('silver_yellow_trips_evaluated') }}
where rejection_reason is not null
