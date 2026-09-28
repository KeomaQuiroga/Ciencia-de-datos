-- =====================================================================
-- 00_bootstrap_admin.sql
--
-- QUÉ HACE:  prepara Snowflake para el pipeline (rol, warehouse,
--            base de datos y un usuario de servicio que entra con llave).
-- QUIÉN:     una persona con el rol ACCOUNTADMIN, en Snowsight.
-- CUÁNDO:    una sola vez, antes de ejecutar el pipeline.
--
-- Es idempotente: si lo ejecutas de nuevo no duplica ni rompe nada.
-- Los esquemas (RAW, BRONZE, SILVER, GOLD) NO se crean aquí: los crea
-- el propio pipeline, para que se pueda levantar desde cero.
--
-- IMPORTANTE: no pegues este archivo tal cual. Ejecuta primero
-- scripts/generar_llaves.sh, que genera keys/00_bootstrap_listo.sql con
-- tu llave pública ya insertada en lugar de __RSA_PUBLIC_KEY__.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) Rol del pipeline
--    Todo lo que hagan la ingesta y dbt se hará con este rol, así no
--    usamos ACCOUNTADMIN para el trabajo diario.
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS NYC_TAXI_ROLE
    COMMENT = 'Rol del pipeline ELT NYC Yellow Taxi (ingesta + dbt)';

-- Buena práctica: los roles propios cuelgan de SYSADMIN. Así, cuando tú
-- entres a Snowsight con SYSADMIN, podrás ver todo lo que cree el pipeline.
GRANT ROLE NYC_TAXI_ROLE TO ROLE SYSADMIN;


-- ---------------------------------------------------------------------
-- 2) Warehouse: el "motor" que ejecuta las consultas y gasta créditos.
--    XSMALL es el tamaño más pequeño y alcanza para este lab.
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS NYC_TAXI_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60      -- se apaga tras 60 s sin uso (ahorra créditos)
    AUTO_RESUME         = TRUE    -- se enciende solo cuando llega una consulta
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse del lab NYC Yellow Taxi';


-- ---------------------------------------------------------------------
-- 3) Base de datos
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS NYC_TAXI
    COMMENT = 'Lab integrador 1 - NYC Yellow Taxi (Bronze / Silver / Gold)';


-- ---------------------------------------------------------------------
-- 4) Permisos del rol del pipeline
--    - USAGE en el warehouse: puede usarlo para ejecutar consultas.
--    - USAGE + CREATE SCHEMA en la base: puede crear sus propios
--      esquemas, y como dueño de ellos podrá crear tablas, vistas, etc.
-- ---------------------------------------------------------------------
GRANT USAGE ON WAREHOUSE NYC_TAXI_WH TO ROLE NYC_TAXI_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE NYC_TAXI TO ROLE NYC_TAXI_ROLE;


-- ---------------------------------------------------------------------
-- 5) Usuario de servicio
--    TYPE = SERVICE: es un usuario para programas (Kestra, dbt), no para
--    personas. No tiene contraseña: se autentica con una llave RSA.
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

CREATE USER IF NOT EXISTS NYC_TAXI_SVC
    TYPE              = SERVICE
    DEFAULT_ROLE      = NYC_TAXI_ROLE
    DEFAULT_WAREHOUSE = NYC_TAXI_WH
    DEFAULT_NAMESPACE = NYC_TAXI
    COMMENT = 'Usuario de servicio para Kestra y dbt (key-pair)';

-- La llave va en un ALTER aparte: si algún día regeneras las llaves,
-- basta con volver a ejecutar este script.
ALTER USER NYC_TAXI_SVC SET RSA_PUBLIC_KEY = '__RSA_PUBLIC_KEY__';

GRANT ROLE NYC_TAXI_ROLE TO USER NYC_TAXI_SVC;


-- ---------------------------------------------------------------------
-- 6) Verificación: busca la fila RSA_PUBLIC_KEY_FP; debe tener un valor
--    que empieza con "SHA256:".
-- ---------------------------------------------------------------------
DESC USER NYC_TAXI_SVC;