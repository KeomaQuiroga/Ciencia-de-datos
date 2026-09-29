-- =====================================================================
-- 99_reset_pipeline.sql
--
-- QUÉ HACE:  borra TODO lo que crea el pipeline (esquemas RAW, BRONZE,
--            SILVER y GOLD con sus tablas, stages y datos), para probar
--            que la tubería se levanta desde cero.
-- QUÉ NO BORRA: el rol, el warehouse, la base de datos ni el usuario de
--            servicio (los crea 00_bootstrap_admin.sql una sola vez).
-- QUIÉN:     tú, en Snowsight, con el rol SYSADMIN.
--
-- Después de ejecutarlo, basta con ejecutar el flujo pipeline_nyc_taxi en
-- Kestra: vuelve a crear los esquemas, descarga los archivos y reconstruye
-- todas las capas.
-- =====================================================================
USE ROLE SYSADMIN;

DROP SCHEMA IF EXISTS NYC_TAXI.GOLD;
DROP SCHEMA IF EXISTS NYC_TAXI.SILVER;
DROP SCHEMA IF EXISTS NYC_TAXI.BRONZE;
DROP SCHEMA IF EXISTS NYC_TAXI.RAW;

-- Solo deben quedar INFORMATION_SCHEMA y PUBLIC
SHOW SCHEMAS IN DATABASE NYC_TAXI;
