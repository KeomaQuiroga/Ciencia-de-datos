# Decisiones de limpieza (capa Silver)

Cada regla de Silver se decidió a partir del perfilado de Bronze
(`analisis/01_perfilado_bronze.sql`, consultas Q1 a Q8) y del diccionario de
datos oficial de TLC (*Yellow Trips Data Dictionary*, 18 de marzo de 2025).

Base: **75,089,241 filas** en Bronze (enero 2025 a julio 2026; agosto 2026 aún
no publicado por TLC).

## Principios

1. **Nada se borra.** Una fila que no representa un viaje válido no pasa a
   `silver_yellow_trips`; va a la cuarentena `silver_yellow_trips_rejected`
   con su motivo (`rejection_reason`). Una prueba verifica que
   Bronze = Silver + rechazados.
2. **Si el viaje es real pero un campo es imposible, se corrige el campo, no se
   descarta el viaje.** El valor pasa a `NULL` (desconocido).
3. **No se inventan datos.** Un valor faltante queda en `NULL`; no se imputa
   con ceros ni promedios. `SUM` y `AVG` ignoran los `NULL`.
4. **Reglas deterministas.** Silver se reconstruye completo en cada ejecución y
   siempre produce el mismo resultado (idempotente).

## Hallazgos y decisiones

### Tipos de datos y nombres (consistencia)

| Hallazgo | Decisión | Justificación |
|---|---|---|
| Nombres mezclados en la fuente: `VendorID`, `PULocationID`, `tpep_pickup_datetime`, `Airport_fee` | Renombrar a `snake_case` descriptivo: `vendor_id`, `pickup_location_id`, `pickup_datetime`, `airport_fee_amount` | Un solo estilo de nombres en todo el modelo |
| Montos y distancia en `FLOAT` | `NUMBER(18,2)` | El dinero no debe tener errores de redondeo de punto flotante |
| `store_and_fwd_flag` con 'Y'/'N' | Booleano `is_store_and_forward` | Tipo acorde al significado |

### Valores nulos (completitud)

| Hallazgo (Q1, Q2) | Filas | Decisión | Justificación |
|---|---:|---|---|
| Nulos simultáneos en `passenger_count`, `RatecodeID`, `store_and_fwd_flag`, `congestion_surcharge` y `Airport_fee` | 18,407,401 (24.5%) | Se conservan los viajes. `rate_code_id` nulo pasa a **99**; los demás quedan en `NULL` | Son exactamente los viajes con `payment_type = 0` ("Flex Fare", precio acordado por adelantado según el diccionario), donde esos campos no se reportan. 99 es el código que TLC define como "Null/unknown" |
| Sin nulos en proveedor, fechas, ubicaciones, forma de pago ni `cbd_congestion_fee` | 0 | Sin cambios | — |

### Registros inválidos (validez / exactitud)

| Hallazgo (Q1, Q6, Q8) | Filas | Decisión | Justificación |
|---|---:|---|---|
| Total negativo | 1,121,063 | Cuarentena: `reverso_monto_negativo` | 100% del proveedor 2 (Curb) y concentrados en disputas, efectivo y "no charge". Q7: 849,359 son pares "viaje original + copia con montos negativos que suman 0". Son **reversos** (anulaciones), no viajes nuevos |
| Tarifa negativa con total ≥ 0 | 1,879,991 | Cuarentena: `tarifa_negativa` | La tarifa es "el cargo por tiempo y distancia del taxímetro" y no puede ser negativa. Casi todas son del proveedor 2 con Flex Fare, con total mediano de **$3.75**, frente a $22.00 de un viaje normal: son ajustes, no el cobro de un viaje |
| Llegada antes de la salida | 2,242 | Cuarentena: `llegada_antes_de_salida` | Imposible en el tiempo |
| Duración mayor a 24 h | 572 | Cuarentena: `duracion_mayor_24h` | Taxímetro olvidado encendido |
| Salida fuera del mes del archivo | 345 | Cuarentena: `fuera_del_periodo_del_archivo` | Fechas erróneas (por ejemplo 2008). Además evita que un viaje aparezca en dos archivos |
| Duración 0 **y** distancia 0 | 23,557 | Cuarentena: `sin_movimiento` | Sin tiempo ni desplazamiento no hay viaje que analizar |
| Distancia mayor a 200 millas | 2,889 | Cuarentena: `distancia_mayor_200_millas` | Imposible para un taxi urbano: error del odómetro |
| Total mayor a $1,000 | 124 | Cuarentena: `total_mayor_1000` | Monto implausible para un viaje en taxi |
| Duración 0 con distancia > 0 | 849,003 | Se conserva el viaje; `trip_duration_minutes` = `NULL` | Tienen distancia y cobro normales (total mediano $20.60): el viaje ocurrió, solo falta la hora de llegada |
| Distancia 0 con duración > 0 | 2,212,573 | Se conserva el viaje; `trip_distance_miles` = `NULL` | Total mediano $23.54, igual que un viaje normal: la distancia no se registró |
| Pasajeros = 0 o > 6 | 343,943 + 170 | Se conserva el viaje; `passenger_count` = `NULL` | Un viaje no tiene 0 pasajeros, y más de 6 excede la capacidad de un taxi |
| Total = 0 | 10,725 | Se conservan | Son viajes válidos sin cobro ("no charge") |

### Duplicados (unicidad)

Clave del viaje (`trip_id`): proveedor + fecha y hora de salida + fecha y hora
de llegada + zona de origen + zona de destino.

| Hallazgo (Q3, Q7) | Grupos | Decisión | Justificación |
|---|---:|---|---|
| Duplicados exactos | 1 | Se conserva una fila | Unicidad |
| Pares original + reverso | 849,359 | El reverso va a cuarentena; el original se conserva con `has_reversal = TRUE` | El viaje sí ocurrió, pero su cobro se anuló. La marca permite excluirlo de los análisis de ingresos |
| Misma clave, sin negativos (mismo o distinto monto), más los grupos mixtos | 74,628 + 3,778 | Se conserva una fila por viaje; las demás van a cuarentena como `duplicado` | Mismo proveedor, mismos segundos de salida y llegada y mismas zonas: es el mismo viaje reportado dos veces. Criterio determinista: se conserva la de mayor total (la más completa, por ejemplo con propina) y, si empatan, la cargada más recientemente |
| Mismo viaje en dos archivos | 2 | Igual que el anterior | La deduplicación se hace sobre todos los archivos a la vez |

### Integridad referencial y catálogos (consistencia)

| Hallazgo (Q2, Q4, Q5) | Decisión | Justificación |
|---|---|---|
| Todos los códigos de proveedor (1, 2, 6, 7), tarifa (1–6, 99) y pago (0–5) existen en el diccionario | Catálogos como seeds de dbt (`ref_vendors`, `ref_rate_codes`, `ref_payment_types`) con pruebas `relationships` | Descripciones oficiales y control de que no aparezcan códigos nuevos sin catalogar |
| Todas las zonas de los viajes existen en el catálogo (Q4 vacío) | Prueba `relationships` contra `silver_taxi_zones` | Si mañana llega una zona desconocida, la prueba lo detecta |
| Zonas 264 y 265 con campos vacíos | Se rellenan con "Unknown" y "Outside of NYC" (`service_zone` = "N/A") y se marcan con `is_identified_zone = FALSE` | Son zonas especiales de TLC usadas en viajes reales; así ningún viaje queda con barrio `NULL` |

## Cómo verificarlo

Filas por motivo de rechazo:

```sql
SELECT rejection_reason, COUNT(*) AS filas
FROM NYC_TAXI.SILVER.SILVER_YELLOW_TRIPS_REJECTED
GROUP BY 1
ORDER BY 2 DESC;
```

Pruebas de dbt que respaldan estas reglas:

- `assert_silver_cuadra_con_bronze`: Bronze = Silver + rechazados.
- `assert_silver_cumple_reglas`: ninguna fila de Silver incumple una regla.
- `unique` y `not_null` de `trip_id`.
- `relationships` de proveedor, tarifa, pago y zonas.
