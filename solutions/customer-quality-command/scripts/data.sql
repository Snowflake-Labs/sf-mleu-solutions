-- =============================================================================
-- Solution: Customer Quality Command (CQC) - data
-- Database: SF_SOLUTIONS
-- Schemas:  CQC_RAW, CQC_STAGING, CQC_ATOMIC, CQC_FEATURE_STORE, CQC_ML, CQC_ANALYTICS, CQC_INSIGHTS, CQC_ACTION, CQC_DOCS
-- Generates synthetic data and builds the STAGING, ATOMIC and FEATURE_STORE layers.
-- Run after setup.sql.
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Synthetic RAW feeds (Python stored procedure; reads CQC_RAW.CQC_CONFIG)
CALL SF_SOLUTIONS.CQC_RAW.SP_GENERATE_RAW();

-- -------------------------------------------------------------------------
-- In-warehouse telematics health and background faults
-- Source: platform/ddl/015_raw_periodic_gen.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_RAW;

-- ---------------------------------------------------------------------------
-- RAW_TELEMATICS_HEALTH — weekly machine health snapshots over each life.
-- ~40.8k machines x weeks-in-service (~7.5M rows). Engine temp / derate ramp
-- up during each machine's [degrade_start_dt, first_failure_dt] window.
-- ---------------------------------------------------------------------------
TRUNCATE TABLE RAW_TELEMATICS_HEALTH;

INSERT INTO RAW_TELEMATICS_HEALTH
    (machine_sn, snapshot_dt, op_hours, fuel_used_l, idle_pct,
     load_factor, avg_engine_temp, peak_engine_temp, derate_events)
WITH weeks AS (
    SELECT SEQ4() AS wk FROM TABLE(GENERATOR(ROWCOUNT => 400))   -- up to ~7.7 yrs
),
spine AS (
    SELECT
        p.machine_sn,
        DATEADD('week', w.wk, p.delivery_dt)                      AS snapshot_dt,
        p.op_hours_per_day,
        p.load_factor,
        p.has_bad_lot,
        p.degrade_start_dt,
        p.first_failure_dt,
        DATEDIFF('day', p.delivery_dt, DATEADD('week', w.wk, p.delivery_dt)) AS days_in
    FROM FAILURE_PROFILE p
    JOIN weeks w
      ON w.wk <= DATEDIFF('week', p.delivery_dt, DATE '2026-07-15')
)
SELECT
    machine_sn,
    snapshot_dt,
    ROUND(op_hours_per_day * days_in, 1)                               AS op_hours,
    ROUND(op_hours_per_day * days_in * UNIFORM(28, 42, RANDOM()), 1)   AS fuel_used_l,
    ROUND(UNIFORM(12, 45, RANDOM()), 2)                            AS idle_pct,
    ROUND(LEAST(0.98, GREATEST(0.15, load_factor + NORMAL(0, 0.05, RANDOM()))), 2) AS load_factor,
    -- degradation ramp (#3): rise toward failure within the degrade window
    ROUND(
        88 + NORMAL(0, 1.8, RANDOM())
        + CASE
            WHEN degrade_start_dt IS NOT NULL
             AND snapshot_dt BETWEEN degrade_start_dt AND first_failure_dt
            THEN 14 * LEAST(1.0, GREATEST(0.0,
                 DATEDIFF('day', degrade_start_dt, snapshot_dt)
                 / NULLIF(DATEDIFF('day', degrade_start_dt, first_failure_dt), 0)))
            ELSE 0 END, 2)                                         AS avg_engine_temp,
    ROUND(
        96 + NORMAL(0, 2.5, RANDOM())
        + CASE
            WHEN degrade_start_dt IS NOT NULL
             AND snapshot_dt BETWEEN degrade_start_dt AND first_failure_dt
            THEN 18 * LEAST(1.0, GREATEST(0.0,
                 DATEDIFF('day', degrade_start_dt, snapshot_dt)
                 / NULLIF(DATEDIFF('day', degrade_start_dt, first_failure_dt), 0)))
            ELSE 0 END, 2)                                         AS peak_engine_temp,
    CASE
        WHEN degrade_start_dt IS NOT NULL
         AND snapshot_dt BETWEEN degrade_start_dt AND first_failure_dt
        THEN CASE WHEN has_bad_lot
                  THEN CAST(UNIFORM(0, 6, RANDOM()) AS NUMBER(6,0))
                  ELSE CAST(UNIFORM(0, 3, RANDOM()) AS NUMBER(6,0)) END
        ELSE CAST(UNIFORM(0, 1, RANDOM()) AS NUMBER(6,0))
    END                                                           AS derate_events
FROM spine
WHERE snapshot_dt <= DATE '2026-07-15';   -- guard weekly-spine overshoot

-- ---------------------------------------------------------------------------
-- Background faults — low-rate, model-agnostic noise so the planted precursor
-- signal is not the ONLY thing in RAW_TELEMATICS_FAULT. Idempotent (BG%).
-- ---------------------------------------------------------------------------
DELETE FROM RAW_TELEMATICS_FAULT WHERE fault_id LIKE 'BG%';

INSERT INTO RAW_TELEMATICS_FAULT
    (fault_id, machine_sn, event_ts, module_id, component_id, fmi, spn, j1939_fmi,
     system_group, severity_lvl, occurrence_cnt, lat, lon)
WITH reps AS (
    SELECT SEQ4() AS r FROM TABLE(GENERATOR(ROWCOUNT => 6))
),
bg AS (
    SELECT
        p.machine_sn,
        p.delivery_dt,
        FLOOR(UNIFORM(0::float, 1::float, RANDOM())
              * DATEDIFF('day', p.delivery_dt, DATE '2026-07-15'))  AS day_off,
        UNIFORM(1, 8, RANDOM()) AS sg_pick
    FROM FAILURE_PROFILE p
    CROSS JOIN reps
    WHERE UNIFORM(0::float, 1::float, RANDOM()) < 0.55              -- ~thinned Poisson
)
SELECT
    'BG' || SEQ8()                                                AS fault_id,
    machine_sn,
    DATEADD('day', day_off, delivery_dt)::TIMESTAMP_NTZ           AS event_ts,
    CAST(UNIFORM(1, 9, RANDOM()) AS NUMBER(6,0))                  AS module_id,
    CAST(UNIFORM(100, 700, RANDOM()) AS NUMBER(6,0))              AS component_id,
    CAST(UNIFORM(1, 12, RANDOM()) AS NUMBER(4,0))                 AS fmi,
    CAST(UNIFORM(190, 2500, RANDOM()) AS NUMBER(8,0))             AS spn,
    CAST(UNIFORM(1, 12, RANDOM()) AS NUMBER(4,0))                 AS j1939_fmi,
    CASE sg_pick WHEN 1 THEN 'Fuel System' WHEN 2 THEN 'Hydraulics'
                 WHEN 3 THEN 'Powertrain'  WHEN 4 THEN 'Engine'
                 WHEN 5 THEN 'Cooling'     WHEN 6 THEN 'Electrical'
                 WHEN 7 THEN 'Undercarriage' ELSE 'Structures' END AS system_group,
    1                                                             AS severity_lvl,   -- background = low
    CAST(UNIFORM(1, 5, RANDOM()) AS NUMBER(8,0))                  AS occurrence_cnt,
    ROUND(UNIFORM(25, 49, RANDOM()), 6)                          AS lat,
    ROUND(UNIFORM(-125, -70, RANDOM()), 6)                       AS lon
FROM bg;

SELECT 'health' AS tbl, COUNT(*) AS row_count FROM RAW_TELEMATICS_HEALTH
UNION ALL
SELECT 'faults_total', COUNT(*) FROM RAW_TELEMATICS_FAULT
UNION ALL
SELECT 'faults_background', COUNT(*) FROM RAW_TELEMATICS_FAULT WHERE fault_id LIKE 'BG%';

-- -------------------------------------------------------------------------
-- STAGING reference and crosswalk seeds
-- Source: platform/ddl/020_staging_ref_seed.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_STAGING;

-- ---------------------------------------------------------------------------
-- REF_SYSTEM_GROUP — canonical machine systems
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_SYSTEM_GROUP (system_group_cd STRING, system_group_name STRING);
INSERT INTO REF_SYSTEM_GROUP VALUES
 ('ENGINE_FUEL','Engine - Fuel System'),('HYDRAULICS','Hydraulics'),
 ('POWERTRAIN','Powertrain'),('ENGINE','Engine'),('ELECTRICAL','Electrical'),
 ('UNDERCARRIAGE','Undercarriage'),('STRUCTURES','Structures'),
 ('OPERATOR_STATION','Operator Station'),('IMPLEMENT','Implement'),
 ('COOLING','Cooling'),('AFTERTREATMENT','Aftertreatment'),
 ('PAINT_COATING','Paint & Coating'),('SOFTWARE_CONTROLS','Software & Controls'),
 ('HVAC','HVAC'),('GENERAL','General');

-- Map RAW system_group name strings -> canonical code
CREATE OR REPLACE TABLE MAP_SYSTEM_GROUP (raw_system_group STRING, system_group_cd STRING);
INSERT INTO MAP_SYSTEM_GROUP VALUES
 ('Fuel System','ENGINE_FUEL'),('Hydraulics','HYDRAULICS'),('Powertrain','POWERTRAIN'),
 ('Engine','ENGINE'),('Cooling','COOLING'),('Electrical','ELECTRICAL'),
 ('Undercarriage','UNDERCARRIAGE'),('Structures','STRUCTURES'),('General','GENERAL');

-- ---------------------------------------------------------------------------
-- REF_FAILURE_MODE — canonical failure modes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_FAILURE_MODE (failure_mode_cd STRING, failure_mode_name STRING);
INSERT INTO REF_FAILURE_MODE VALUES
 ('SUDDEN_SHUTDOWN','Sudden Shutdown'),('POWER_LOSS','Power Loss / Derate'),
 ('FLUID_LEAK','Fluid Leak'),('OVERHEAT','Overheat'),('PREMATURE_WEAR','Premature Wear'),
 ('CRACK_FRACTURE','Crack / Fracture'),('CORROSION','Corrosion'),
 ('ELECTRICAL_FAULT','Electrical Fault'),('SENSOR_FAULT','Sensor Fault'),
 ('SOFTWARE_FAULT','Software Fault'),('NOISE_VIBRATION','Noise / Vibration'),
 ('PAINT_DEFECT','Paint Defect'),('HARD_START','Hard Start'),
 ('CONTAMINATION','Contamination'),('SEAL_FAILURE','Seal Failure');

-- ---------------------------------------------------------------------------
-- REF_MODEL_FAMILY — model -> CED product family
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_MODEL_FAMILY (model STRING, product_family STRING);
INSERT INTO REF_MODEL_FAMILY VALUES
 ('EX-220','Excavator'),('EX-260','Excavator'),
 ('LX-520','Large Excavator'),('LX-740','Large Excavator'),('LX-950','Large Excavator'),
 ('DZ-60','Dozer'),('DZ-80','Dozer'),
 ('WL-150','Wheel Loader'),('WL-170','Wheel Loader'),('WL-190','Wheel Loader'),
 ('MG-14','Motor Grader'),('AT-45','Articulated Truck');

-- ---------------------------------------------------------------------------
-- REF_REGION — region drilldown
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_REGION (region_cd STRING, global_region STRING, us_subregion STRING);
INSERT INTO REF_REGION VALUES
 ('US_SE','NORTH_AMERICA','Southeast'),('US_S_CENTRAL','NORTH_AMERICA','South Central'),
 ('US_MW','NORTH_AMERICA','Midwest'),('US_W','NORTH_AMERICA','West'),
 ('US_NE','NORTH_AMERICA','Northeast'),('CA_W','NORTH_AMERICA','Canada West'),
 ('CA_E','NORTH_AMERICA','Canada East');

-- ---------------------------------------------------------------------------
-- REF_END_MARKET + industry crosswalk
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_END_MARKET (end_market_cd STRING, end_market_name STRING);
INSERT INTO REF_END_MARKET VALUES
 ('INFRASTRUCTURE','Infrastructure'),('NONRES_BUILDING','Non-Residential Building'),
 ('RESIDENTIAL','Residential'),('QUARRY_AGG','Quarry & Aggregates'),('RENTAL','Rental');

CREATE OR REPLACE TABLE MAP_INDUSTRY_END_MARKET (industry STRING, end_market_cd STRING);
INSERT INTO MAP_INDUSTRY_END_MARKET
SELECT 'Infrastructure','INFRASTRUCTURE'
UNION ALL SELECT 'NonResidential','NONRES_BUILDING'
UNION ALL SELECT 'Residential','RESIDENTIAL'
UNION ALL SELECT 'Quarry'||CHR(38)||'Agg','QUARRY_AGG'
UNION ALL SELECT 'Rental','RENTAL';

-- ---------------------------------------------------------------------------
-- REF_SEVERITY — canonical ordinal severity
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_SEVERITY (severity_cd STRING, severity_rank NUMBER(2,0));
INSERT INTO REF_SEVERITY VALUES ('LOW',1),('MED',2),('HIGH',3),('CRITICAL',4);

-- ---------------------------------------------------------------------------
-- MAP_SERVICE_3C — Dealer Service Records (complaint,cause,correction) -> system_group + failure_mode
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE MAP_SERVICE_3C (
    complaint_cd STRING, cause_cd STRING, correction_cd STRING,
    system_group_cd STRING, failure_mode_cd STRING);
INSERT INTO MAP_SERVICE_3C VALUES
 ('LOW_POWER','INJ_DEPOSIT','REPLACE_INJECTOR','ENGINE_FUEL','POWER_LOSS'),
 ('HARD_START','PUMP_WEAR','REPLACE_PUMP','ENGINE_FUEL','HARD_START'),
 ('SLOW_HYD','CAVITATION','REPLACE_HYD_PUMP','HYDRAULICS','POWER_LOSS'),
 ('OIL_LEAK','SEAL_FAIL','RESEAL_CYLINDER','HYDRAULICS','FLUID_LEAK'),
 ('NOISE_DRIVE','BEARING_WEAR','REBUILD_FINAL_DRIVE','POWERTRAIN','PREMATURE_WEAR'),
 ('SHIFT_FAULT','CLUTCH_WEAR','REBUILD_TRANS','POWERTRAIN','PREMATURE_WEAR'),
 ('LOW_POWER','TURBO_WEAR','REPLACE_TURBO','ENGINE','POWER_LOSS'),
 ('OVERHEAT','WPUMP_SEAL','REPLACE_WATER_PUMP','ENGINE','OVERHEAT'),
 ('OVERHEAT','RAD_BLOCK','CLEAN_RADIATOR','COOLING','OVERHEAT'),
 ('INTERMITTENT','HARNESS_CHAFE','REPAIR_HARNESS','ELECTRICAL','ELECTRICAL_FAULT'),
 ('TRACK_NOISE','UC_WEAR','REPLACE_TRACK','UNDERCARRIAGE','PREMATURE_WEAR'),
 ('STRUCT_CRACK','FATIGUE_CRACK','WELD_REPAIR','STRUCTURES','CRACK_FRACTURE');

-- ---------------------------------------------------------------------------
-- MAP_DIAGNOSTIC_CODE — telematics (module_id,component_id,fmi) -> system_group + hint + severity
-- (covers the 8 precursor code families; background faults conform via row's
--  own system_group in the STG view, so no unmapped scenario codes.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE MAP_DIAGNOSTIC_CODE (
    module_id NUMBER(6,0), component_id NUMBER(6,0), fmi NUMBER(4,0),
    system_group_cd STRING, component_hint STRING, severity_cd STRING);
INSERT INTO MAP_DIAGNOSTIC_CODE VALUES
 (3,100,5,'ENGINE_FUEL','Fuel injector / rail pressure','HIGH'),
 (5,200,3,'HYDRAULICS','Main hydraulic pump','MED'),
 (7,300,4,'POWERTRAIN','Final drive / transmission','MED'),
 (2,110,4,'ENGINE','Turbo / water pump','HIGH'),
 (4,111,3,'COOLING','Radiator / cooling','MED'),
 (8,400,2,'ELECTRICAL','Wiring harness','LOW'),
 (6,500,2,'UNDERCARRIAGE','Track group','LOW'),
 (9,600,1,'STRUCTURES','Boom / structure','HIGH');

-- ---------------------------------------------------------------------------
-- MAP_MES_DEFECT — MES defect_cd -> category + system_group
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE MAP_MES_DEFECT (defect_cd STRING, defect_category STRING, system_group_cd STRING);
INSERT INTO MAP_MES_DEFECT VALUES
 ('FUEL_INJ_LEAK','Leak','ENGINE_FUEL'),
 ('MINOR_ADJ','Adjustment','GENERAL');

-- ---------------------------------------------------------------------------
-- MAP_WARRANTY_GROUP — warranty group_no -> system_group (derived from RAW,
-- since group_no is assigned per system_group at generation time).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE MAP_WARRANTY_GROUP (group_no STRING, system_group_cd STRING);
INSERT INTO MAP_WARRANTY_GROUP
SELECT DISTINCT w.group_no, m.system_group_cd
FROM SF_SOLUTIONS.CQC_RAW.RAW_WARRANTY_CLAIM w
JOIN MAP_SYSTEM_GROUP m ON m.raw_system_group = w.system_group
WHERE w.group_no IS NOT NULL;

-- quick coverage check
SELECT 'MAP_SERVICE_3C' t, COUNT(*) n FROM MAP_SERVICE_3C
UNION ALL SELECT 'MAP_WARRANTY_GROUP', COUNT(*) FROM MAP_WARRANTY_GROUP
UNION ALL SELECT 'REF_SYSTEM_GROUP', COUNT(*) FROM REF_SYSTEM_GROUP;

-- -------------------------------------------------------------------------
-- STAGING views
-- Source: platform/ddl/021_staging_views.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_STAGING;

-- Text cleaner convenience: TRIM + collapse whitespace (kept intact for embeddings)
--   TRIM(REGEXP_REPLACE(txt, '\\s+', ' '))

-- ---------------------------------------------------------------------------
-- STG_MACHINE — one conformed row per machine
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_MACHINE AS
SELECT
    r.machine_sn,
    r.model,
    COALESCE(mf.product_family, r.model_family)          AS product_family,
    r.sales_model,
    r.customer_acct,
    r.dealer_cd,
    r.build_facility_cd,
    r.region_cd,
    rg.global_region,
    rg.us_subregion,
    r.delivery_dt,
    r.warranty_start_dt,
    r.warranty_months,
    r.ext_coverage_flag,
    r.service_agreement_flag
FROM SF_SOLUTIONS.CQC_RAW.RAW_MACHINE_REGISTRATION r
LEFT JOIN REF_MODEL_FAMILY mf ON mf.model = r.model
LEFT JOIN REF_REGION rg ON rg.region_cd = r.region_cd
QUALIFY ROW_NUMBER() OVER (PARTITION BY r.machine_sn ORDER BY r.delivery_dt) = 1;

-- ---------------------------------------------------------------------------
-- STG_GENEALOGY — installed components (supplier_lot_no preserved untouched)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_GENEALOGY AS
SELECT
    g.machine_sn,
    g.engine_sn,
    g.config_no,
    g.part_no,
    g.component_sn,
    g.supplier_lot_no,
    g.supplier_id,
    g.build_facility_cd,
    g.build_dt,
    g.system_group                                       AS system_group_raw,
    sg.system_group_cd
FROM SF_SOLUTIONS.CQC_RAW.RAW_PRODUCT_GENEALOGY g
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = g.system_group;

-- ---------------------------------------------------------------------------
-- STG_PART
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_PART AS
SELECT p.part_no, TRIM(p.part_desc) AS part_desc, sg.system_group_cd,
       p.supplier_id, p.serviceable_flag
FROM SF_SOLUTIONS.CQC_RAW.RAW_PART_MASTER p
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = p.system_group;

-- ---------------------------------------------------------------------------
-- STG_CUSTOMER
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_CUSTOMER AS
SELECT c.acct_no, TRIM(c.name) AS name, c.industry, em.end_market_cd,
       c.size_band, c.region_cd, rg.global_region, rg.us_subregion,
       c.country_cd, c.state_cd
FROM SF_SOLUTIONS.CQC_RAW.RAW_CUSTOMER_MASTER c
LEFT JOIN MAP_INDUSTRY_END_MARKET em ON em.industry = c.industry
LEFT JOIN REF_REGION rg ON rg.region_cd = c.region_cd;

-- ---------------------------------------------------------------------------
-- STG_DEALER
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_DEALER AS
SELECT d.dealer_cd, TRIM(d.name) AS name, d.branch, d.territory,
       d.region_cd, rg.global_region, rg.us_subregion, d.country_cd, d.state_cd
FROM SF_SOLUTIONS.CQC_RAW.RAW_DEALER_MASTER d
LEFT JOIN REF_REGION rg ON rg.region_cd = d.region_cd;

-- ---------------------------------------------------------------------------
-- STG_DEALER_SERVICE — 3C -> system_group + failure_mode
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_DEALER_SERVICE AS
SELECT
    s.service_record_id,
    s.machine_sn,
    s.dealer_cd,
    m.product_family,
    m.global_region, m.us_subregion,
    s.repair_dt                                          AS event_date,
    DATE_TRUNC('month', s.repair_dt)                     AS event_month,
    s.op_hours,
    s.complaint_cd, s.cause_cd, s.correction_cd,
    COALESCE(x.system_group_cd, sg.system_group_cd)      AS system_group_cd,
    x.failure_mode_cd,
    s.part_no,
    s.labor_hrs,
    TRIM(REGEXP_REPLACE(s.job_story_txt, '\\s+', ' '))   AS job_story_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_DEALER_SERVICE s
LEFT JOIN MAP_SERVICE_3C x
       ON x.complaint_cd = s.complaint_cd AND x.cause_cd = s.cause_cd AND x.correction_cd = s.correction_cd
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = s.system_group
LEFT JOIN STG_MACHINE m ON m.machine_sn = s.machine_sn;

-- ---------------------------------------------------------------------------
-- STG_WARRANTY_CLAIM — group_no -> system_group; typed amounts; MIS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_WARRANTY_CLAIM AS
SELECT
    w.claim_no,
    w.machine_sn,
    w.dealer_cd,
    m.product_family, m.global_region, m.us_subregion,
    w.failure_dt                                         AS event_date,
    DATE_TRUNC('month', w.failure_dt)                    AS event_month,
    w.claim_dt,
    w.part_no,
    w.group_no,
    COALESCE(wg.system_group_cd, sg.system_group_cd)     AS system_group_cd,
    w.labor_hrs, w.parts_amt, w.labor_amt, w.total_claim_amt,
    w.months_in_service, w.op_hours_at_failure
FROM SF_SOLUTIONS.CQC_RAW.RAW_WARRANTY_CLAIM w
LEFT JOIN MAP_WARRANTY_GROUP wg ON wg.group_no = w.group_no
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = w.system_group
LEFT JOIN STG_MACHINE m ON m.machine_sn = w.machine_sn
QUALIFY ROW_NUMBER() OVER (PARTITION BY w.claim_no ORDER BY w.claim_dt) = 1;   -- dedup resubmits

-- ---------------------------------------------------------------------------
-- STG_TECH_ASSIST_CASE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_TECH_ASSIST_CASE AS
SELECT d.tac_id, d.machine_sn, d.model,
       COALESCE(sg.system_group_cd, 'GENERAL')            AS system_group_cd,
       d.open_ts, d.close_ts,
       CAST(d.open_ts AS DATE)                            AS event_date,
       DATE_TRUNC('month', d.open_ts)                     AS event_month,
       UPPER(d.status)                                    AS status,
       TRIM(REGEXP_REPLACE(d.problem_txt, '\\s+', ' '))   AS problem_txt,
       TRIM(REGEXP_REPLACE(d.resolution_txt, '\\s+', ' ')) AS resolution_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_TECH_ASSIST_CASE d
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = d.system_group;

-- ---------------------------------------------------------------------------
-- STG_INSPECTION — condition rating scale
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_INSPECTION AS
SELECT i.inspection_id, i.machine_sn, i.dealer_cd,
       i.inspect_dt AS event_date, DATE_TRUNC('month', i.inspect_dt) AS event_month,
       UPPER(i.inspect_type) AS inspect_type, i.item_cd,
       COALESCE(sg.system_group_cd, 'GENERAL') AS system_group_cd,
       UPPER(i.condition_rating) AS condition_rating,
       CASE UPPER(i.condition_rating) WHEN 'GREEN' THEN 1 WHEN 'YELLOW' THEN 2 WHEN 'RED' THEN 3 END AS condition_rank,
       TRIM(REGEXP_REPLACE(i.finding_txt, '\\s+', ' ')) AS finding_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_INSPECTION i
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = i.system_group;

-- ---------------------------------------------------------------------------
-- STG_FLUID_ANALYSIS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_FLUID_ANALYSIS AS
SELECT sample_id, machine_sn, LOWER(compartment) AS compartment,
       sample_dt AS event_date, DATE_TRUNC('month', sample_dt) AS event_month,
       op_hours, fe_ppm, cu_ppm, al_ppm, si_ppm, visc_cst, LOWER(interp_cd) AS interp_cd
FROM SF_SOLUTIONS.CQC_RAW.RAW_FLUID_ANALYSIS;

-- ---------------------------------------------------------------------------
-- STG_TELEMATICS_FAULT — OEM / J1939 diagnostic codes -> system_group + severity
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_TELEMATICS_FAULT AS
SELECT
    f.fault_id, f.machine_sn, f.event_ts,
    CAST(f.event_ts AS DATE)                              AS event_date,
    DATE_TRUNC('month', f.event_ts)                       AS event_month,
    f.module_id, f.component_id, f.fmi, f.spn, f.j1939_fmi,
    COALESCE(dc.system_group_cd, sg.system_group_cd, 'GENERAL') AS system_group_cd,
    dc.component_hint,
    COALESCE(dc.severity_cd, CASE f.severity_lvl WHEN 3 THEN 'HIGH' WHEN 2 THEN 'MED' ELSE 'LOW' END) AS severity_cd,
    f.severity_lvl, f.occurrence_cnt, f.lat, f.lon,
    (f.fault_id LIKE 'BG%')                               AS is_background
FROM SF_SOLUTIONS.CQC_RAW.RAW_TELEMATICS_FAULT f
LEFT JOIN MAP_DIAGNOSTIC_CODE dc ON dc.module_id = f.module_id AND dc.component_id = f.component_id AND dc.fmi = f.fmi
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = f.system_group;

-- ---------------------------------------------------------------------------
-- STG_TELEMATICS_HEALTH
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_TELEMATICS_HEALTH AS
SELECT machine_sn, snapshot_dt AS event_date, DATE_TRUNC('month', snapshot_dt) AS event_month,
       op_hours, fuel_used_l, idle_pct, load_factor, avg_engine_temp, peak_engine_temp, derate_events
FROM SF_SOLUTIONS.CQC_RAW.RAW_TELEMATICS_HEALTH
QUALIFY ROW_NUMBER() OVER (PARTITION BY machine_sn, snapshot_dt ORDER BY op_hours DESC) = 1;

-- ---------------------------------------------------------------------------
-- STG_MES_QUALITY — defect_cd -> category + system_group
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_MES_QUALITY AS
SELECT q.mes_id, q.machine_sn, q.facility_cd, q.line, q.shift, q.station,
       q.test_dt AS event_date, DATE_TRUNC('month', q.test_dt) AS event_month,
       UPPER(q.result) AS result, q.defect_cd, md.defect_category,
       COALESCE(md.system_group_cd, sg.system_group_cd, 'GENERAL') AS system_group_cd,
       q.rework_min
FROM SF_SOLUTIONS.CQC_RAW.RAW_MES_QUALITY q
LEFT JOIN MAP_MES_DEFECT md ON md.defect_cd = q.defect_cd
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = q.system_group;

-- ---------------------------------------------------------------------------
-- STG_SUPPLIER_INCOMING / STG_SUPPLIER_SCAR (lot preserved untouched)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_SUPPLIER_INCOMING AS
SELECT incoming_id, supplier_id, part_no, supplier_lot_no,
       recv_dt AS event_date, DATE_TRUNC('month', recv_dt) AS event_month,
       qty_recv, qty_reject,
       DIV0(qty_reject, qty_recv) AS reject_rate, defect_cd
FROM SF_SOLUTIONS.CQC_RAW.RAW_SUPPLIER_INCOMING;

CREATE OR REPLACE VIEW STG_SUPPLIER_SCAR AS
SELECT scar_id, supplier_id, part_no, supplier_lot_no,
       open_dt AS event_date, DATE_TRUNC('month', open_dt) AS event_month, close_dt,
       UPPER(status) AS status,
       TRIM(REGEXP_REPLACE(root_cause_txt, '\\s+', ' ')) AS root_cause_txt,
       TRIM(REGEXP_REPLACE(corrective_txt, '\\s+', ' ')) AS corrective_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_SUPPLIER_SCAR;

-- ---------------------------------------------------------------------------
-- STG_VOC_SURVEY / STG_CUSTOMER_CASE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_VOC_SURVEY AS
SELECT resp_id, customer_acct, machine_sn,
       survey_dt AS event_date, DATE_TRUNC('month', survey_dt) AS event_month,
       nps, csat,
       CASE WHEN nps >= 50 THEN 'PROMOTER' WHEN nps >= 0 THEN 'PASSIVE' ELSE 'DETRACTOR' END AS nps_band,
       TRIM(REGEXP_REPLACE(verbatim_txt, '\\s+', ' ')) AS verbatim_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_VOC_SURVEY;

CREATE OR REPLACE VIEW STG_CUSTOMER_CASE AS
SELECT case_id, customer_acct, machine_sn, open_ts, close_ts,
       CAST(open_ts AS DATE) AS event_date, DATE_TRUNC('month', open_ts) AS event_month,
       LOWER(channel) AS channel, category,
       TRIM(REGEXP_REPLACE(narrative_txt, '\\s+', ' ')) AS narrative_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_CUSTOMER_CASE;

-- ---------------------------------------------------------------------------
-- STG_SAFETY_INCIDENT — severity conform to REF_SEVERITY
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_SAFETY_INCIDENT AS
SELECT s.incident_id, s.machine_sn, s.part_no,
       s.event_dt AS event_date, DATE_TRUNC('month', s.event_dt) AS event_month,
       CASE UPPER(s.severity) WHEN 'MEDIUM' THEN 'MED' ELSE UPPER(s.severity) END AS severity_cd,
       s.injury_flag, s.sif_potential_flag,
       COALESCE(sg.system_group_cd, 'GENERAL') AS system_group_cd,
       TRIM(REGEXP_REPLACE(s.description_txt, '\\s+', ' ')) AS description_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_SAFETY_INCIDENT s
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = s.system_group;

-- ---------------------------------------------------------------------------
-- STG_FIELD_CAMPAIGN — one row per affected serial (already exploded in RAW)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_FIELD_CAMPAIGN AS
SELECT c.program_id, UPPER(c.program_type) AS program_type, c.model,
       COALESCE(sg.system_group_cd, 'GENERAL') AS system_group_cd,
       c.affected_sn AS machine_sn, c.open_dt, c.completion_dt,
       UPPER(c.status) AS status,
       TRIM(REGEXP_REPLACE(c.issue_txt, '\\s+', ' ')) AS issue_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_FIELD_CAMPAIGN c
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = c.system_group;

-- ---------------------------------------------------------------------------
-- STG_DOC_TECH — model->family, system_group conform (text intact for Search)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_DOC_TECH AS
SELECT d.doc_id, d.doc_type, d.model,
       mf.product_family,
       COALESCE(sg.system_group_cd, 'GENERAL') AS system_group_cd,
       d.issue_dt, TRIM(d.title) AS title, d.body_txt
FROM SF_SOLUTIONS.CQC_RAW.RAW_DOC_TECH d
LEFT JOIN REF_MODEL_FAMILY mf ON mf.model = d.model
LEFT JOIN MAP_SYSTEM_GROUP sg ON sg.raw_system_group = d.system_group;

SHOW VIEWS IN SCHEMA SF_SOLUTIONS.CQC_STAGING;

-- -------------------------------------------------------------------------
-- STAGING data-quality checks
-- Source: platform/ddl/022_staging_dq.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_STAGING;

CREATE OR REPLACE TABLE STG_DQ_QUARANTINE (
    source_table STRING, reason_cd STRING, business_key STRING,
    payload VARIANT, detected_ts TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE STG_DQ_CHECKS (
    check_name STRING, target_object STRING, check_type STRING,
    numerator NUMBER, denominator NUMBER, rate FLOAT,
    status STRING, checked_ts TIMESTAMP_NTZ
);

-- ---------------------------------------------------------------------------
-- SP_RUN_DQ_CHECKS — re-runnable; repopulates both DQ tables. Agent/UI-callable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_RUN_DQ_CHECKS()
RETURNS STRING LANGUAGE SQL AS
$$
BEGIN
    TRUNCATE TABLE STG_DQ_CHECKS;
    TRUNCATE TABLE STG_DQ_QUARANTINE;

    -- Orphan-key checks: field/telematics rows whose machine is unknown.
    LET feeds ARRAY := ARRAY_CONSTRUCT(
        'STG_DEALER_SERVICE','STG_WARRANTY_CLAIM','STG_TECH_ASSIST_CASE','STG_INSPECTION',
        'STG_FLUID_ANALYSIS','STG_TELEMATICS_FAULT','STG_TELEMATICS_HEALTH','STG_VOC_SURVEY',
        'STG_CUSTOMER_CASE','STG_SAFETY_INCIDENT','STG_FIELD_CAMPAIGN');
    FOR i IN 0 TO ARRAY_SIZE(feeds)-1 DO
        LET f STRING := feeds[i]::STRING;
        EXECUTE IMMEDIATE
          'INSERT INTO STG_DQ_CHECKS
           SELECT ''orphan_machine_key'', ''' || f || ''', ''orphan_key'',
                  SUM(IFF(mm.machine_sn IS NULL,1,0)), COUNT(*),
                  DIV0(SUM(IFF(mm.machine_sn IS NULL,1,0)), COUNT(*)),
                  IFF(DIV0(SUM(IFF(mm.machine_sn IS NULL,1,0)),COUNT(*)) <= 0.005, ''PASS'', ''WARN''),
                  CURRENT_TIMESTAMP()
           FROM ' || f || ' s LEFT JOIN STG_MACHINE mm ON mm.machine_sn = s.machine_sn';
    END FOR;

    -- Unmapped-code checks (must be 0 for the anchor scenario).
    INSERT INTO STG_DQ_CHECKS
    SELECT 'unmapped_3c','STG_DEALER_SERVICE','unmapped_code',
           SUM(IFF(failure_mode_cd IS NULL,1,0)), COUNT(*),
           DIV0(SUM(IFF(failure_mode_cd IS NULL,1,0)),COUNT(*)),
           IFF(SUM(IFF(failure_mode_cd IS NULL,1,0))=0,'PASS','FAIL'), CURRENT_TIMESTAMP()
    FROM STG_DEALER_SERVICE;

    INSERT INTO STG_DQ_CHECKS
    SELECT 'unmapped_warranty_group','STG_WARRANTY_CLAIM','unmapped_code',
           SUM(IFF(system_group_cd IS NULL,1,0)), COUNT(*),
           DIV0(SUM(IFF(system_group_cd IS NULL,1,0)),COUNT(*)),
           IFF(SUM(IFF(system_group_cd IS NULL,1,0))=0,'PASS','FAIL'), CURRENT_TIMESTAMP()
    FROM STG_WARRANTY_CLAIM;

    INSERT INTO STG_DQ_CHECKS
    SELECT 'unmapped_diag_code','STG_TELEMATICS_FAULT','unmapped_code',
           SUM(IFF(system_group_cd IS NULL,1,0)), COUNT(*),
           DIV0(SUM(IFF(system_group_cd IS NULL,1,0)),COUNT(*)),
           IFF(SUM(IFF(system_group_cd IS NULL,1,0))=0,'PASS','FAIL'), CURRENT_TIMESTAMP()
    FROM STG_TELEMATICS_FAULT;

    -- Null-critical-field checks.
    INSERT INTO STG_DQ_CHECKS
    SELECT 'null_event_date','STG_DEALER_SERVICE','null_critical',
           SUM(IFF(event_date IS NULL,1,0)), COUNT(*),
           DIV0(SUM(IFF(event_date IS NULL,1,0)),COUNT(*)),
           IFF(DIV0(SUM(IFF(event_date IS NULL,1,0)),COUNT(*))<=0.001,'PASS','WARN'), CURRENT_TIMESTAMP()
    FROM STG_DEALER_SERVICE;

    -- Duplicate-rate checks.
    INSERT INTO STG_DQ_CHECKS
    SELECT 'dup_claim_no','STG_WARRANTY_CLAIM','duplicate',
           COUNT(*)-COUNT(DISTINCT claim_no), COUNT(*),
           DIV0(COUNT(*)-COUNT(DISTINCT claim_no),COUNT(*)),
           IFF(COUNT(*)=COUNT(DISTINCT claim_no),'PASS','WARN'), CURRENT_TIMESTAMP()
    FROM STG_WARRANTY_CLAIM;

    -- Out-of-range checks: negative operating hours / future-dated failures.
    INSERT INTO STG_DQ_CHECKS
    SELECT 'op_hours_out_of_range','STG_DEALER_SERVICE','range',
           SUM(IFF(op_hours < 0 OR op_hours > 80000,1,0)), COUNT(*),
           DIV0(SUM(IFF(op_hours < 0 OR op_hours > 80000,1,0)),COUNT(*)),
           IFF(SUM(IFF(op_hours<0 OR op_hours>80000,1,0))=0,'PASS','WARN'), CURRENT_TIMESTAMP()
    FROM STG_DEALER_SERVICE;

    INSERT INTO STG_DQ_CHECKS
    SELECT 'future_dated_failures','STG_WARRANTY_CLAIM','range',
           SUM(IFF(event_date > CURRENT_DATE(),1,0)), COUNT(*),
           DIV0(SUM(IFF(event_date > CURRENT_DATE(),1,0)),COUNT(*)),
           IFF(SUM(IFF(event_date > CURRENT_DATE(),1,0))=0,'PASS','WARN'), CURRENT_TIMESTAMP()
    FROM STG_WARRANTY_CLAIM;

    -- Quarantine orphan Dealer Service Records/warranty rows (payload for audit).
    INSERT INTO STG_DQ_QUARANTINE
    SELECT 'STG_DEALER_SERVICE','ORPHAN_MACHINE', s.service_record_id,
           OBJECT_CONSTRUCT('machine_sn', s.machine_sn, 'event_date', s.event_date),
           CURRENT_TIMESTAMP()
    FROM STG_DEALER_SERVICE s LEFT JOIN STG_MACHINE m ON m.machine_sn = s.machine_sn
    WHERE m.machine_sn IS NULL;

    RETURN 'DQ checks complete';
END;
$$;

CALL SP_RUN_DQ_CHECKS();

SELECT check_type, status, COUNT(*) n FROM STG_DQ_CHECKS GROUP BY 1,2 ORDER BY 1,2;

-- -------------------------------------------------------------------------
-- ATOMIC dimensions
-- Source: platform/ddl/030_atomic_dims.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ATOMIC;

-- ---------------------------------------------------------------------------
-- DIM_DATE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_DATE AS
SELECT
    d                                        AS date_day,
    YEAR(d)                                  AS year,
    QUARTER(d)                               AS quarter,
    MONTH(d)                                 AS month,
    DATE_TRUNC('month', d)                   AS month_start,
    TO_CHAR(d, 'YYYY-MM')                     AS year_month,
    WEEKOFYEAR(d)                            AS week_of_year,
    DAYNAME(d)                               AS day_name
FROM (
    SELECT DATEADD('day', SEQ4(), DATE '2018-01-01') AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 3653))
);

-- ---------------------------------------------------------------------------
-- DIM_QUALITY_DIMENSION (S/P/E) — seed with priority rank (safety=1)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_QUALITY_DIMENSION (
    quality_dimension_cd STRING, quality_dimension_name STRING, priority_rank NUMBER(2,0));
INSERT INTO DIM_QUALITY_DIMENSION VALUES
 ('SAFETY','Safety',1),('PRODUCTIVITY','Productivity',2),('EXPERIENCE','Experience',3);

-- ---------------------------------------------------------------------------
-- DIM_SYSTEM_GROUP / DIM_FAILURE_MODE (from conformed REF_*)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_SYSTEM_GROUP AS
SELECT system_group_cd, system_group_name FROM SF_SOLUTIONS.CQC_STAGING.REF_SYSTEM_GROUP;

CREATE OR REPLACE TABLE DIM_FAILURE_MODE AS
SELECT failure_mode_cd, failure_mode_name FROM SF_SOLUTIONS.CQC_STAGING.REF_FAILURE_MODE;

-- ---------------------------------------------------------------------------
-- DIM_GEOGRAPHY
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_GEOGRAPHY (
    geography_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    region_cd STRING, global_region STRING, us_subregion STRING);
INSERT INTO DIM_GEOGRAPHY (region_cd, global_region, us_subregion)
SELECT region_cd, global_region, us_subregion FROM SF_SOLUTIONS.CQC_STAGING.REF_REGION;

-- ---------------------------------------------------------------------------
-- DIM_PRODUCT_FAMILY / DIM_MODEL
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_PRODUCT_FAMILY (
    product_family_key NUMBER AUTOINCREMENT START 1 INCREMENT 1, product_family STRING);
INSERT INTO DIM_PRODUCT_FAMILY (product_family)
SELECT DISTINCT product_family FROM SF_SOLUTIONS.CQC_STAGING.REF_MODEL_FAMILY;

CREATE OR REPLACE TABLE DIM_MODEL (
    model_key NUMBER AUTOINCREMENT START 1 INCREMENT 1, model STRING, product_family STRING);
INSERT INTO DIM_MODEL (model, product_family)
SELECT model, product_family FROM SF_SOLUTIONS.CQC_STAGING.REF_MODEL_FAMILY;

-- ---------------------------------------------------------------------------
-- DIM_CUSTOMER / DIM_DEALER
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_CUSTOMER (
    customer_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    customer_acct STRING, name STRING, industry STRING, end_market_cd STRING,
    size_band STRING, region_cd STRING, global_region STRING, us_subregion STRING,
    country_cd STRING, state_cd STRING);
INSERT INTO DIM_CUSTOMER (customer_acct, name, industry, end_market_cd, size_band, region_cd, global_region, us_subregion, country_cd, state_cd)
SELECT acct_no, name, industry, end_market_cd, size_band, region_cd, global_region, us_subregion, country_cd, state_cd
FROM SF_SOLUTIONS.CQC_STAGING.STG_CUSTOMER;

CREATE OR REPLACE TABLE DIM_DEALER (
    dealer_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    dealer_cd STRING, name STRING, branch STRING, territory STRING,
    region_cd STRING, global_region STRING, us_subregion STRING, country_cd STRING, state_cd STRING);
INSERT INTO DIM_DEALER (dealer_cd, name, branch, territory, region_cd, global_region, us_subregion, country_cd, state_cd)
SELECT dealer_cd, name, branch, territory, region_cd, global_region, us_subregion, country_cd, state_cd
FROM SF_SOLUTIONS.CQC_STAGING.STG_DEALER;

-- ---------------------------------------------------------------------------
-- DIM_SUPPLIER (distinct suppliers across genealogy/part/supplier feeds)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_SUPPLIER (
    supplier_key NUMBER AUTOINCREMENT START 1 INCREMENT 1, supplier_id STRING);
INSERT INTO DIM_SUPPLIER (supplier_id)
SELECT DISTINCT supplier_id FROM (
    SELECT supplier_id FROM SF_SOLUTIONS.CQC_STAGING.STG_GENEALOGY
    UNION SELECT supplier_id FROM SF_SOLUTIONS.CQC_STAGING.STG_PART
    UNION SELECT supplier_id FROM SF_SOLUTIONS.CQC_STAGING.STG_SUPPLIER_INCOMING
) WHERE supplier_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- DIM_FACILITY (build plants; seed names/region)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_FACILITY (
    facility_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    facility_cd STRING, facility_name STRING, country_cd STRING, state_cd STRING);
INSERT INTO DIM_FACILITY (facility_cd, facility_name, country_cd, state_cd)
SELECT f.facility_cd,
       CASE f.facility_cd
         WHEN 'PLT_SOUTH'   THEN 'South Plant, GA (Large Excavators)'
         WHEN 'PLT_PACIFIC' THEN 'Pacific Plant, KR (Excavators)'
         WHEN 'PLT_CENTRAL' THEN 'Central Plant, OH (Dozers)'
         WHEN 'PLT_NORTH'   THEN 'North Plant, MN (Wheel Loaders)'
         WHEN 'PLT_WEST'    THEN 'West Plant, CO (Motor Graders)'
         WHEN 'PLT_EAST'    THEN 'East Plant, PA (Articulated Trucks)'
         ELSE f.facility_cd END,
       CASE WHEN f.facility_cd = 'PLT_PACIFIC' THEN 'KR' ELSE 'US' END,
       CASE f.facility_cd WHEN 'PLT_SOUTH' THEN 'GA' WHEN 'PLT_CENTRAL' THEN 'OH'
         WHEN 'PLT_NORTH' THEN 'MN' WHEN 'PLT_WEST' THEN 'CO' WHEN 'PLT_EAST' THEN 'PA' ELSE NULL END
FROM (SELECT DISTINCT build_facility_cd AS facility_cd FROM SF_SOLUTIONS.CQC_STAGING.STG_MACHINE) f;

-- ---------------------------------------------------------------------------
-- DIM_COMPONENT (part grain) — criticality derived from system group
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_COMPONENT (
    component_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    part_no STRING, part_desc STRING, system_group_cd STRING, supplier_id STRING, criticality STRING);
INSERT INTO DIM_COMPONENT (part_no, part_desc, system_group_cd, supplier_id, criticality)
SELECT part_no, part_desc, system_group_cd, supplier_id,
       CASE WHEN system_group_cd IN ('ENGINE_FUEL','ENGINE','POWERTRAIN','HYDRAULICS','STRUCTURES')
            THEN 'HIGH' ELSE 'MEDIUM' END
FROM SF_SOLUTIONS.CQC_STAGING.STG_PART;

-- ---------------------------------------------------------------------------
-- DIM_LOT (traceability key) — grain = supplier x part x lot; suspect flag
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_LOT (
    lot_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    supplier_id STRING, part_no STRING, supplier_lot_no STRING,
    system_group_cd STRING, first_build_dt DATE, is_suspect BOOLEAN);
INSERT INTO DIM_LOT (supplier_id, part_no, supplier_lot_no, system_group_cd, first_build_dt, is_suspect)
SELECT g.supplier_id, g.part_no, g.supplier_lot_no, ANY_VALUE(g.system_group_cd),
       MIN(g.build_dt),
       BOOLOR_AGG(g.supplier_lot_no IN ('L-4471','L-4472','L-4480'))
FROM SF_SOLUTIONS.CQC_STAGING.STG_GENEALOGY g
WHERE g.supplier_lot_no IS NOT NULL
GROUP BY g.supplier_id, g.part_no, g.supplier_lot_no;

-- ---------------------------------------------------------------------------
-- DIM_MACHINE (grain = machine serial) — build attrs from genealogy
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_MACHINE (
    machine_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    machine_sn STRING, model STRING, product_family STRING, engine_sn STRING,
    build_facility_cd STRING, build_dt DATE, customer_acct STRING, dealer_cd STRING,
    region_cd STRING, global_region STRING, us_subregion STRING,
    delivery_dt DATE, warranty_start_dt DATE, warranty_months NUMBER(4,0),
    ext_coverage_flag BOOLEAN, service_agreement_flag BOOLEAN);
INSERT INTO DIM_MACHINE (machine_sn, model, product_family, engine_sn, build_facility_cd, build_dt,
    customer_acct, dealer_cd, region_cd, global_region, us_subregion, delivery_dt, warranty_start_dt,
    warranty_months, ext_coverage_flag, service_agreement_flag)
SELECT m.machine_sn, m.model, m.product_family, g.engine_sn, m.build_facility_cd, g.build_dt,
    m.customer_acct, m.dealer_cd, m.region_cd, m.global_region, m.us_subregion, m.delivery_dt,
    m.warranty_start_dt, m.warranty_months, m.ext_coverage_flag, m.service_agreement_flag
FROM SF_SOLUTIONS.CQC_STAGING.STG_MACHINE m
LEFT JOIN (
    SELECT machine_sn, ANY_VALUE(engine_sn) engine_sn, MIN(build_dt) build_dt
    FROM SF_SOLUTIONS.CQC_STAGING.STG_GENEALOGY GROUP BY machine_sn
) g ON g.machine_sn = m.machine_sn;

SELECT 'DIM_MACHINE' t, COUNT(*) n FROM DIM_MACHINE
UNION ALL SELECT 'DIM_LOT', COUNT(*) FROM DIM_LOT
UNION ALL SELECT 'DIM_COMPONENT', COUNT(*) FROM DIM_COMPONENT
UNION ALL SELECT 'DIM_LOT_suspect', COUNT(*) FROM DIM_LOT WHERE is_suspect;

-- -------------------------------------------------------------------------
-- ATOMIC quality-dimension mapping
-- Source: platform/ddl/031_atomic_map_quality_dimension.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ATOMIC;

CREATE OR REPLACE TABLE MAP_QUALITY_DIMENSION (
    system_group_cd STRING,          -- '*' = any system group
    failure_mode_cd STRING,
    quality_dimension_cd STRING,
    safety_implicated BOOLEAN        -- mode is inherently safety-gating
);
INSERT INTO MAP_QUALITY_DIMENSION VALUES
 ('*','CRACK_FRACTURE','SAFETY',TRUE),
 ('*','SUDDEN_SHUTDOWN','SAFETY',TRUE),
 ('*','POWER_LOSS','PRODUCTIVITY',FALSE),
 ('*','OVERHEAT','PRODUCTIVITY',FALSE),
 ('*','FLUID_LEAK','PRODUCTIVITY',FALSE),
 ('*','PREMATURE_WEAR','PRODUCTIVITY',FALSE),
 ('*','HARD_START','PRODUCTIVITY',FALSE),
 ('*','ELECTRICAL_FAULT','PRODUCTIVITY',FALSE),
 ('*','SEAL_FAILURE','PRODUCTIVITY',FALSE),
 ('*','CONTAMINATION','PRODUCTIVITY',FALSE),
 ('*','NOISE_VIBRATION','EXPERIENCE',FALSE),
 ('*','PAINT_DEFECT','EXPERIENCE',FALSE),
 ('*','SENSOR_FAULT','EXPERIENCE',FALSE),
 ('*','SOFTWARE_FAULT','EXPERIENCE',FALSE),
 ('*','CORROSION','EXPERIENCE',FALSE);

SELECT quality_dimension_cd, COUNT(*) n FROM MAP_QUALITY_DIMENSION GROUP BY 1 ORDER BY 1;

-- -------------------------------------------------------------------------
-- ATOMIC quality-event spine
-- Source: platform/ddl/032_atomic_fact_quality_event.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ATOMIC;

CREATE OR REPLACE TABLE FACT_QUALITY_EVENT AS
WITH ev AS (
    -- 1. Warranty claims
    SELECT 'WARRANTY' AS source_system, claim_no AS source_event_id,
           event_date::TIMESTAMP_NTZ AS event_ts, machine_sn, part_no, system_group_cd,
           NULL::STRING AS failure_mode_cd,
           IFF(total_claim_amt > 8000,'HIGH','MED') AS severity_cd,
           'warranty' AS detection_channel, 'RESOLVED' AS status,
           labor_hrs::FLOAT AS downtime_hours, total_claim_amt::FLOAT AS repair_cost_usd,
           labor_hrs::FLOAT AS labor_hrs, months_in_service::FLOAT AS months_in_service,
           op_hours_at_failure::FLOAT AS op_hours_at_event, FALSE AS injury_flag, FALSE AS sif_potential_flag
    FROM SF_SOLUTIONS.CQC_STAGING.STG_WARRANTY_CLAIM
    UNION ALL
    -- 2. Dealer service records (3C -> failure_mode)
    SELECT 'DEALER_SERVICE', service_record_id, event_date::TIMESTAMP_NTZ, machine_sn, part_no, system_group_cd,
           failure_mode_cd, 'MED', 'dealer_service', 'RESOLVED',
           labor_hrs::FLOAT, NULL::FLOAT, labor_hrs::FLOAT, NULL::FLOAT, op_hours::FLOAT, FALSE, FALSE
    FROM SF_SOLUTIONS.CQC_STAGING.STG_DEALER_SERVICE
    UNION ALL
    -- 3. TAC technical cases
    SELECT 'TECH_ASSIST', tac_id, open_ts, machine_sn, NULL, system_group_cd,
           NULL, 'MED', 'tech_assist',
           CASE status WHEN 'CLOSED' THEN 'RESOLVED' WHEN 'ESCALATED' THEN 'IN_PROGRESS' ELSE 'NEW' END,
           NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, FALSE, FALSE
    FROM SF_SOLUTIONS.CQC_STAGING.STG_TECH_ASSIST_CASE
    UNION ALL
    -- 4. Severe/actionable telematics faults (HIGH severity, non-background)
    SELECT 'TELEMATICS', fault_id, event_ts, machine_sn, NULL, system_group_cd,
           NULL, severity_cd, 'telematics', 'NEW',
           NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, FALSE, FALSE
    FROM SF_SOLUTIONS.CQC_STAGING.STG_TELEMATICS_FAULT
    WHERE severity_cd = 'HIGH' AND NOT is_background
    UNION ALL
    -- 5. Critical inspection findings (RED)
    SELECT 'INSPECTION', inspection_id, event_date::TIMESTAMP_NTZ, machine_sn, NULL, system_group_cd,
           NULL, 'MED', 'inspection', 'TRIAGED',
           NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, FALSE, FALSE
    FROM SF_SOLUTIONS.CQC_STAGING.STG_INSPECTION
    WHERE condition_rating = 'RED'
    UNION ALL
    -- 6. Safety incidents / near-misses (drives the safety gate)
    SELECT 'SAFETY', incident_id, event_date::TIMESTAMP_NTZ, machine_sn, part_no, system_group_cd,
           'SUDDEN_SHUTDOWN', severity_cd, 'safety', 'TRIAGED',
           NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, injury_flag, sif_potential_flag
    FROM SF_SOLUTIONS.CQC_STAGING.STG_SAFETY_INCIDENT
    UNION ALL
    -- 7. Quality-related customer cases (category -> system group)
    SELECT 'CASE', c.case_id, c.open_ts, c.machine_sn, NULL,
           COALESCE(sg.system_group_cd,'GENERAL'), NULL, 'LOW', 'customer_case', 'NEW',
           NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, FALSE, FALSE
    FROM SF_SOLUTIONS.CQC_STAGING.STG_CUSTOMER_CASE c
    LEFT JOIN SF_SOLUTIONS.CQC_STAGING.MAP_SYSTEM_GROUP sg ON sg.raw_system_group = c.category
    UNION ALL
    -- 8. Detractor VOC verbatims (Experience)
    SELECT 'VOC', resp_id, event_date::TIMESTAMP_NTZ, machine_sn, NULL, 'GENERAL',
           NULL, 'LOW', 'voc', 'NEW',
           NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, FALSE, FALSE
    FROM SF_SOLUTIONS.CQC_STAGING.STG_VOC_SURVEY
    WHERE nps_band = 'DETRACTOR'
    UNION ALL
    -- 9. Escaped/critical plant line defects
    SELECT 'PLANT', mes_id, event_date::TIMESTAMP_NTZ, machine_sn, NULL, system_group_cd,
           NULL, 'LOW', 'plant', 'CONTAINED',
           NULL::FLOAT, NULL::FLOAT, rework_min::FLOAT, NULL::FLOAT, NULL::FLOAT, FALSE, FALSE
    FROM SF_SOLUTIONS.CQC_STAGING.STG_MES_QUALITY
    WHERE result IN ('FAIL','REWORK')
),
-- effective failure mode (explicit or derived by system group), + repeat-repair window
evn AS (
    SELECT ev.*,
        COALESCE(ev.failure_mode_cd, CASE ev.system_group_cd
            WHEN 'ENGINE_FUEL' THEN 'POWER_LOSS' WHEN 'HYDRAULICS' THEN 'FLUID_LEAK'
            WHEN 'POWERTRAIN' THEN 'PREMATURE_WEAR' WHEN 'ENGINE' THEN 'OVERHEAT'
            WHEN 'COOLING' THEN 'OVERHEAT' WHEN 'ELECTRICAL' THEN 'ELECTRICAL_FAULT'
            WHEN 'UNDERCARRIAGE' THEN 'PREMATURE_WEAR' WHEN 'STRUCTURES' THEN 'CRACK_FRACTURE'
            ELSE NULL END) AS fm_eff,
        (COUNT_IF(detection_channel IN ('warranty','dealer_service'))
            OVER (PARTITION BY machine_sn, system_group_cd) > 1
         AND detection_channel IN ('warranty','dealer_service')) AS repeat_repair_flag
    FROM ev
),
-- lot-linkage: resolve installed component lot for events carrying a part_no
linked AS (
    SELECT evn.*,
        g.supplier_lot_no AS lk_lot, g.supplier_id AS lk_supplier,
        g.build_facility_cd AS lk_facility, g.component_sn AS lk_component_sn
    FROM evn
    LEFT JOIN SF_SOLUTIONS.CQC_STAGING.STG_GENEALOGY g
           ON g.machine_sn = evn.machine_sn AND g.part_no = evn.part_no
)
SELECT
    ROW_NUMBER() OVER (ORDER BY l.event_ts, l.source_system, l.source_event_id) AS event_key,
    l.source_system, l.source_event_id,
    l.event_ts, l.event_ts::DATE AS event_date, DATE_TRUNC('month', l.event_ts) AS event_month,
    dm.machine_key, dm.model, dm.product_family,
    dc.customer_key, dd.dealer_key, dg.geography_key,
    dcomp.component_key, dl.lot_key, ds.supplier_key, df.facility_key AS build_facility_key,
    l.system_group_cd, l.fm_eff AS failure_mode_cd, l.severity_cd,
    -- S/P/E classification: base map + safety gate override
    CASE
        WHEN l.injury_flag OR l.sif_potential_flag OR l.source_system = 'SAFETY'
             OR COALESCE(mqd.safety_implicated, FALSE)
             OR l.fm_eff IN ('CRACK_FRACTURE','SUDDEN_SHUTDOWN')
        THEN 'SAFETY'
        ELSE COALESCE(mqd.quality_dimension_cd, 'EXPERIENCE')
    END AS quality_dimension_cd,
    l.detection_channel, l.status,
    l.downtime_hours, l.repair_cost_usd, l.labor_hrs, l.months_in_service, l.op_hours_at_event,
    l.repeat_repair_flag, l.injury_flag, l.sif_potential_flag,
    NULL::NUMBER AS affected_population_hint,
    l.lk_component_sn AS component_sn, l.lk_lot AS supplier_lot_no
FROM linked l
LEFT JOIN DIM_MACHINE dm  ON dm.machine_sn = l.machine_sn
LEFT JOIN DIM_CUSTOMER dc ON dc.customer_acct = dm.customer_acct
LEFT JOIN DIM_DEALER dd   ON dd.dealer_cd = dm.dealer_cd
LEFT JOIN DIM_GEOGRAPHY dg ON dg.region_cd = dm.region_cd
LEFT JOIN DIM_COMPONENT dcomp ON dcomp.part_no = l.part_no
LEFT JOIN DIM_LOT dl ON dl.supplier_id = l.lk_supplier AND dl.part_no = l.part_no AND dl.supplier_lot_no = l.lk_lot
LEFT JOIN DIM_SUPPLIER ds ON ds.supplier_id = l.lk_supplier
LEFT JOIN DIM_FACILITY df ON df.facility_cd = l.lk_facility
LEFT JOIN MAP_QUALITY_DIMENSION mqd ON mqd.failure_mode_cd = l.fm_eff AND mqd.system_group_cd = '*';

-- summary
SELECT source_system, COUNT(*) n FROM FACT_QUALITY_EVENT GROUP BY 1 ORDER BY 2 DESC;

-- -------------------------------------------------------------------------
-- ATOMIC detail facts
-- Source: platform/ddl/033_atomic_detail_facts.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ATOMIC;

-- Reusable lot-linkage: genealogy row per (machine, part)
--   join STG_GENEALOGY g ON g.machine_sn = x.machine_sn AND g.part_no = x.part_no

CREATE OR REPLACE VIEW FACT_WARRANTY_CLAIM AS
SELECT w.claim_no, dm.machine_key, w.machine_sn, dm.model, dm.product_family,
       dd.dealer_key, dc.customer_key, dg.geography_key,
       dcomp.component_key, dl.lot_key, ds.supplier_key,
       w.system_group_cd, w.event_date, w.event_month, w.claim_dt,
       w.part_no, w.group_no, w.labor_hrs, w.parts_amt, w.labor_amt, w.total_claim_amt,
       w.months_in_service, w.op_hours_at_failure
FROM SF_SOLUTIONS.CQC_STAGING.STG_WARRANTY_CLAIM w
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = w.machine_sn
LEFT JOIN DIM_DEALER dd ON dd.dealer_cd = dm.dealer_cd
LEFT JOIN DIM_CUSTOMER dc ON dc.customer_acct = dm.customer_acct
LEFT JOIN DIM_GEOGRAPHY dg ON dg.region_cd = dm.region_cd
LEFT JOIN SF_SOLUTIONS.CQC_STAGING.STG_GENEALOGY g ON g.machine_sn = w.machine_sn AND g.part_no = w.part_no
LEFT JOIN DIM_COMPONENT dcomp ON dcomp.part_no = w.part_no
LEFT JOIN DIM_LOT dl ON dl.supplier_id = g.supplier_id AND dl.part_no = w.part_no AND dl.supplier_lot_no = g.supplier_lot_no
LEFT JOIN DIM_SUPPLIER ds ON ds.supplier_id = g.supplier_id;

CREATE OR REPLACE VIEW FACT_SERVICE_REPAIR AS
SELECT s.service_record_id, dm.machine_key, s.machine_sn, dm.model, dm.product_family,
       dd.dealer_key, dg.geography_key, dcomp.component_key, dl.lot_key,
       s.system_group_cd, s.failure_mode_cd, s.event_date, s.event_month,
       s.op_hours, s.labor_hrs, s.part_no, s.job_story_txt
FROM SF_SOLUTIONS.CQC_STAGING.STG_DEALER_SERVICE s
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = s.machine_sn
LEFT JOIN DIM_DEALER dd ON dd.dealer_cd = dm.dealer_cd
LEFT JOIN DIM_GEOGRAPHY dg ON dg.region_cd = dm.region_cd
LEFT JOIN SF_SOLUTIONS.CQC_STAGING.STG_GENEALOGY g ON g.machine_sn = s.machine_sn AND g.part_no = s.part_no
LEFT JOIN DIM_COMPONENT dcomp ON dcomp.part_no = s.part_no
LEFT JOIN DIM_LOT dl ON dl.supplier_id = g.supplier_id AND dl.part_no = s.part_no AND dl.supplier_lot_no = g.supplier_lot_no;

CREATE OR REPLACE VIEW FACT_TELEMATICS_FAULT AS
SELECT f.fault_id, dm.machine_key, f.machine_sn, dm.model, dm.product_family,
       f.event_ts, f.event_date, f.event_month, f.module_id, f.component_id, f.fmi, f.spn, f.j1939_fmi,
       f.system_group_cd, f.component_hint, f.severity_cd, f.severity_lvl, f.occurrence_cnt,
       f.is_background, f.lat, f.lon
FROM SF_SOLUTIONS.CQC_STAGING.STG_TELEMATICS_FAULT f
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = f.machine_sn;

CREATE OR REPLACE VIEW FACT_TELEMATICS_HEALTH_DAILY AS
SELECT h.machine_sn, dm.machine_key, dm.model, dm.product_family,
       h.event_date, h.event_month, h.op_hours, h.fuel_used_l, h.idle_pct,
       h.load_factor, h.avg_engine_temp, h.peak_engine_temp, h.derate_events
FROM SF_SOLUTIONS.CQC_STAGING.STG_TELEMATICS_HEALTH h
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = h.machine_sn;

CREATE OR REPLACE VIEW FACT_PDI_RESULT AS
SELECT i.inspection_id, dm.machine_key, i.machine_sn, dm.model, dm.product_family,
       dd.dealer_key, i.event_date, i.event_month, i.inspect_type, i.item_cd,
       i.system_group_cd, i.condition_rating, i.condition_rank, i.finding_txt
FROM SF_SOLUTIONS.CQC_STAGING.STG_INSPECTION i
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = i.machine_sn
LEFT JOIN DIM_DEALER dd ON dd.dealer_cd = i.dealer_cd;

CREATE OR REPLACE VIEW FACT_MES_QUALITY AS
SELECT q.mes_id, dm.machine_key, q.machine_sn, df.facility_key, q.facility_cd,
       q.line, q.shift, q.station, q.event_date, q.event_month, q.result,
       q.defect_cd, q.defect_category, q.system_group_cd, q.rework_min
FROM SF_SOLUTIONS.CQC_STAGING.STG_MES_QUALITY q
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = q.machine_sn
LEFT JOIN DIM_FACILITY df ON df.facility_cd = q.facility_cd;

CREATE OR REPLACE VIEW FACT_SUPPLIER_QUALITY AS
SELECT i.incoming_id, ds.supplier_key, i.supplier_id, dcomp.component_key, i.part_no,
       dl.lot_key, i.supplier_lot_no, i.event_date, i.event_month,
       i.qty_recv, i.qty_reject, i.reject_rate, i.defect_cd
FROM SF_SOLUTIONS.CQC_STAGING.STG_SUPPLIER_INCOMING i
LEFT JOIN DIM_SUPPLIER ds ON ds.supplier_id = i.supplier_id
LEFT JOIN DIM_COMPONENT dcomp ON dcomp.part_no = i.part_no
LEFT JOIN DIM_LOT dl ON dl.supplier_id = i.supplier_id AND dl.part_no = i.part_no AND dl.supplier_lot_no = i.supplier_lot_no;

CREATE OR REPLACE VIEW FACT_FLUID_SAMPLE AS
SELECT s.sample_id, dm.machine_key, s.machine_sn, dm.model, dm.product_family,
       s.compartment, s.event_date, s.event_month, s.op_hours,
       s.fe_ppm, s.cu_ppm, s.al_ppm, s.si_ppm, s.visc_cst, s.interp_cd
FROM SF_SOLUTIONS.CQC_STAGING.STG_FLUID_ANALYSIS s
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = s.machine_sn;

CREATE OR REPLACE VIEW FACT_SAFETY_INCIDENT AS
SELECT s.incident_id, dm.machine_key, s.machine_sn, dm.model, dm.product_family,
       s.event_date, s.event_month, s.severity_cd, s.injury_flag, s.sif_potential_flag,
       s.system_group_cd, s.part_no, s.description_txt
FROM SF_SOLUTIONS.CQC_STAGING.STG_SAFETY_INCIDENT s
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = s.machine_sn;

CREATE OR REPLACE VIEW FACT_VOC_RESPONSE AS
SELECT v.resp_id, dc.customer_key, v.customer_acct, dm.machine_key, v.machine_sn,
       dg.geography_key, v.event_date, v.event_month, v.nps, v.csat, v.nps_band, v.verbatim_txt
FROM SF_SOLUTIONS.CQC_STAGING.STG_VOC_SURVEY v
LEFT JOIN DIM_CUSTOMER dc ON dc.customer_acct = v.customer_acct
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = v.machine_sn
LEFT JOIN DIM_GEOGRAPHY dg ON dg.region_cd = dc.region_cd;

CREATE OR REPLACE VIEW FACT_CAMPAIGN_AFFECTED AS
SELECT c.program_id, c.program_type, c.model, c.system_group_cd,
       dm.machine_key, c.machine_sn, c.open_dt, c.completion_dt, c.status,
       (c.completion_dt IS NOT NULL) AS completed_flag
FROM SF_SOLUTIONS.CQC_STAGING.STG_FIELD_CAMPAIGN c
LEFT JOIN DIM_MACHINE dm ON dm.machine_sn = c.machine_sn;

SHOW VIEWS LIKE 'FACT_%' IN SCHEMA SF_SOLUTIONS.CQC_ATOMIC;

-- -------------------------------------------------------------------------
-- ATOMIC bridges
-- Source: platform/ddl/034_atomic_bridges.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ATOMIC;

-- Every machine carrying a given lot (instant "how many machines exposed to this
-- suspect lot" for containment / campaign scoping).
CREATE OR REPLACE TABLE BRIDGE_LOT_MACHINE AS
SELECT DISTINCT
    dl.lot_key, dm.machine_key,
    dl.supplier_id, dl.part_no, dl.supplier_lot_no, dl.is_suspect,
    dm.machine_sn, dm.model, dm.product_family, dm.build_facility_cd, g.build_dt
FROM SF_SOLUTIONS.CQC_STAGING.STG_GENEALOGY g
JOIN DIM_LOT dl ON dl.supplier_id = g.supplier_id AND dl.part_no = g.part_no AND dl.supplier_lot_no = g.supplier_lot_no
JOIN DIM_MACHINE dm ON dm.machine_sn = g.machine_sn;

-- Field service campaign (FSC) affected serials + completion state.
CREATE OR REPLACE TABLE BRIDGE_CAMPAIGN_MACHINE AS
SELECT c.program_id, c.program_type, c.model, c.system_group_cd,
       dm.machine_key, c.machine_sn, c.open_dt, c.completion_dt,
       c.status, (c.completion_dt IS NOT NULL) AS completed_flag
FROM SF_SOLUTIONS.CQC_STAGING.STG_FIELD_CAMPAIGN c
JOIN DIM_MACHINE dm ON dm.machine_sn = c.machine_sn;

-- verify: exposed fleet for the suspect anchor lots
SELECT 'exposed_to_suspect_lots' AS metric, COUNT(DISTINCT machine_key) AS machines
FROM BRIDGE_LOT_MACHINE WHERE is_suspect
UNION ALL
SELECT 'campaign_affected', COUNT(*) FROM BRIDGE_CAMPAIGN_MACHINE;

-- -------------------------------------------------------------------------
-- Customer archetypes
-- Source: platform/ddl/036_customer_archetype.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ATOMIC;

-- ---------------------------------------------------------------------------
-- Governed reference: the four archetypes as defined by the manufacturer.
-- equip_rev_midpoint drives "relative pain" (impact as a share of the operation).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_ACCOUNT_ARCHETYPE (
    archetype              STRING,   -- ENTERPRISE / NATIONAL / LOCAL / INDEPENDENT
    archetype_rank         NUMBER,   -- 1 = most managed / largest
    account_model          STRING,
    operations_label       STRING,
    size_hint              STRING,
    quality_definition     STRING,
    quality_definition_cd  STRING,   -- PORTFOLIO_TCO / FLEET_UPTIME / COST_PER_HOUR / MACHINE_UPTIME
    pain_channel           STRING,
    pain_channel_cd        STRING,   -- ACCOUNT_TEAM_EXEC / ACCOUNT_MGR_DEALER / DEALER_RELATIONSHIP / SERVICE_COUNTER
    response_mode          STRING,   -- PROACTIVE / MANAGED_REACTIVE / REACTIVE
    equip_rev_midpoint     NUMBER,   -- representative annual equipment revenue (USD)
    pop_pct                NUMBER    -- target share of customer population
);
INSERT INTO REF_ACCOUNT_ARCHETYPE
SELECT 'ENTERPRISE',1,'Strategic Accounts (Manufacturer-led + Dealer support)','Enterprise Operations','Very large ($20M+)',
       'Portfolio-level productivity and total cost of ownership','PORTFOLIO_TCO',
       'account team and executive touchpoints','ACCOUNT_TEAM_EXEC','PROACTIVE',30000000,4
UNION ALL SELECT 'NATIONAL',2,'Corporate Accounts (Manufacturer-led + Dealer as POC)','National Operations','Medium to large ($5M-$20M)',
       'Fleet-wide uptime and site-to-site consistency','FLEET_UPTIME',
       'account manager with dealer coordination','ACCOUNT_MGR_DEALER','PROACTIVE',10000000,13
UNION ALL SELECT 'LOCAL',3,'Regional Accounts (Dealer-led + manufacturer support)','Local Operations','Small to medium ($2.5M-$5M)',
       'Cost-per-hour reliability and predictable service','COST_PER_HOUR',
       'Dealer relationship','DEALER_RELATIONSHIP','MANAGED_REACTIVE',3500000,28
UNION ALL SELECT 'INDEPENDENT',4,'Non-managed Accounts (Dealer-only)','Independent Operators','Single owner-operator',
       'Machine works when needed','MACHINE_UPTIME',
       'Service counter, machine-by-machine','SERVICE_COUNTER','REACTIVE',500000,55;

-- ---------------------------------------------------------------------------
-- Add archetype attributes to DIM_CUSTOMER (idempotent).
-- ---------------------------------------------------------------------------
ALTER TABLE DIM_CUSTOMER ADD COLUMN IF NOT EXISTS account_archetype     STRING;
ALTER TABLE DIM_CUSTOMER ADD COLUMN IF NOT EXISTS management_model       STRING;
ALTER TABLE DIM_CUSTOMER ADD COLUMN IF NOT EXISTS quality_definition_cd  STRING;
ALTER TABLE DIM_CUSTOMER ADD COLUMN IF NOT EXISTS pain_channel_cd        STRING;
ALTER TABLE DIM_CUSTOMER ADD COLUMN IF NOT EXISTS equip_rev_usd          NUMBER;

-- ---------------------------------------------------------------------------
-- Step 1: FIXED DISTRIBUTION assignment (deterministic via MD5 hash percentile).
--   pct 1-55 Independent, 56-83 Local, 84-96 National, 97-100 Enterprise.
-- ---------------------------------------------------------------------------
UPDATE DIM_CUSTOMER c
SET account_archetype = t.archetype
FROM (
    SELECT customer_key,
           CASE
             WHEN pct <= 55 THEN 'INDEPENDENT'
             WHEN pct <= 83 THEN 'LOCAL'
             WHEN pct <= 96 THEN 'NATIONAL'
             ELSE 'ENTERPRISE'
           END AS archetype
    FROM (
        SELECT customer_key, NTILE(100) OVER (ORDER BY MD5(customer_acct)) AS pct
        FROM DIM_CUSTOMER
    )
) t
WHERE t.customer_key = c.customer_key;

-- ---------------------------------------------------------------------------
-- Step 2: ANCHOR BACK-FIT. The 63 lot-exposed LX-950 units each belong to a
-- distinct customer; assign 2 Enterprise / 11 National / 34 Local / 16
-- Independent so "One Defect, Four Customers" lands cleanly.
-- ---------------------------------------------------------------------------
UPDATE DIM_CUSTOMER c
SET account_archetype = t.archetype
FROM (
    WITH exposed AS (
        SELECT DISTINCT dm.customer_acct
        FROM DIM_MACHINE dm
        JOIN BRIDGE_LOT_MACHINE b ON b.machine_key = dm.machine_key
        JOIN DIM_LOT l ON l.lot_key = b.lot_key
        WHERE l.is_suspect = TRUE AND dm.model = 'LX-950'
    ),
    ranked AS (
        SELECT customer_acct, ROW_NUMBER() OVER (ORDER BY MD5(customer_acct)) AS rn
        FROM exposed
    )
    SELECT customer_acct,
           CASE
             WHEN rn <= 2  THEN 'ENTERPRISE'
             WHEN rn <= 13 THEN 'NATIONAL'
             WHEN rn <= 47 THEN 'LOCAL'
             ELSE 'INDEPENDENT'
           END AS archetype
    FROM ranked
) t
WHERE t.customer_acct = c.customer_acct;

-- ---------------------------------------------------------------------------
-- Step 3: denormalize the governed archetype attributes onto each customer.
-- ---------------------------------------------------------------------------
UPDATE DIM_CUSTOMER c
SET management_model      = r.account_model,
    quality_definition_cd = r.quality_definition_cd,
    pain_channel_cd       = r.pain_channel_cd,
    equip_rev_usd         = r.equip_rev_midpoint
FROM REF_ACCOUNT_ARCHETYPE r
WHERE r.archetype = c.account_archetype;

-- ---------------------------------------------------------------------------
-- Validation.
-- ---------------------------------------------------------------------------
SELECT account_archetype, COUNT(*) n,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) pct
FROM DIM_CUSTOMER GROUP BY 1 ORDER BY MIN(equip_rev_usd) DESC;

-- -------------------------------------------------------------------------
-- FEATURE_STORE
-- Source: platform/ddl/040_feature_store.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_FEATURE_STORE;

SET obs_date = DATE '2026-07-15';

CREATE OR REPLACE TABLE FEAT_MACHINE AS
WITH h_all AS (   -- lifetime telematics aggregates
    SELECT machine_sn,
           MAX(op_hours)      AS op_hours_now,
           AVG(load_factor)    AS avg_load_factor,
           AVG(idle_pct)       AS avg_idle_pct,
           AVG(avg_engine_temp) AS life_avg_engine_temp
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_HEALTH_DAILY
    GROUP BY 1
),
h90 AS (          -- last 90 days
    SELECT machine_sn,
           AVG(avg_engine_temp)  AS t90_avg_temp,
           MAX(peak_engine_temp) AS t90_max_temp,
           SUM(derate_events)    AS t90_derate_sum,
           AVG(load_factor)      AS t90_avg_load
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_HEALTH_DAILY
    WHERE event_date > DATEADD('day', -90, $obs_date)
    GROUP BY 1
),
hprior AS (       -- prior 90-180 days (for trend)
    SELECT machine_sn, AVG(avg_engine_temp) AS tprior_avg_temp
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_HEALTH_DAILY
    WHERE event_date BETWEEN DATEADD('day', -180, $obs_date) AND DATEADD('day', -90, $obs_date)
    GROUP BY 1
),
flt90 AS (        -- telematics faults last 90 days
    SELECT machine_sn,
           COUNT(*)                                   AS f90_fault_cnt,
           COUNT_IF(severity_cd = 'HIGH')             AS f90_highsev_cnt,
           COUNT_IF(system_group_cd = 'ENGINE_FUEL')  AS f90_fuel_fault_cnt
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_FAULT
    WHERE event_date > DATEADD('day', -90, $obs_date)
    GROUP BY 1
),
fluid AS (        -- latest Fluid Analysis sample + action count
    SELECT machine_sn,
           MAX_BY(fe_ppm, event_date) AS fluid_fe_ppm,
           MAX_BY(cu_ppm, event_date) AS fluid_cu_ppm,
           MAX_BY(al_ppm, event_date) AS fluid_al_ppm,
           MAX_BY(si_ppm, event_date) AS fluid_si_ppm,
           COUNT_IF(interp_cd = 'action') AS fluid_action_cnt
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_FLUID_SAMPLE
    GROUP BY 1
),
rep AS (          -- prior repair history
    SELECT machine_sn,
           COUNT(*)                                  AS prior_repair_cnt,
           COUNT_IF(system_group_cd = 'ENGINE_FUEL') AS prior_fuel_repair_cnt,
           DATEDIFF('day', MAX(event_date), $obs_date) AS days_since_last_repair
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_SERVICE_REPAIR
    GROUP BY 1
),
suspect AS (      -- carries suspect-lot exposure (EVAL ONLY)
    SELECT DISTINCT machine_key, TRUE AS has_suspect_lot
    FROM SF_SOLUTIONS.CQC_ATOMIC.BRIDGE_LOT_MACHINE WHERE is_suspect
)
SELECT
    m.machine_key, m.machine_sn, m.model, m.product_family,
    c.end_market_cd, m.global_region, m.build_facility_cd,
    TO_CHAR(m.build_dt, 'YYYY-MM')                          AS build_month,
    m.delivery_dt,
    DATEDIFF('day', m.delivery_dt, $obs_date) / 30.44       AS months_in_service,
    COALESCE(h.op_hours_now, 0)                                  AS op_hours_now,
    DIV0(COALESCE(h.op_hours_now,0), GREATEST(DATEDIFF('day', m.delivery_dt, $obs_date),1)) AS op_hours_per_day,
    h.avg_load_factor, h.avg_idle_pct, h.life_avg_engine_temp,
    h90.t90_avg_temp, h90.t90_max_temp, h90.t90_derate_sum, h90.t90_avg_load,
    (h90.t90_avg_temp - hprior.tprior_avg_temp)             AS temp_trend_90d,
    COALESCE(flt90.f90_fault_cnt, 0)                        AS f90_fault_cnt,
    COALESCE(flt90.f90_highsev_cnt, 0)                      AS f90_highsev_cnt,
    COALESCE(flt90.f90_fuel_fault_cnt, 0)                   AS f90_fuel_fault_cnt,
    fluid.fluid_fe_ppm, fluid.fluid_cu_ppm, fluid.fluid_al_ppm, fluid.fluid_si_ppm,
    COALESCE(fluid.fluid_action_cnt, 0)                         AS fluid_action_cnt,
    COALESCE(rep.prior_repair_cnt, 0)                       AS prior_repair_cnt,
    COALESCE(rep.prior_fuel_repair_cnt, 0)                  AS prior_fuel_repair_cnt,
    rep.days_since_last_repair,
    (m.warranty_months IS NOT NULL
        AND DATEDIFF('day', m.warranty_start_dt, $obs_date)/30.44 <= m.warranty_months) AS warranty_active,
    m.ext_coverage_flag, m.service_agreement_flag,
    COALESCE(s.has_suspect_lot, FALSE)                      AS has_suspect_lot   -- EVAL ONLY
FROM SF_SOLUTIONS.CQC_ATOMIC.DIM_MACHINE m
LEFT JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_CUSTOMER c ON c.customer_acct = m.customer_acct
LEFT JOIN h_all h    ON h.machine_sn = m.machine_sn
LEFT JOIN h90        ON h90.machine_sn = m.machine_sn
LEFT JOIN hprior     ON hprior.machine_sn = m.machine_sn
LEFT JOIN flt90      ON flt90.machine_sn = m.machine_sn
LEFT JOIN fluid      ON fluid.machine_sn = m.machine_sn
LEFT JOIN rep        ON rep.machine_sn = m.machine_sn
LEFT JOIN suspect s  ON s.machine_key = m.machine_key;

SELECT COUNT(*) machines,
       ROUND(AVG(months_in_service),1) avg_mis,
       ROUND(AVG(t90_avg_temp),1) avg_t90_temp,
       SUM(IFF(has_suspect_lot,1,0)) suspect_units
FROM FEAT_MACHINE;

SELECT 'CQC data load complete. Next: run scripts/pipeline.sql' AS STATUS;
