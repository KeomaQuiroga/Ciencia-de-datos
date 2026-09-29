{#-
    GOLD - Dimensión de proveedores tecnológicos (TPEP).
    Grano: un proveedor. PK: vendor_key (código oficial de TLC).
-#}
select
    vendor_id       as vendor_key,
    vendor_name
from {{ ref('ref_vendors') }}
