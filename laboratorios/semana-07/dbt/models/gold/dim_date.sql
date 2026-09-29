{#-
    GOLD - Dimensión de fechas (calendario).

    Grano: un día. PK: date_key (AAAAMMDD).
    Se genera un día por fila, desde la primera salida hasta la última
    llegada de los viajes, así cubre siempre todo el rango de datos.
    Se usa dos veces desde la tabla de hechos: fecha de salida y de llegada.
-#}
with limites as (

    select
        min(pickup_datetime)::date  as fecha_min,
        max(dropoff_datetime)::date as fecha_max
    from {{ ref('silver_yellow_trips') }}

),

numeros as (

    -- 0, 1, 2, ... (10,000 días alcanzan para más de 27 años)
    select row_number() over (order by seq4()) - 1 as n
    from table(generator(rowcount => 10000))

),

dias as (

    select dateadd('day', numeros.n, limites.fecha_min) as fecha
    from numeros
    cross join limites
    where dateadd('day', numeros.n, limites.fecha_min) <= limites.fecha_max

)

select
    {{ date_key('fecha') }}                     as date_key,
    fecha                                       as full_date,
    year(fecha)                                 as year,
    quarter(fecha)                              as quarter,
    month(fecha)                                as month,
    decode(month(fecha),
        1, 'Enero', 2, 'Febrero', 3, 'Marzo', 4, 'Abril',
        5, 'Mayo', 6, 'Junio', 7, 'Julio', 8, 'Agosto',
        9, 'Septiembre', 10, 'Octubre', 11, 'Noviembre', 12, 'Diciembre')
                                                as month_name,
    to_char(fecha, 'YYYY-MM')                   as year_month,
    day(fecha)                                  as day_of_month,
    dayofweekiso(fecha)                         as day_of_week,
    decode(dayofweekiso(fecha),
        1, 'Lunes', 2, 'Martes', 3, 'Miércoles', 4, 'Jueves',
        5, 'Viernes', 6, 'Sábado', 7, 'Domingo')
                                                as day_name,
    weekiso(fecha)                              as iso_week,
    dayofweekiso(fecha) in (6, 7)               as is_weekend
from dias
