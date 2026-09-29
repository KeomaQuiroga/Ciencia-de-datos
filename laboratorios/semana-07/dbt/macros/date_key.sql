{#-
    Convierte una fecha u hora en la llave de dim_date con formato AAAAMMDD
    (por ejemplo 2025-01-15 08:30 -> 20250115). Se usa en dim_date y en
    fct_trips para que ambas calculen la llave exactamente igual.
-#}
{% macro date_key(columna) -%}
    (year({{ columna }}) * 10000 + month({{ columna }}) * 100 + day({{ columna }}))
{%- endmacro %}