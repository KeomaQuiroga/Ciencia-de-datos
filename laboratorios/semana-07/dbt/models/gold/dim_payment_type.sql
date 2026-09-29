{#-
    GOLD - Dimensión de formas de pago.
    Grano: una forma de pago. PK: payment_type_key (código oficial de TLC).
-#}
select
    payment_type_id         as payment_type_key,
    payment_type_name,
    case payment_type_id
        when 0 then 'Flex Fare'
        when 1 then 'Tarjeta'
        when 2 then 'Efectivo'
        else 'Sin cobro, disputa u otro'
    end                     as payment_group
from {{ ref('ref_payment_types') }}
