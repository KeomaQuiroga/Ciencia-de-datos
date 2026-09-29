{#-
    GOLD - Dimensión de hora del día.

    Grano: una hora del día (0 a 23). PK: time_key.
    Permite analizar los viajes por hora y por franja del día.
    Se usa dos veces desde la tabla de hechos: hora de salida y de llegada.
-#}
with horas as (

    select row_number() over (order by seq4()) - 1 as hora
    from table(generator(rowcount => 24))

)

select
    hora                                        as time_key,
    hora                                        as hour_of_day,
    lpad(hora::varchar, 2, '0') || ':00'        as hour_label,
    case
        when hora < 6  then 'Madrugada'
        when hora < 12 then 'Mañana'
        when hora < 18 then 'Tarde'
        else 'Noche'
    end                                         as day_period
from horas
