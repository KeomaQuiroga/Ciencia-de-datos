-- =====================================================================
-- 01_perfilado_bronze.sql
--
-- Perfilado de calidad de datos de la capa Bronze. Sus resultados son la
-- evidencia que justifica cada regla de limpieza de la capa Silver
-- (se citan en el README).
--
-- Ejecútalo en Snowsight con el rol SYSADMIN, UNA CONSULTA A LA VEZ:
-- pon el cursor dentro de la consulta y presiona Ctrl+Enter.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q1. Completitud y validez: nulos, valores fuera de rango, fechas raras
--     (devuelve una sola fila)
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                         AS total_filas,

    -- Nulos
    COUNT_IF(vendorid IS NULL)                                       AS nulos_vendorid,
    COUNT_IF(tpep_pickup_datetime IS NULL
          OR tpep_dropoff_datetime IS NULL)                          AS nulos_fechas,
    COUNT_IF(passenger_count IS NULL)                                AS nulos_passenger_count,
    COUNT_IF(ratecodeid IS NULL)                                     AS nulos_ratecodeid,
    COUNT_IF(store_and_fwd_flag IS NULL)                             AS nulos_store_and_fwd_flag,
    COUNT_IF(payment_type IS NULL)                                   AS nulos_payment_type,
    COUNT_IF(pulocationid IS NULL OR dolocationid IS NULL)           AS nulos_ubicaciones,
    COUNT_IF(congestion_surcharge IS NULL)                           AS nulos_congestion_surcharge,
    COUNT_IF(airport_fee IS NULL)                                    AS nulos_airport_fee,
    COUNT_IF(cbd_congestion_fee IS NULL)                             AS nulos_cbd_congestion_fee,

    -- Tiempo
    COUNT_IF(tpep_dropoff_datetime < tpep_pickup_datetime)           AS llegada_antes_de_salida,
    COUNT_IF(tpep_dropoff_datetime = tpep_pickup_datetime)           AS duracion_cero,
    COUNT_IF(DATEDIFF('minute', tpep_pickup_datetime,
                      tpep_dropoff_datetime) > 24 * 60)              AS duracion_mas_24h,
    COUNT_IF(DATE_TRUNC('month', tpep_pickup_datetime)
             <> _source_period)                                      AS fuera_del_mes_del_archivo,

    -- Distancia
    COUNT_IF(trip_distance < 0)                                      AS distancia_negativa,
    COUNT_IF(trip_distance = 0)                                      AS distancia_cero,
    COUNT_IF(trip_distance > 200)                                    AS distancia_mas_200_millas,

    -- Montos
    COUNT_IF(fare_amount < 0)                                        AS tarifa_negativa,
    COUNT_IF(total_amount < 0)                                       AS total_negativo,
    COUNT_IF(total_amount = 0)                                       AS total_cero,
    COUNT_IF(total_amount > 1000)                                    AS total_mas_1000,

    -- Pasajeros
    COUNT_IF(passenger_count = 0)                                    AS pasajeros_cero,
    COUNT_IF(passenger_count > 6)                                    AS pasajeros_mas_6
FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS;


-- ---------------------------------------------------------------------
-- Q2. Consistencia de columnas categóricas: qué códigos aparecen y
--     cuántas filas tienen total negativo en cada uno
-- ---------------------------------------------------------------------
WITH t AS (SELECT * FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS)
SELECT 'vendorid' AS columna, TO_VARCHAR(vendorid) AS valor,
       COUNT(*) AS filas, COUNT_IF(total_amount < 0) AS filas_total_negativo
FROM t GROUP BY 1, 2
UNION ALL
SELECT 'ratecodeid', TO_VARCHAR(ratecodeid), COUNT(*), COUNT_IF(total_amount < 0)
FROM t GROUP BY 1, 2
UNION ALL
SELECT 'payment_type', TO_VARCHAR(payment_type), COUNT(*), COUNT_IF(total_amount < 0)
FROM t GROUP BY 1, 2
UNION ALL
SELECT 'store_and_fwd_flag', store_and_fwd_flag, COUNT(*), COUNT_IF(total_amount < 0)
FROM t GROUP BY 1, 2
UNION ALL
SELECT 'passenger_count', TO_VARCHAR(passenger_count), COUNT(*), COUNT_IF(total_amount < 0)
FROM t GROUP BY 1, 2
ORDER BY columna, filas DESC;


-- ---------------------------------------------------------------------
-- Q3. Unicidad: duplicados
--   exactos       -> todas las columnas del viaje iguales
--   por clave     -> mismo proveedor, salida, llegada, origen y destino
--   entre archivos-> el mismo viaje (por clave) en más de un archivo
-- ---------------------------------------------------------------------
WITH exactos AS (
    SELECT vendorid, tpep_pickup_datetime, tpep_dropoff_datetime, passenger_count,
           trip_distance, ratecodeid, store_and_fwd_flag, pulocationid, dolocationid,
           payment_type, fare_amount, extra, mta_tax, tip_amount, tolls_amount,
           improvement_surcharge, total_amount, congestion_surcharge, airport_fee,
           cbd_congestion_fee,
           COUNT(*) AS n
    FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS
    GROUP BY ALL
    HAVING COUNT(*) > 1
),
por_clave AS (
    SELECT vendorid, tpep_pickup_datetime, tpep_dropoff_datetime,
           pulocationid, dolocationid,
           COUNT(*) AS n,
           COUNT(DISTINCT _source_file) AS archivos
    FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS
    GROUP BY ALL
    HAVING COUNT(*) > 1
)
SELECT 'exactos' AS tipo, COUNT(*) AS grupos, SUM(n - 1) AS filas_sobrantes FROM exactos
UNION ALL
SELECT 'por_clave', COUNT(*), SUM(n - 1) FROM por_clave
UNION ALL
SELECT 'por_clave_entre_archivos', COUNT_IF(archivos > 1),
       SUM(IFF(archivos > 1, n - 1, 0)) FROM por_clave;


-- ---------------------------------------------------------------------
-- Q4. Integridad referencial: zonas de los viajes que no existen en el
--     catálogo de zonas
-- ---------------------------------------------------------------------
SELECT 'pickup' AS tipo, t.pulocationid AS locationid, COUNT(*) AS filas
FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS t
LEFT JOIN NYC_TAXI.BRONZE.BRONZE_TAXI_ZONES z ON t.pulocationid = z.locationid
WHERE z.locationid IS NULL
GROUP BY 1, 2
UNION ALL
SELECT 'dropoff', t.dolocationid, COUNT(*)
FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS t
LEFT JOIN NYC_TAXI.BRONZE.BRONZE_TAXI_ZONES z ON t.dolocationid = z.locationid
WHERE z.locationid IS NULL
GROUP BY 1, 2
ORDER BY filas DESC;


-- ---------------------------------------------------------------------
-- Q5. Catálogo de zonas: filas especiales o incompletas
-- ---------------------------------------------------------------------
SELECT locationid, borough, zone, service_zone
FROM NYC_TAXI.BRONZE.BRONZE_TAXI_ZONES
WHERE locationid >= 264
   OR borough IS NULL OR zone IS NULL OR service_zone IS NULL
   OR borough IN ('Unknown', 'N/A') OR zone IN ('Unknown', 'N/A')
ORDER BY locationid;


-- =====================================================================
-- Segunda ronda: diagnóstico de los hallazgos de Q1-Q3
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q6. Montos negativos: ¿en qué proveedor y forma de pago aparecen, y
--     vienen negativos la tarifa, el total o ambos?
-- ---------------------------------------------------------------------
SELECT vendorid,
       payment_type,
       COUNT(*)                                          AS filas,
       COUNT_IF(fare_amount < 0 AND total_amount < 0)    AS ambos_negativos,
       COUNT_IF(fare_amount < 0 AND total_amount >= 0)   AS solo_tarifa_negativa,
       COUNT_IF(fare_amount >= 0 AND total_amount < 0)   AS solo_total_negativo,
       ROUND(MEDIAN(IFF(fare_amount < 0 AND total_amount >= 0,
                        total_amount, NULL)), 2)         AS mediana_total_si_tarifa_neg
FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS
GROUP BY 1, 2
ORDER BY 1, 2;


-- ---------------------------------------------------------------------
-- Q7. Duplicados por clave: ¿qué patrón tienen los grupos repetidos?
--   par_original_y_reverso -> un viaje y su anulación (montos que suman 0)
--   sin_negativos_*        -> repetidos donde ninguno es negativo
-- ---------------------------------------------------------------------
WITH g AS (
    SELECT vendorid, tpep_pickup_datetime, tpep_dropoff_datetime,
           pulocationid, dolocationid,
           COUNT(*)                     AS n,
           COUNT_IF(total_amount < 0)   AS negativos,
           COUNT(DISTINCT total_amount) AS montos_distintos,
           SUM(total_amount)            AS suma_total
    FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS
    GROUP BY 1, 2, 3, 4, 5
    HAVING COUNT(*) > 1
)
SELECT CASE
           WHEN n = 2 AND negativos = 1 AND ABS(suma_total) < 0.01 THEN 'par_original_y_reverso'
           WHEN negativos = n                                     THEN 'solo_negativos'
           WHEN negativos = 0 AND montos_distintos = 1            THEN 'sin_negativos_mismo_monto'
           WHEN negativos = 0                                     THEN 'sin_negativos_monto_distinto'
           ELSE 'mixto_otro'
       END              AS patron,
       COUNT(*)         AS grupos,
       SUM(n)           AS filas
FROM g
GROUP BY 1
ORDER BY grupos DESC;


-- ---------------------------------------------------------------------
-- Q8. Duración cero y distancia cero: ¿se dan juntas? ¿tienen cobro?
-- ---------------------------------------------------------------------
SELECT (tpep_dropoff_datetime = tpep_pickup_datetime) AS duracion_cero,
       (trip_distance = 0)                            AS distancia_cero,
       COUNT(*)                                       AS filas,
       COUNT_IF(total_amount > 0)                     AS con_cobro_positivo,
       ROUND(MEDIAN(total_amount), 2)                 AS mediana_total
FROM NYC_TAXI.BRONZE.BRONZE_YELLOW_TRIPS
GROUP BY 1, 2
ORDER BY 1, 2;