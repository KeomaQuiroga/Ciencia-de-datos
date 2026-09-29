{#-
    GOLD - Dimensión de códigos de tarifa.
    Grano: un código de tarifa. PK: rate_code_key (código oficial de TLC).
-#}
select
    rate_code_id            as rate_code_key,
    rate_code_name,
    rate_code_id in (2, 3)  as is_airport_rate     -- JFK y Newark
from {{ ref('ref_rate_codes') }}
