{#-
    Por defecto dbt arma el nombre del esquema como <esquema_del_perfil>_<esquema_de_la_carpeta>,
    por ejemplo BRONZE_SILVER. Esta macro lo cambia para que cada capa use
    exactamente el esquema que le dimos: BRONZE, SILVER o GOLD.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
