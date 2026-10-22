-- =============================================================================
-- Solution: Customer Quality Command (CQC) - pipeline
-- Database: SF_SOLUTIONS
-- Schemas:  CQC_RAW, CQC_STAGING, CQC_ATOMIC, CQC_FEATURE_STORE, CQC_ML, CQC_ANALYTICS, CQC_INSIGHTS, CQC_ACTION, CQC_DOCS
-- Runs the ML suite and builds ANALYTICS, INSIGHTS, ACTION, the semantic view, search and the agent.
-- Run after data.sql. The weekly agent-eval task is created suspended.
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- ML modules 1-4 (Python stored procedures)
CALL SF_SOLUTIONS.CQC_ML.SP_ML_RELIABILITY();
CALL SF_SOLUTIONS.CQC_ML.SP_ML_EMERGING();
CALL SF_SOLUTIONS.CQC_ML.SP_ML_FAILURE_RISK();
CALL SF_SOLUTIONS.CQC_ML.SP_ML_ISSUE_CLUSTERING();

-- -------------------------------------------------------------------------
-- ML module 5: root-cause attribution
-- Source: platform/ddl/045_module5_rootcause.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ML;

CREATE OR REPLACE TABLE ROOT_CAUSE_ATTRIBUTION AS
WITH issue AS (   -- governable issues (match Module 4 grain + id)
    SELECT MD5(model || '|' || system_group_cd || '|' || failure_mode_cd) AS issue_id,
           model, system_group_cd, failure_mode_cd, COUNT(*) issue_events
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT
    WHERE failure_mode_cd IS NOT NULL
    GROUP BY 1,2,3,4 HAVING COUNT(*) >= 40
),
-- machines that experienced each issue's failure mode (service repairs)
failed AS (
    SELECT DISTINCT MD5(sr.model || '|' || sr.system_group_cd || '|' || sr.failure_mode_cd) issue_id,
           sr.model, sr.system_group_cd, sr.failure_mode_cd, sr.machine_key
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_SERVICE_REPAIR sr
    WHERE sr.failure_mode_cd IS NOT NULL
),
-- lot carried by each machine for the issue's system group (from genealogy)
mach_lot AS (
    SELECT g.machine_sn, dm.machine_key, dm.model, sg.system_group_cd,
           g.supplier_lot_no, g.supplier_id, g.build_facility_cd
    FROM SF_SOLUTIONS.CQC_STAGING.STG_GENEALOGY g
    JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_MACHINE dm ON dm.machine_sn = g.machine_sn
    JOIN SF_SOLUTIONS.CQC_STAGING.MAP_SYSTEM_GROUP sg ON sg.raw_system_group = g.system_group_raw
),
-- fleet count per (model, system_group, lot)
fleet_lot AS (
    SELECT model, system_group_cd, supplier_lot_no, supplier_id, build_facility_cd,
           COUNT(DISTINCT machine_key) fleet_n
    FROM mach_lot GROUP BY 1,2,3,4,5
),
-- fleet totals per (model, system_group)
fleet_tot AS (
    SELECT model, system_group_cd, COUNT(DISTINCT machine_key) fleet_total
    FROM mach_lot GROUP BY 1,2
),
-- failures per (issue, lot)
fail_lot AS (
    SELECT f.issue_id, f.model, f.system_group_cd, f.failure_mode_cd,
           ml.supplier_lot_no, COUNT(DISTINCT f.machine_key) fail_n
    FROM failed f JOIN mach_lot ml
      ON ml.machine_key = f.machine_key AND ml.model = f.model AND ml.system_group_cd = f.system_group_cd
    GROUP BY 1,2,3,4,5
),
issue_fail_tot AS (
    SELECT issue_id, COUNT(DISTINCT machine_key) issue_fail_total
    FROM failed GROUP BY 1
)
SELECT
    fl.issue_id, fl.model, fl.system_group_cd, fl.failure_mode_cd,
    'LOT' AS attribution_type,
    fl.supplier_lot_no AS attribution_value,
    flot.supplier_id, flot.build_facility_cd,
    flot.fleet_n AS fleet_with_attr,
    ft.fleet_total,
    fl.fail_n AS failures_with_attr,
    ift.issue_fail_total,
    -- expected failures on this lot = issue failures * (lot fleet share)
    ROUND(ift.issue_fail_total * (flot.fleet_n / NULLIF(ft.fleet_total,0)), 2) AS expected_failures,
    ROUND(fl.fail_n / NULLIF(ift.issue_fail_total * (flot.fleet_n / NULLIF(ft.fleet_total,0)), 0), 2) AS lift,
    ROUND((fl.fail_n - ift.issue_fail_total * (flot.fleet_n / NULLIF(ft.fleet_total,0)))
          / NULLIF(SQRT(ift.issue_fail_total * (flot.fleet_n / NULLIF(ft.fleet_total,0))),0), 2) AS z_score,
    (((fl.fail_n - ift.issue_fail_total * (flot.fleet_n / NULLIF(ft.fleet_total,0)))
          / NULLIF(SQRT(ift.issue_fail_total * (flot.fleet_n / NULLIF(ft.fleet_total,0))),0)) > 3
     AND fl.fail_n >= 5) AS is_significant,
    (fl.supplier_lot_no IN ('L-4471','L-4472','L-4480')) AS is_suspect_seed
FROM fail_lot fl
JOIN fleet_lot flot ON flot.model=fl.model AND flot.system_group_cd=fl.system_group_cd AND flot.supplier_lot_no=fl.supplier_lot_no
JOIN fleet_tot ft ON ft.model=fl.model AND ft.system_group_cd=fl.system_group_cd
JOIN issue_fail_tot ift ON ift.issue_id=fl.issue_id
WHERE fl.fail_n >= 3;

-- validation: significant lot concentrations, anchor first
SELECT model, failure_mode_cd, attribution_value, build_facility_cd,
       failures_with_attr, expected_failures, lift, z_score, is_significant, is_suspect_seed
FROM ROOT_CAUSE_ATTRIBUTION
WHERE is_significant ORDER BY z_score DESC LIMIT 12;

-- ML module 7: Monte-Carlo exposure (Python stored procedure)
CALL SF_SOLUTIONS.CQC_ML.SP_ML_EXPOSURE();

-- -------------------------------------------------------------------------
-- ML module 6: safety-gated prioritization
-- Source: platform/ddl/046_module6_prioritization.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ML;

-- value-of-uptime ($/downtime-hour) by end-market (documented assumptions)
CREATE OR REPLACE TABLE REF_VALUE_OF_UPTIME (end_market_cd STRING, usd_per_hour NUMBER);
INSERT INTO REF_VALUE_OF_UPTIME
SELECT 'QUARRY_AGG',650 UNION ALL SELECT 'RENTAL',500 UNION ALL SELECT 'INFRASTRUCTURE',450
UNION ALL SELECT 'NONRES_BUILDING',400 UNION ALL SELECT 'RESIDENTIAL',300;

-- ---- issue base + drivers from the event spine ----
CREATE OR REPLACE TEMP TABLE _issue_drivers AS
WITH ev AS (
    SELECT MD5(e.model || '|' || e.system_group_cd || '|' || e.failure_mode_cd) issue_id,
           e.model, e.system_group_cd, e.failure_mode_cd, e.quality_dimension_cd,
           e.machine_key, e.customer_key, e.severity_cd,
           COALESCE(e.downtime_hours,0) downtime_hours, COALESCE(e.repair_cost_usd,0) repair_cost,
           e.injury_flag, e.sif_potential_flag, e.source_system,
           c.end_market_cd
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT e
    LEFT JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_CUSTOMER c ON c.customer_key = e.customer_key
    WHERE e.failure_mode_cd IS NOT NULL
)
SELECT issue_id,
       ANY_VALUE(model) model, ANY_VALUE(system_group_cd) system_group_cd,
       ANY_VALUE(failure_mode_cd) failure_mode_cd, MODE(quality_dimension_cd) dimension,
       COUNT(*) events, COUNT(DISTINCT machine_key) fleet, COUNT(DISTINCT customer_key) customers,
       SUM(IFF(sif_potential_flag,1,0)) sif_events, SUM(IFF(injury_flag,1,0)) injury_events,
       SUM(IFF(quality_dimension_cd='SAFETY',1,0)) safety_events,
       SUM(downtime_hours) downtime_hours, SUM(repair_cost) repair_cost,
       SUM(downtime_hours * COALESCE(v.usd_per_hour,400)) downtime_value
FROM ev LEFT JOIN REF_VALUE_OF_UPTIME v ON v.end_market_cd = ev.end_market_cd
GROUP BY issue_id
HAVING COUNT(*) >= 40;

-- ---- SIP (Bayesian rare-event risk) ----
CREATE OR REPLACE TABLE PRO_SIF_RISK AS
SELECT issue_id, model, failure_mode_cd, fleet, sif_events, injury_events,
       ROUND((sif_events + 1.0) / (fleet + 2.0), 5) AS p_sif_posterior,   -- Beta(1,1) prior
       ROUND(((sif_events + 1.0) / (fleet + 2.0)) * fleet * (1 + injury_events), 3) AS pro_sif_risk
FROM _issue_drivers;

-- ---- VTC (monetized productivity impact) ----
CREATE OR REPLACE TABLE VTC_ESTIMATE AS
SELECT issue_id, model, failure_mode_cd, downtime_hours, repair_cost, downtime_value,
       ROUND(downtime_value + repair_cost, 0) AS vtc_usd,
       ROUND((downtime_value + repair_cost) * 0.75, 0) AS vtc_p50,
       ROUND((downtime_value + repair_cost) * 1.30, 0) AS vtc_p90   -- simple dispersion band
FROM _issue_drivers;

-- ---- CEI (experience): NPS delta of affected customers + AI_SENTIMENT ----
CREATE OR REPLACE TABLE CEI_SCORE AS
WITH overall AS (SELECT AVG(nps) avg_nps FROM SF_SOLUTIONS.CQC_STAGING.STG_VOC_SURVEY),
issue_cust AS (
    SELECT DISTINCT d.issue_id, e.customer_key
    FROM _issue_drivers d
    JOIN SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT e
      ON MD5(e.model||'|'||e.system_group_cd||'|'||e.failure_mode_cd) = d.issue_id
),
nps AS (
    SELECT ic.issue_id, AVG(v.nps) issue_nps, COUNT(*) responses
    FROM issue_cust ic
    JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_CUSTOMER c ON c.customer_key = ic.customer_key
    JOIN SF_SOLUTIONS.CQC_STAGING.STG_VOC_SURVEY v ON v.customer_acct = c.customer_acct
    GROUP BY 1
)
SELECT d.issue_id, d.model, d.failure_mode_cd,
       ROUND(n.issue_nps,1) issue_avg_nps, ROUND(o.avg_nps,1) fleet_avg_nps,
       ROUND(n.issue_nps - o.avg_nps, 1) nps_delta,
       ROUND(GREATEST(0, (o.avg_nps - n.issue_nps)) * LN(d.customers + 1), 2) AS cei_impact
FROM _issue_drivers d
LEFT JOIN nps n ON n.issue_id = d.issue_id
CROSS JOIN overall o;

-- ---- Composite: safety-gated lexicographic ranking ----
CREATE OR REPLACE TABLE SF_SOLUTIONS.CQC_ANALYTICS.CUSTOMER_IMPACT_SCORE AS
SELECT
    d.issue_id, d.model, d.system_group_cd, d.failure_mode_cd, d.dimension,
    d.events, d.fleet, d.customers,
    ps.pro_sif_risk, ps.p_sif_posterior,
    vt.vtc_usd, vt.vtc_p50, vt.vtc_p90,
    ce.cei_impact, ce.nps_delta,
    CASE d.dimension WHEN 'SAFETY' THEN 1 WHEN 'PRODUCTIVITY' THEN 2 ELSE 3 END AS priority_tier,
    -- within-tier magnitude used for lexicographic ordering
    CASE d.dimension WHEN 'SAFETY' THEN ps.pro_sif_risk
                     WHEN 'PRODUCTIVITY' THEN vt.vtc_usd
                     ELSE ce.cei_impact END AS primary_magnitude,
    ROW_NUMBER() OVER (
        ORDER BY CASE d.dimension WHEN 'SAFETY' THEN 1 WHEN 'PRODUCTIVITY' THEN 2 ELSE 3 END,
                 CASE d.dimension WHEN 'SAFETY' THEN ps.pro_sif_risk
                                  WHEN 'PRODUCTIVITY' THEN vt.vtc_usd
                                  ELSE ce.cei_impact END DESC
    ) AS priority_rank
FROM _issue_drivers d
LEFT JOIN PRO_SIF_RISK ps ON ps.issue_id = d.issue_id
LEFT JOIN VTC_ESTIMATE vt ON vt.issue_id = d.issue_id
LEFT JOIN CEI_SCORE ce ON ce.issue_id = d.issue_id;

-- validation: top-10 prioritized issues (safety should lead), anchor visible
SELECT priority_rank, model, failure_mode_cd, dimension, fleet,
       pro_sif_risk, vtc_usd, cei_impact
FROM SF_SOLUTIONS.CQC_ANALYTICS.CUSTOMER_IMPACT_SCORE
ORDER BY priority_rank LIMIT 10;

-- -------------------------------------------------------------------------
-- ML module 8: recommended actions
-- Source: platform/ddl/047_module8_actions.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ML;

CREATE OR REPLACE TABLE RECOMMENDED_ACTIONS AS
WITH iss AS (
    SELECT s.issue_id, s.model, s.system_group_cd, s.failure_mode_cd, s.dimension,
           s.fleet, s.priority_rank, s.vtc_usd, s.pro_sif_risk,
           COALESCE(x.exposure_p90,0) exposure_p90, COALESCE(x.exposed_fleet,0) exposed_fleet,
           COALESCE(rc.has_lot, FALSE) has_significant_lot,
           rc.top_lot, rc.top_facility
    FROM SF_SOLUTIONS.CQC_ANALYTICS.CUSTOMER_IMPACT_SCORE s
    LEFT JOIN SF_SOLUTIONS.CQC_ML.EXPOSURE_SIMULATION x ON x.issue_id = s.issue_id
    LEFT JOIN (
        SELECT issue_id, TRUE has_lot,
               MAX_BY(attribution_value, z_score) top_lot,
               MAX_BY(build_facility_cd, z_score) top_facility
        FROM SF_SOLUTIONS.CQC_ML.ROOT_CAUSE_ATTRIBUTION WHERE is_significant GROUP BY 1
    ) rc ON rc.issue_id = s.issue_id
),
acts AS (
    -- Rule 1: lot-concentrated -> CONTAINMENT (supply chain)
    SELECT issue_id, 1 action_seq,
           CASE WHEN dimension='SAFETY' THEN '0-24h' ELSE '24-48h' END time_window,
           'CONTAINMENT' action_type,
           'Contain suspect lot ' || top_lot || ' (' || top_facility || '); quarantine inventory + notify plant QC' title,
           'supply_chain' owner_persona,
           exposure_p90 expected_impact_usd, 0.70 risk_reduction_pct
    FROM iss WHERE has_significant_lot
    UNION ALL
    -- Rule 2: safety dimension -> IMMEDIATE field/operator action + program
    SELECT issue_id, 2, '0-24h', 'SAFETY_FIELD_ACTION',
           'Issue operator safety advisory + expedite field inspection; evaluate field service campaign (FSC)' ,
           'product', pro_sif_risk * 1000, 0.60
    FROM iss WHERE dimension='SAFETY'
    UNION ALL
    -- Rule 3: high productivity impact w/o lot cause -> DESIGN/SERVICE
    SELECT issue_id, 3, '48-72h',
           CASE WHEN NOT has_significant_lot THEN 'DESIGN_REVIEW' ELSE 'SERVICE_CAPACITY' END,
           CASE WHEN NOT has_significant_lot
                THEN 'Open design/reliability review; broad failure pattern not lot-isolated'
                ELSE 'Stage parts + add service capacity in affected regions' END,
           'product', vtc_usd, 0.35
    FROM iss WHERE dimension='PRODUCTIVITY' AND vtc_usd > 50000
    UNION ALL
    -- Rule 4: experience -> dealer outreach
    SELECT issue_id, 4, '48-72h', 'CUSTOMER_OUTREACH',
           'Proactive dealer outreach to affected detractor accounts; loyalty recovery',
           'dealer', 0, 0.25
    FROM iss WHERE dimension='EXPERIENCE'
)
SELECT a.*, i.model, i.failure_mode_cd, i.dimension, i.priority_rank,
       'RECOMMENDED' AS status
FROM acts a JOIN iss i USING (issue_id);

-- SP_RECOMMEND_ACTIONS(issue_id) — agent-callable. Agent procedure tools need a
-- single-cell result, so this returns a JSON array with one object per action.
CREATE OR REPLACE PROCEDURE SP_RECOMMEND_ACTIONS(ISSUE_ID STRING)
RETURNS VARIANT
LANGUAGE SQL AS
$$
DECLARE payload VARIANT;
BEGIN
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(
               'action_seq', action_seq, 'time_window', time_window, 'action_type', action_type,
               'title', title, 'owner_persona', owner_persona,
               'expected_impact_usd', expected_impact_usd::FLOAT, 'risk_reduction_pct', risk_reduction_pct::FLOAT))
           WITHIN GROUP (ORDER BY action_seq)
      INTO :payload
      FROM SF_SOLUTIONS.CQC_ML.RECOMMENDED_ACTIONS WHERE issue_id = :ISSUE_ID;
    RETURN payload;
END;
$$;

-- SP_ALLOCATE_RESOURCES(capacity) — greedy knapsack: allocate limited field/containment
-- units to the highest risk-reduction-per-unit issues (safety-first).
-- Returns a JSON array (single cell) so it can be used as an agent procedure tool.
CREATE OR REPLACE PROCEDURE SP_ALLOCATE_RESOURCES(CAPACITY_UNITS NUMBER)
RETURNS VARIANT
LANGUAGE SQL AS
$$
DECLARE payload VARIANT;
BEGIN
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(
               'priority_rank', priority_rank, 'model', model, 'failure_mode_cd', failure_mode_cd,
               'dimension', dimension, 'action_type', action_type,
               'expected_impact_usd', expected_impact_usd::FLOAT, 'units_allocated', 1, 'cum_units', cum_units))
           WITHIN GROUP (ORDER BY priority_rank)
      INTO :payload
      FROM (
        SELECT i.priority_rank, i.model, i.failure_mode_cd, i.dimension, a.action_type,
               a.expected_impact_usd,
               SUM(1) OVER (ORDER BY i.priority_rank ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) cum_units
        FROM SF_SOLUTIONS.CQC_ANALYTICS.CUSTOMER_IMPACT_SCORE i
        -- each issue's first action (action_seq numbering varies by action type)
        JOIN (SELECT * FROM SF_SOLUTIONS.CQC_ML.RECOMMENDED_ACTIONS
              QUALIFY ROW_NUMBER() OVER (PARTITION BY issue_id ORDER BY action_seq) = 1) a
          ON a.issue_id = i.issue_id
      ) ranked
     WHERE cum_units <= :CAPACITY_UNITS;
    RETURN payload;
END;
$$;

SELECT dimension, action_type, COUNT(*) n FROM RECOMMENDED_ACTIONS GROUP BY 1,2 ORDER BY 1,3 DESC;

-- -------------------------------------------------------------------------
-- ANALYTICS issue entity and rollups
-- Source: platform/ddl/048_analytics_issue.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ANALYTICS;

-- ---------------------------------------------------------------------------
-- CQC_ANALYTICS.ISSUE — hero entity (one row per governable issue)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE ISSUE AS
SELECT
    ic.issue_id, ic.model, dm.product_family,
    ic.system_group_cd, ic.system_group_name, ic.failure_mode_cd, ic.failure_mode_name,
    ic.dimension, ic.brief, ic.cluster_id,
    ic.events, ic.fleet, cis.customers, ic.first_seen, ic.last_seen,
    cis.priority_rank, cis.priority_tier,
    cis.pro_sif_risk, cis.p_sif_posterior,
    cis.vtc_usd, cis.vtc_p50, cis.vtc_p90, cis.cei_impact, cis.nps_delta,
    ex.exposure_p50, ex.exposure_p90, ex.exposure_cvar95, ex.exposed_fleet,
    rc.top_lot AS root_cause_lot, rc.top_facility AS root_cause_facility,
    rc.top_lift AS root_cause_lift, (rc.issue_id IS NOT NULL) AS is_lot_concentrated,
    em.changepoint_month AS emerging_changepoint,
    CASE WHEN cis.priority_rank <= 15 THEN 'IN_PROGRESS' ELSE 'MONITORING' END AS status
FROM SF_SOLUTIONS.CQC_ML.ISSUE_CLUSTERS ic
LEFT JOIN SF_SOLUTIONS.CQC_ANALYTICS.CUSTOMER_IMPACT_SCORE cis ON cis.issue_id = ic.issue_id
LEFT JOIN SF_SOLUTIONS.CQC_ML.EXPOSURE_SIMULATION ex ON ex.issue_id = ic.issue_id
LEFT JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_MODEL dm ON dm.model = ic.model
LEFT JOIN (
    SELECT issue_id, MAX_BY(attribution_value, z_score) top_lot,
           MAX_BY(build_facility_cd, z_score) top_facility, MAX(lift) top_lift
    FROM SF_SOLUTIONS.CQC_ML.ROOT_CAUSE_ATTRIBUTION WHERE is_significant GROUP BY 1
) rc ON rc.issue_id = ic.issue_id
LEFT JOIN (
    SELECT model, system_group_cd, MAX_BY(event_month, cusum) changepoint_month
    FROM SF_SOLUTIONS.CQC_ML.EMERGING_ISSUE_SIGNALS WHERE is_changepoint GROUP BY 1,2
) em ON em.model = ic.model AND em.system_group_cd = ic.system_group_cd;

-- ---------------------------------------------------------------------------
-- IMPACTED_* rollups (per issue) — command dashboard tiles
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE IMPACTED_CUSTOMERS AS
SELECT MD5(e.model||'|'||e.system_group_cd||'|'||e.failure_mode_cd) issue_id,
       e.customer_key, c.name customer_name, c.end_market_cd, c.us_subregion,
       COUNT(DISTINCT e.machine_key) units_impacted, COUNT(*) events
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT e
JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_CUSTOMER c ON c.customer_key = e.customer_key
WHERE e.failure_mode_cd IS NOT NULL
GROUP BY 1,2,3,4,5;

CREATE OR REPLACE TABLE IMPACTED_DEALERS AS
SELECT MD5(e.model||'|'||e.system_group_cd||'|'||e.failure_mode_cd) issue_id,
       e.dealer_key, d.name dealer_name, d.us_subregion,
       COUNT(DISTINCT e.machine_key) units_impacted, COUNT(*) events
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT e
JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_DEALER d ON d.dealer_key = e.dealer_key
WHERE e.failure_mode_cd IS NOT NULL
GROUP BY 1,2,3,4;

CREATE OR REPLACE TABLE IMPACTED_FACILITIES AS
SELECT MD5(b.model||'|'||b.system_group_cd||'|'||b.failure_mode_cd) issue_id,
       b.build_facility_key, f.facility_name,
       COUNT(DISTINCT b.machine_key) units_built, ANY_VALUE(b.build_facility_key) fk
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT b
JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_FACILITY f ON f.facility_key = b.build_facility_key
WHERE b.failure_mode_cd IS NOT NULL AND b.build_facility_key IS NOT NULL
GROUP BY 1,2,3;

CREATE OR REPLACE TABLE IMPACTED_AREAS AS
SELECT MD5(e.model||'|'||e.system_group_cd||'|'||e.failure_mode_cd) issue_id,
       g.us_subregion area, g.global_region,
       COUNT(DISTINCT e.machine_key) units_impacted, COUNT(*) events
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT e
JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_GEOGRAPHY g ON g.geography_key = e.geography_key
WHERE e.failure_mode_cd IS NOT NULL
GROUP BY 1,2,3;

-- ---------------------------------------------------------------------------
-- Persona + ideal-state metric views (§5)
-- ---------------------------------------------------------------------------
-- Dealer: PDI red-rate
CREATE OR REPLACE VIEW V_METRIC_PDI AS
SELECT dealer_key, model, COUNT(*) inspections,
       ROUND(100.0*COUNT_IF(condition_rating='RED')/COUNT(*),2) pdi_red_pct
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_PDI_RESULT WHERE inspect_type='PDI' GROUP BY 1,2;

-- Product: MTTR (repair labor proxy) + MTBF (from Module 1)
CREATE OR REPLACE VIEW V_METRIC_MTTR AS
SELECT model, system_group_cd, ROUND(AVG(labor_hrs),2) mttr_hours, COUNT(*) repairs
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_SERVICE_REPAIR GROUP BY 1,2;
CREATE OR REPLACE VIEW V_METRIC_MTBF AS
SELECT model, system_group_cd, mtbf_hours, beta, eta, n_events
FROM SF_SOLUTIONS.CQC_ML.MTBF_ESTIMATES;

-- Manufacturing: rework minutes / first-pass yield
CREATE OR REPLACE VIEW V_METRIC_REWORK AS
SELECT facility_key, facility_cd, model, COUNT(*) tests,
       ROUND(100.0*COUNT_IF(result='PASS')/COUNT(*),2) first_pass_yield_pct,
       ROUND(SUM(rework_min),1) total_rework_min
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_MES_QUALITY q
JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_MACHINE m USING (machine_key)
GROUP BY 1,2,3;

-- Supply Chain: SQPI composite (PPM + SCAR responsiveness + lot escape)
CREATE OR REPLACE VIEW V_METRIC_SQPI AS
WITH ppm AS (
    SELECT supplier_id, SUM(qty_reject)*1e6/NULLIF(SUM(qty_recv),0) ppm
    FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_SUPPLIER_QUALITY GROUP BY 1),
scar AS (
    SELECT supplier_id, COUNT(*) scars, COUNT_IF(status='OPEN') open_scars
    FROM SF_SOLUTIONS.CQC_STAGING.STG_SUPPLIER_SCAR GROUP BY 1)
SELECT p.supplier_id, ROUND(p.ppm,1) ppm, COALESCE(s.scars,0) scars, COALESCE(s.open_scars,0) open_scars,
       ROUND(GREATEST(0, 100 - p.ppm/200 - COALESCE(s.open_scars,0)*5),1) sqpi_score
FROM ppm p LEFT JOIN scar s USING (supplier_id);

-- Executive: downtime / availability
CREATE OR REPLACE VIEW V_METRIC_DOWNTIME AS
SELECT model, ROUND(AVG(idle_pct),2) avg_idle_pct, ROUND(AVG(derate_events),3) avg_derate,
       COUNT(DISTINCT machine_sn) machines
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_HEALTH_DAILY GROUP BY 1;

SELECT 'ISSUE' t, COUNT(*) n FROM ISSUE
UNION ALL SELECT 'IMPACTED_CUSTOMERS', COUNT(*) FROM IMPACTED_CUSTOMERS
UNION ALL SELECT 'IMPACTED_AREAS', COUNT(*) FROM IMPACTED_AREAS;

-- -------------------------------------------------------------------------
-- Agent-callable procedures
-- Source: platform/ddl/049_ml_procs.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ML;

-- Agent procedure tools need a single-cell result, so the agent-callable procs below
-- (SP_DETECT_EMERGING_ISSUES, SP_SIMULATE_EXPOSURE) return a JSON array of row objects.

-- Emerging issues currently alarming (most recent 6 months), ranked by CUSUM.
CREATE OR REPLACE PROCEDURE SP_DETECT_EMERGING_ISSUES()
RETURNS VARIANT
LANGUAGE SQL AS
$$
DECLARE payload VARIANT;
BEGIN
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(
               'model', s.model, 'system_group_cd', s.system_group_cd, 'event_month', s.event_month::DATE,
               'rate_per_1k', s.rate_per_1k::FLOAT, 'baseline_rate', s.baseline_rate::FLOAT,
               'cusum', s.cusum::FLOAT, 'changepoint_month', cp.changepoint_month::DATE,
               'lift', ROUND(s.rate_per_1k / NULLIF(s.baseline_rate,0), 2)::FLOAT))
           WITHIN GROUP (ORDER BY s.cusum DESC)
      INTO :payload
      FROM SF_SOLUTIONS.CQC_ML.EMERGING_ISSUE_SIGNALS s
      JOIN (SELECT model, system_group_cd, MAX(event_month) mx
              FROM SF_SOLUTIONS.CQC_ML.EMERGING_ISSUE_SIGNALS GROUP BY 1,2) l
        ON l.model=s.model AND l.system_group_cd=s.system_group_cd
       AND s.event_month >= DATEADD('month',-6,l.mx)
      LEFT JOIN (SELECT model, system_group_cd, MAX_BY(event_month, cusum) changepoint_month
                   FROM SF_SOLUTIONS.CQC_ML.EMERGING_ISSUE_SIGNALS WHERE is_changepoint GROUP BY 1,2) cp
        ON cp.model=s.model AND cp.system_group_cd=s.system_group_cd
     WHERE s.alarm = 1;
    RETURN payload;
END;
$$;

-- Full S/P/E score + priority for one issue.
CREATE OR REPLACE PROCEDURE SP_SCORE_ISSUE(ISSUE_ID STRING)
RETURNS TABLE (dimension STRING, priority_rank NUMBER, pro_sif_risk FLOAT, p_sif_posterior FLOAT,
               vtc_usd FLOAT, vtc_p50 FLOAT, vtc_p90 FLOAT, cei_impact FLOAT, nps_delta FLOAT)
LANGUAGE SQL AS
$$
DECLARE res RESULTSET DEFAULT (
    SELECT dimension, priority_rank::NUMBER, pro_sif_risk::FLOAT, p_sif_posterior::FLOAT, vtc_usd::FLOAT,
           vtc_p50::FLOAT, vtc_p90::FLOAT, cei_impact::FLOAT, nps_delta::FLOAT
    FROM SF_SOLUTIONS.CQC_ANALYTICS.CUSTOMER_IMPACT_SCORE WHERE issue_id = :ISSUE_ID);
BEGIN RETURN TABLE(res); END;
$$;

-- Exposure P50/P90/CVaR for one issue (from Module 7 simulation).
CREATE OR REPLACE PROCEDURE SP_SIMULATE_EXPOSURE(ISSUE_ID STRING)
RETURNS VARIANT
LANGUAGE SQL AS
$$
DECLARE payload VARIANT;
BEGIN
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(
               'exposed_fleet', exposed_fleet, 'p_fail_forward', p_fail_forward::FLOAT,
               'exposure_mean', exposure_mean::FLOAT, 'exposure_p50', exposure_p50::FLOAT,
               'exposure_p90', exposure_p90::FLOAT, 'exposure_cvar95', exposure_cvar95::FLOAT,
               'copula', copula))
      INTO :payload
      FROM SF_SOLUTIONS.CQC_ML.EXPOSURE_SIMULATION WHERE issue_id = :ISSUE_ID;
    RETURN payload;
END;
$$;

-- smoke test the procs on the anchor issue
CALL SP_DETECT_EMERGING_ISSUES();

-- -------------------------------------------------------------------------
-- INSIGHTS issue hub
-- Source: platform/ddl/050_insights_issue.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_INSIGHTS;

CREATE OR REPLACE TABLE INSIGHT_ISSUE AS
WITH dq AS (   -- data completeness from staging DQ (1 - avg failure rate)
    SELECT 1 - COALESCE(AVG(rate), 0) AS completeness FROM SF_SOLUTIONS.CQC_STAGING.STG_DQ_CHECKS
),
rel AS (       -- reliability params per issue grain
    SELECT MD5(model||'|'||system_group_cd||'|'||failure_mode_cd) issue_id,
           beta, eta, mtbf_hours, infant_mortality_flag
    FROM SF_SOLUTIONS.CQC_ML.RELIABILITY_PARAMS
),
conc AS (      -- top significant concentration per issue
    SELECT issue_id, MAX_BY(attribution_value, z_score) lot, MAX_BY(build_facility_cd, z_score) facility,
           MAX(lift) lift, MAX(z_score) z, MAX(failures_with_attr) obs
    FROM SF_SOLUTIONS.CQC_ML.ROOT_CAUSE_ATTRIBUTION WHERE is_significant GROUP BY 1
),
emg AS (       -- detector signal per model x system_group
    SELECT model, system_group_cd, MAX_BY(event_month, cusum) changepoint_month, MAX(cusum) max_cusum
    FROM SF_SOLUTIONS.CQC_ML.EMERGING_ISSUE_SIGNALS WHERE alarm=1 GROUP BY 1,2
),
mttr AS (
    SELECT model, system_group_cd, AVG(labor_hrs) mttr_hours FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_SERVICE_REPAIR GROUP BY 1,2
),
impc AS (SELECT issue_id, COUNT(*) c FROM SF_SOLUTIONS.CQC_ANALYTICS.IMPACTED_CUSTOMERS GROUP BY 1),
impd AS (SELECT issue_id, COUNT(*) c FROM SF_SOLUTIONS.CQC_ANALYTICS.IMPACTED_DEALERS GROUP BY 1),
impf AS (SELECT issue_id, COUNT(*) c FROM SF_SOLUTIONS.CQC_ANALYTICS.IMPACTED_FACILITIES GROUP BY 1),
acts AS (SELECT issue_id, COUNT(*) c, MIN(time_window) nxt FROM SF_SOLUTIONS.CQC_ML.RECOMMENDED_ACTIONS GROUP BY 1),
topgeo AS (
    SELECT issue_id, MAX_BY(area, units_impacted) area FROM SF_SOLUTIONS.CQC_ANALYTICS.IMPACTED_AREAS GROUP BY 1
)
SELECT
    i.issue_id,
    i.first_seen AS first_detected_ts, CURRENT_TIMESTAMP() AS updated_ts,
    i.model || ' ' || i.system_group_name || ' — ' || i.failure_mode_name AS title,
    i.brief AS summary_text,
    CASE WHEN i.priority_rank <= 15 THEN 'IN_PROGRESS' ELSE 'TRIAGED' END AS status,
    CASE WHEN i.is_lot_concentrated THEN 'CONFIRMED'
         WHEN emg.changepoint_month IS NOT NULL THEN 'EMERGING' ELSE 'CONFIRMED' END AS lifecycle_stage,
    -- classification & priority
    i.dimension AS quality_dimension, i.priority_rank,
    COALESCE(i.pro_sif_risk, i.vtc_usd, i.cei_impact) AS priority_score,
    -- what / where
    i.product_family, i.model, i.system_group_cd AS system_group, i.failure_mode_cd AS failure_mode,
    COALESCE(i.exposed_fleet, i.fleet) AS exposed_fleet_count,
    COALESCE(impc.c, i.customers) AS impacted_customer_count,
    COALESCE(impd.c, 0) AS impacted_dealer_count,
    COALESCE(impf.c, 0) AS impacted_facility_count,
    topgeo.area AS geography_top,
    -- root cause
    CASE WHEN i.is_lot_concentrated THEN 'LOT'
         WHEN i.fleet > 500 THEN 'DESIGN' ELSE 'ISOLATED' END AS root_cause_type,
    CASE WHEN i.is_lot_concentrated
         THEN 'Failures concentrated on supplier lot ' || i.root_cause_lot || ' built at ' || i.root_cause_facility
              || ' (lift ' || ROUND(i.root_cause_lift,1) || 'x)'
         ELSE 'No single lot/plant concentration; broad-population pattern' END AS root_cause_summary,
    CASE WHEN conc.z >= 5 THEN 0.95 WHEN conc.z >= 3 THEN 0.8 ELSE 0.4 END AS root_cause_confidence,
    i.root_cause_lot AS lot_key, conc.facility AS build_facility_key,
    -- business impact
    i.pro_sif_risk, i.p_sif_posterior AS sif_rate,
    i.vtc_usd, i.vtc_p50, i.vtc_p90,
    i.cei_impact AS cei_score, i.nps_delta,
    i.exposure_p50 AS warranty_exposure_p50, i.exposure_p90 AS warranty_exposure_p90,
    i.exposure_cvar95 AS warranty_exposure_cvar,
    -- headline persona metrics (denormalized)
    rel.mtbf_hours AS mtbf, ROUND(mttr.mttr_hours,2) AS mttr,
    -- explainability-as-data
    OBJECT_CONSTRUCT(
        'detector', OBJECT_CONSTRUCT('signal','CUSUM breakout','changepoint',
            TO_CHAR(emg.changepoint_month,'YYYY-MM'),'max_cusum', ROUND(emg.max_cusum,2)),
        'concentration', IFF(i.is_lot_concentrated, OBJECT_CONSTRUCT('dimension','supplier_lot',
            'value', i.root_cause_lot,'facility', i.root_cause_facility,'stat','funnel_zscore',
            'z_score', ROUND(conc.z,2),'lift', ROUND(conc.lift,2),'observed', conc.obs), NULL),
        'reliability', OBJECT_CONSTRUCT('beta', rel.beta,'eta_hours', rel.eta,
            'mtbf_hours', ROUND(rel.mtbf_hours,0),
            'interpretation', IFF(rel.infant_mortality_flag,'infant mortality (beta<1)','wear-out (beta>1)')),
        'exposure', OBJECT_CONSTRUCT('p50_usd', i.exposure_p50,'p90_usd', i.exposure_p90,'cvar_usd', i.exposure_cvar95),
        'exposed_fleet', COALESCE(i.exposed_fleet, i.fleet),
        'impact', OBJECT_CONSTRUCT('vtc_usd', i.vtc_usd,'pro_sif_risk', i.pro_sif_risk,'nps_delta', i.nps_delta),
        'support', OBJECT_CONSTRUCT('events', i.events,'fleet', i.fleet,'customers', i.customers)
    ) AS evidence,
    CAST(NULL AS STRING) AS rationale_text,
    CAST(NULL AS TIMESTAMP_NTZ) AS rationale_generated_ts,
    ROUND(LEAST(0.98, (0.55 + 0.08 * LN(i.events + 1)) * (SELECT completeness FROM dq)), 3) AS data_confidence,
    CASE WHEN (0.55 + 0.08*LN(i.events+1)) * (SELECT completeness FROM dq) >= 0.85 THEN 'HIGH'
         WHEN (0.55 + 0.08*LN(i.events+1)) * (SELECT completeness FROM dq) >= 0.7  THEN 'MED' ELSE 'LOW' END AS data_confidence_band,
    OBJECT_CONSTRUCT('models', ARRAY_CONSTRUCT('FAILURE_RISK_MODEL:V1','EXPOSURE_SIMULATOR:V1'),
        'reliability_fit','lifelines_weibull','built_ts', CURRENT_TIMESTAMP()::STRING) AS provenance,
    COALESCE(acts.c, 0) AS recommended_action_count,
    acts.nxt AS next_action_window
FROM SF_SOLUTIONS.CQC_ANALYTICS.ISSUE i
LEFT JOIN rel ON rel.issue_id = i.issue_id
LEFT JOIN conc ON conc.issue_id = i.issue_id
LEFT JOIN emg ON emg.model = i.model AND emg.system_group_cd = i.system_group_cd
LEFT JOIN mttr ON mttr.model = i.model AND mttr.system_group_cd = i.system_group_cd
LEFT JOIN impc ON impc.issue_id = i.issue_id
LEFT JOIN impd ON impd.issue_id = i.issue_id
LEFT JOIN impf ON impf.issue_id = i.issue_id
LEFT JOIN acts ON acts.issue_id = i.issue_id
LEFT JOIN topgeo ON topgeo.issue_id = i.issue_id;

SELECT COUNT(*) issues, COUNT(evidence) with_evidence,
       SUM(IFF(data_confidence_band='HIGH',1,0)) high_conf,
       SUM(IFF(root_cause_type='LOT',1,0)) lot_issues
FROM INSIGHT_ISSUE;

-- -------------------------------------------------------------------------
-- INSIGHTS satellites
-- Source: platform/ddl/051_insights_satellites.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_INSIGHTS;

-- ---------------------------------------------------------------------------
-- INSIGHT_PERSONA_VIEW — exactly 5 rows per issue (Fig 6)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE INSIGHT_PERSONA_VIEW AS
WITH pdi AS (SELECT model, AVG(pdi_red_pct) v FROM SF_SOLUTIONS.CQC_ANALYTICS.V_METRIC_PDI GROUP BY 1),
rew AS (SELECT model, AVG(first_pass_yield_pct) fpy, SUM(total_rework_min) rwk FROM SF_SOLUTIONS.CQC_ANALYTICS.V_METRIC_REWORK GROUP BY 1),
dwn AS (SELECT model, avg_idle_pct FROM SF_SOLUTIONS.CQC_ANALYTICS.V_METRIC_DOWNTIME),
sqpi AS (SELECT AVG(sqpi_score) v FROM SF_SOLUTIONS.CQC_ANALYTICS.V_METRIC_SQPI)
SELECT i.issue_id, p.persona, p.view_level,
    p.diagnose_question,
    CASE p.persona
      WHEN 'DEALER' THEN 'PDI red-rate on ' || i.model || ' is ' || COALESCE(ROUND(pdi.v,1),0) || '%; prioritize pre-delivery checks on affected units.'
      WHEN 'PRODUCT' THEN 'MTBF ' || COALESCE(ROUND(i.mtbf,0),0) || ' hrs / MTTR ' || COALESCE(i.mttr,0) || ' hrs for ' || i.system_group || ' on ' || i.model || '.'
      WHEN 'MANUFACTURING' THEN 'First-pass yield ' || COALESCE(ROUND(rew.fpy,1),0) || '%; rework ' || COALESCE(ROUND(rew.rwk,0),0) || ' min tied to ' || i.system_group || '.'
      WHEN 'SUPPLY_CHAIN' THEN CASE WHEN i.root_cause_type='LOT' THEN 'Suspect supplier lot ' || i.lot_key || ' drives failures; contain + SCAR.' ELSE 'No supplier-lot concentration detected.' END
      ELSE 'Plan-for exposure $' || TRIM(TO_CHAR(ROUND(COALESCE(i.warranty_exposure_p90,0)),'999,999,999,990')) || '; downtime idle ' || COALESCE(ROUND(dwn.avg_idle_pct,1),0) || '% on ' || i.model || '.' END AS diagnose_answer_text,
    p.primary_metric_name,
    CASE p.persona WHEN 'DEALER' THEN COALESCE(ROUND(pdi.v,1),0) WHEN 'PRODUCT' THEN COALESCE(ROUND(i.mtbf,0),0)
      WHEN 'MANUFACTURING' THEN COALESCE(ROUND(rew.fpy,1),0) WHEN 'SUPPLY_CHAIN' THEN COALESCE(ROUND((SELECT v FROM sqpi),0),0)
      ELSE COALESCE(i.warranty_exposure_p90,0) END AS primary_metric_value,
    p.primary_metric_target,
    NULL AS primary_metric_delta,
    CASE p.persona
      WHEN 'DEALER' THEN 'Outreach + PDI on affected fleet'
      WHEN 'PRODUCT' THEN 'Reliability review; monitor MTBF trend'
      WHEN 'MANUFACTURING' THEN 'Line/station containment where lot-built'
      WHEN 'SUPPLY_CHAIN' THEN CASE WHEN i.root_cause_type='LOT' THEN 'Contain lot ' || i.lot_key || '; open/expedite SCAR' ELSE 'Monitor supplier PPM' END
      ELSE 'Assign owner; allocate containment resources' END AS action_summary
FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i
CROSS JOIN (
    SELECT 'DEALER' persona, 'customer' view_level, 'How many of my delivered units are affected and what should I inspect?' diagnose_question, 'PDI_RED_PCT' primary_metric_name, 3 primary_metric_target
    UNION ALL SELECT 'PRODUCT','product-line','Is this design/reliability, and is it getting worse?','MTBF_HOURS', 20000
    UNION ALL SELECT 'MANUFACTURING','production','Which line/shift/process built the affected units?','FIRST_PASS_YIELD_PCT', 98
    UNION ALL SELECT 'SUPPLY_CHAIN','component','Is this a systemic supplier/lot issue or isolated?','SQPI', 90
    UNION ALL SELECT 'EXECUTIVE','division','How big is the exposure and who owns the response?','PLAN_FOR_EXPOSURE_USD', 0
) p
LEFT JOIN pdi ON pdi.model=i.model
LEFT JOIN rew ON rew.model=i.model
LEFT JOIN dwn ON dwn.model=i.model;

-- ---------------------------------------------------------------------------
-- INSIGHT_RISK_ASSESSMENT (Fig 10)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE INSIGHT_RISK_ASSESSMENT AS
SELECT issue_id, CURRENT_TIMESTAMP() assessed_ts,
   CASE WHEN quality_dimension='SAFETY' THEN 'High Risk' WHEN pro_sif_risk>20 THEN 'Elevated' ELSE 'Low' END safety_rating,
   CASE WHEN vtc_usd>1e6 THEN 'High Risk' WHEN vtc_usd>250000 THEN 'Moderate' ELSE 'Low' END productivity_rating,
   CASE WHEN exposed_fleet_count>50 THEN 'Elevated' ELSE 'Contained' END downtime_rating,
   CASE WHEN warranty_exposure_p90>1e6 THEN 'High' WHEN warranty_exposure_p90>200000 THEN 'Moderate' ELSE 'Low' END warranty_exposure_rating,
   CASE WHEN impacted_customer_count>200 THEN 'Broad' WHEN impacted_customer_count>50 THEN 'Moderate' ELSE 'Narrow' END customer_impact_rating,
   CASE WHEN quality_dimension='SAFETY' THEN 'HIGH' WHEN priority_rank<=15 THEN 'ELEVATED' ELSE 'MODERATE' END overall_risk,
   title || ' — ' || quality_dimension || ' priority #' || priority_rank ||
     '; plan-for exposure $' || TRIM(TO_CHAR(ROUND(COALESCE(warranty_exposure_p90,0)),'999,999,999,990')) AS headline_text
FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE;

-- ---------------------------------------------------------------------------
-- INSIGHT_ACTION (Fig 10) — from Module 8 recommendations + TSB retrieval
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE INSIGHT_ACTION AS
SELECT
    a.issue_id || '-' || a.action_seq AS action_id, a.issue_id, a.owner_persona,
    REPLACE(a.time_window,'-','_') || IFF(a.time_window LIKE '%h','','') AS time_window,
    a.title AS action_text,
    'Root-cause=' || i.root_cause_type || '; dimension=' || i.quality_dimension ||
      '; priority #' || i.priority_rank AS action_rationale,
    a.risk_reduction_pct AS expected_risk_reduction,
    'RULE' AS source,
    (SELECT ARRAY_AGG(doc_id) FROM SF_SOLUTIONS.CQC_STAGING.STG_DOC_TECH d
      WHERE d.system_group_cd = i.system_group AND (d.model = i.model OR d.model='ALL')) AS tsb_refs,
    a.status
FROM SF_SOLUTIONS.CQC_ML.RECOMMENDED_ACTIONS a
JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON i.issue_id = a.issue_id;

-- ---------------------------------------------------------------------------
-- INSIGHT_IMPACTED_* (Fig 9 tiles) — reshaped from ANALYTICS rollups
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE INSIGHT_IMPACTED_CUSTOMERS AS
SELECT issue_id, customer_key entity_key, customer_name entity_name, units_impacted exposure_count,
       events impact_value, us_subregion geo, end_market_cd FROM SF_SOLUTIONS.CQC_ANALYTICS.IMPACTED_CUSTOMERS;
CREATE OR REPLACE TABLE INSIGHT_IMPACTED_DEALERS AS
SELECT issue_id, dealer_key entity_key, dealer_name entity_name, units_impacted exposure_count,
       events impact_value, us_subregion geo FROM SF_SOLUTIONS.CQC_ANALYTICS.IMPACTED_DEALERS;
CREATE OR REPLACE TABLE INSIGHT_IMPACTED_FACILITIES AS
SELECT issue_id, build_facility_key entity_key, facility_name entity_name, units_built exposure_count,
       units_built impact_value, NULL geo FROM SF_SOLUTIONS.CQC_ANALYTICS.IMPACTED_FACILITIES;
CREATE OR REPLACE TABLE INSIGHT_IMPACTED_AREAS AS
SELECT issue_id, area entity_key, area entity_name, units_impacted exposure_count,
       events impact_value, global_region geo FROM SF_SOLUTIONS.CQC_ANALYTICS.IMPACTED_AREAS;

-- ---------------------------------------------------------------------------
-- INSIGHT_ALERT (Fig 2/8) — push feed for high-priority / safety / lot issues
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE INSIGHT_ALERT AS
SELECT
    'ALRT-' || SUBSTR(issue_id,1,10) AS alert_id, issue_id,
    updated_ts AS alert_ts,
    CASE WHEN quality_dimension='SAFETY' THEN 'CRITICAL' WHEN priority_rank<=10 THEN 'HIGH' ELSE 'MEDIUM' END severity,
    quality_dimension || ' — ' || title AS headline,
    summary_text AS body,
    CASE WHEN root_cause_type='LOT' THEN ARRAY_CONSTRUCT('PLANT_QC','SUPPLY_CHAIN','EXEC')
         WHEN quality_dimension='SAFETY' THEN ARRAY_CONSTRUCT('EXEC','DEALER')
         ELSE ARRAY_CONSTRUCT('PRODUCT') END AS channel_targets,
    NULL AS forward_target,
    issue_id AS dedupe_key, 'NEW' AS state
FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE
WHERE quality_dimension='SAFETY' OR priority_rank <= 20 OR root_cause_type='LOT';

-- ---------------------------------------------------------------------------
-- INSIGHT_METRIC_TREND — pillar KPI time series (events by dimension x month)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE INSIGHT_METRIC_TREND AS
SELECT quality_dimension_cd AS metric_name, 'dimension' AS grain,
       event_month AS period, COUNT(*) AS value,
       NULL AS target, NULL AS baseline
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT
WHERE event_month >= '2022-01-01'
GROUP BY 1,3
UNION ALL
SELECT 'EVENTS_' || product_family, 'family', event_month, COUNT(*), NULL, NULL
FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT e
JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_MACHINE m USING (machine_key)
WHERE event_month >= '2022-01-01'
GROUP BY 2, product_family, event_month;

SELECT 'PERSONA_VIEW' t, COUNT(*) n, COUNT(DISTINCT issue_id) issues FROM INSIGHT_PERSONA_VIEW
UNION ALL SELECT 'RISK_ASSESSMENT', COUNT(*), COUNT(DISTINCT issue_id) FROM INSIGHT_RISK_ASSESSMENT
UNION ALL SELECT 'ACTION', COUNT(*), COUNT(DISTINCT issue_id) FROM INSIGHT_ACTION
UNION ALL SELECT 'ALERT', COUNT(*), COUNT(DISTINCT issue_id) FROM INSIGHT_ALERT;

-- -------------------------------------------------------------------------
-- INSIGHTS narratives (AI_COMPLETE)
-- Source: platform/ddl/052_insights_narrative.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_INSIGHTS;

CREATE OR REPLACE PROCEDURE SP_GENERATE_INSIGHT_NARRATIVE(P_ISSUE_ID STRING)
RETURNS STRING LANGUAGE SQL AS
$$
BEGIN
    UPDATE SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE
    SET rationale_text = SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
            'You are a customer-quality analyst for Acme Industrial. Using ONLY the figures in the JSON '
         || 'evidence below, write 2-3 sentences explaining why this issue matters and its root cause. '
         || 'Do NOT invent any numbers not present in the JSON. Refer to pro_sif_risk as "SIP risk" (Serious Injury Potential). '
            || 'Describe exposure.p50_usd as "likely exposure", exposure.p90_usd as "plan-for exposure" and '
            || 'exposure.cvar_usd as "bad-case exposure"; never write P50, P90, CVaR, percentile, median or '
            || 'the JSON key names. Be concise and executive-ready.\n\n'
         || 'Issue: ' || title || ' (' || quality_dimension || ').\nEvidence: ' || TO_JSON(evidence)),
        rationale_generated_ts = CURRENT_TIMESTAMP()
    WHERE (:P_ISSUE_ID IS NULL OR issue_id = :P_ISSUE_ID);
    RETURN 'narratives generated';
END;
$$;

-- generate grounded narratives for all insights
CALL SP_GENERATE_INSIGHT_NARRATIVE(NULL);

-- anchor narrative spot-check
SELECT title, data_confidence_band, rationale_text
FROM INSIGHT_ISSUE WHERE model='LX-950' AND system_group='ENGINE_FUEL' AND failure_mode='POWER_LOSS';

-- -------------------------------------------------------------------------
-- Issue archetype rollups
-- Source: platform/ddl/037_issue_archetype.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ANALYTICS;

-- ---------------------------------------------------------------------------
-- ISSUE_ARCHETYPE_MIX — one row per issue x archetype.
--   LOT issues  -> basis EXPOSED  (suspect-lot machines of the issue's model)
--   other issues-> basis IMPACTED (impacted-customers footprint)
-- relative_pain_per_unit = per_unit_$ / archetype equipment-revenue midpoint (intensity)
-- pain_share_pct         = archetype's share of the issue's total felt pain
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE CQC_ANALYTICS.ISSUE_ARCHETYPE_MIX AS
WITH lot_exposed AS (
    SELECT ii.issue_id, c.account_archetype AS archetype,
           COUNT(DISTINCT dm.machine_key) AS units, COUNT(DISTINCT dm.customer_acct) AS customers
    FROM CQC_INSIGHTS.INSIGHT_ISSUE ii
    JOIN CQC_ATOMIC.DIM_MACHINE dm ON dm.model = ii.model
    JOIN CQC_ATOMIC.BRIDGE_LOT_MACHINE b ON b.machine_key = dm.machine_key
    JOIN CQC_ATOMIC.DIM_LOT l ON l.lot_key = b.lot_key AND l.is_suspect = TRUE
    JOIN CQC_ATOMIC.DIM_CUSTOMER c ON c.customer_acct = dm.customer_acct
    WHERE ii.root_cause_type = 'LOT' GROUP BY 1,2
),
impacted AS (
    SELECT ic.issue_id, c.account_archetype AS archetype,
           SUM(ic.units_impacted) AS units, COUNT(DISTINCT ic.customer_key) AS customers
    FROM CQC_ANALYTICS.IMPACTED_CUSTOMERS ic
    JOIN CQC_ATOMIC.DIM_CUSTOMER c ON c.customer_key = ic.customer_key
    JOIN CQC_INSIGHTS.INSIGHT_ISSUE ii ON ii.issue_id = ic.issue_id AND ii.root_cause_type <> 'LOT'
    GROUP BY 1,2
),
combined AS (
    SELECT issue_id, archetype, units, customers, 'EXPOSED' AS basis FROM lot_exposed
    UNION ALL SELECT issue_id, archetype, units, customers, 'IMPACTED' AS basis FROM impacted
),
totals AS (SELECT issue_id, SUM(units) AS tot_units FROM combined GROUP BY 1),
peru AS (
    SELECT t.issue_id, t.tot_units,
           COALESCE(ii.warranty_exposure_p50, ii.vtc_usd, 0) / NULLIF(t.tot_units,0) AS per_unit_usd
    FROM totals t JOIN CQC_INSIGHTS.INSIGHT_ISSUE ii ON ii.issue_id = t.issue_id
)
SELECT cm.issue_id, cm.archetype, r.archetype_rank, cm.units, cm.customers, cm.basis,
       r.quality_definition, r.quality_definition_cd, r.pain_channel, r.pain_channel_cd,
       r.response_mode, r.equip_rev_midpoint,
       ROUND(pu.per_unit_usd) AS per_unit_usd,
       ROUND(pu.per_unit_usd / NULLIF(r.equip_rev_midpoint,0), 6) AS relative_pain_per_unit,
       ROUND(cm.units * pu.per_unit_usd / NULLIF(r.equip_rev_midpoint,0), 4) AS relative_pain,
       ROUND(100.0 * (cm.units * pu.per_unit_usd / NULLIF(r.equip_rev_midpoint,0))
             / NULLIF(SUM(cm.units * pu.per_unit_usd / NULLIF(r.equip_rev_midpoint,0)) OVER (PARTITION BY cm.issue_id),0), 1) AS pain_share_pct
FROM combined cm
JOIN CQC_ATOMIC.REF_ACCOUNT_ARCHETYPE r ON r.archetype = cm.archetype
JOIN peru pu ON pu.issue_id = cm.issue_id
WHERE cm.archetype IS NOT NULL;

-- ---------------------------------------------------------------------------
-- CUSTOMER_BACK_PRIORITY — re-rank by pain intensity; SAFETY stays absolute.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE CQC_ANALYTICS.CUSTOMER_BACK_PRIORITY AS
WITH intensity AS (
    SELECT issue_id, SUM(relative_pain) AS total_pain, SUM(units) AS mix_units,
           SUM(relative_pain)/NULLIF(SUM(units),0) AS pain_intensity
    FROM CQC_ANALYTICS.ISSUE_ARCHETYPE_MIX GROUP BY 1
),
base AS (
    SELECT ii.issue_id, ii.quality_dimension, ii.priority_rank AS orig_priority_rank, ii.pro_sif_risk,
           CASE ii.quality_dimension WHEN 'SAFETY' THEN 1 WHEN 'PRODUCTIVITY' THEN 2 ELSE 3 END AS priority_tier,
           COALESCE(i.pain_intensity,0) AS pain_intensity, COALESCE(i.total_pain,0) AS total_pain
    FROM CQC_INSIGHTS.INSIGHT_ISSUE ii
    LEFT JOIN intensity i ON i.issue_id = ii.issue_id
)
SELECT issue_id, quality_dimension, priority_tier, orig_priority_rank,
       ROUND(pain_intensity,6) AS pain_intensity, ROUND(total_pain,4) AS total_pain,
       ROW_NUMBER() OVER (ORDER BY priority_tier,
           CASE WHEN quality_dimension='SAFETY' THEN pro_sif_risk ELSE pain_intensity END DESC) AS customer_back_rank,
       ROW_NUMBER() OVER (PARTITION BY priority_tier ORDER BY
           CASE WHEN quality_dimension='SAFETY' THEN pro_sif_risk ELSE pain_intensity END DESC) AS rank_in_tier
FROM base;

-- ---------------------------------------------------------------------------
-- INSIGHTS consumption objects (agent + UI + semantic model).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE CQC_INSIGHTS.INSIGHT_ISSUE_ARCHETYPE AS
SELECT m.*, (m.pain_share_pct = MAX(m.pain_share_pct) OVER (PARTITION BY m.issue_id)) AS is_dominant_pain
FROM CQC_ANALYTICS.ISSUE_ARCHETYPE_MIX m;

CREATE OR REPLACE TABLE CQC_INSIGHTS.INSIGHT_ISSUE_CUSTOMER_BACK AS
WITH dom AS (
    SELECT issue_id, archetype AS dominant_archetype, pain_channel AS dominant_channel,
           pain_share_pct AS dominant_pain_share_pct, units AS dominant_units
    FROM CQC_INSIGHTS.INSIGHT_ISSUE_ARCHETYPE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY issue_id ORDER BY pain_share_pct DESC) = 1
)
SELECT cb.issue_id, cb.quality_dimension, cb.priority_tier,
       cb.orig_priority_rank, cb.customer_back_rank, cb.rank_in_tier,
       cb.orig_priority_rank - cb.customer_back_rank AS rank_delta,
       cb.pain_intensity, cb.total_pain,
       d.dominant_archetype, d.dominant_channel, d.dominant_pain_share_pct, d.dominant_units
FROM CQC_ANALYTICS.CUSTOMER_BACK_PRIORITY cb
LEFT JOIN dom d ON d.issue_id = cb.issue_id;

-- validation
SELECT archetype, units, pain_share_pct FROM CQC_INSIGHTS.INSIGHT_ISSUE_ARCHETYPE
WHERE issue_id = '28981e2d09f89322a87dba34c2947cb7' ORDER BY archetype_rank;

-- -------------------------------------------------------------------------
-- ACTION workflow tables
-- Source: platform/ddl/080_action.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ACTION;

-- ---------------------------------------------------------------------
-- Registries
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CQC_ACTION.OWNER (
    owner_id       STRING PRIMARY KEY,
    owner_name     STRING,
    persona_scope  STRING,          -- dealer/product/manufacturing/supply_chain/executive
    org_unit       STRING,
    email          STRING
);

INSERT INTO CQC_ACTION.OWNER (owner_id, owner_name, persona_scope, org_unit, email)
SELECT 'OWN-DEALER',   'Regional Service Manager', 'dealer',        'Dealer Network — North America', 'dealer.ops@acme.example'   UNION ALL
SELECT 'OWN-PRODUCT',  'Reliability Engineering Lead', 'product',   'Product Design & Engineering',   'product.eng@acme.example'  UNION ALL
SELECT 'OWN-MFG',      'Plant Quality Manager', 'manufacturing',    'Assembly — South Plant, GA',        'plant.qc@acme.example'     UNION ALL
SELECT 'OWN-SC',       'Supplier Quality Lead', 'supply_chain',     'Supplier Quality & SCAR',        'supplier.quality@acme.example' UNION ALL
SELECT 'OWN-EXEC',     'Division Quality Sponsor', 'executive',     'CED Division Leadership',         'exec.sponsor@acme.example';

CREATE OR REPLACE TABLE CQC_ACTION.SLA_POLICY (
    pillar         STRING,
    severity       STRING,
    ack_hours      NUMBER,
    resolve_hours  NUMBER
);

INSERT INTO CQC_ACTION.SLA_POLICY (pillar, severity, ack_hours, resolve_hours)
SELECT 'SAFETY','CRITICAL',1,24        UNION ALL
SELECT 'SAFETY','HIGH',4,48            UNION ALL
SELECT 'SAFETY','MED',8,72             UNION ALL
SELECT 'PRODUCTIVITY','CRITICAL',4,48  UNION ALL
SELECT 'PRODUCTIVITY','HIGH',8,72      UNION ALL
SELECT 'PRODUCTIVITY','MED',24,120     UNION ALL
SELECT 'EXPERIENCE','HIGH',24,168      UNION ALL
SELECT 'EXPERIENCE','MED',48,240       UNION ALL
SELECT 'EXPERIENCE','LOW',48,240;

-- ---------------------------------------------------------------------
-- Hero + audit + notifications
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CQC_ACTION.WORKFLOW_ITEM (
    workflow_item_id  STRING PRIMARY KEY,
    source_type       STRING,        -- ALERT / ACTION
    insight_issue_id  STRING,
    insight_alert_id  STRING,
    insight_action_id STRING,
    title             STRING,
    pillar            STRING,
    severity          STRING,
    state             STRING,        -- NEW/ACKNOWLEDGED/ASSIGNED/IN_PROGRESS/FORWARDED/RESOLVED/VERIFIED/DISMISSED
    owner_id          STRING,
    persona_scope     STRING,
    time_window       STRING,
    sla_due_ts        TIMESTAMP_NTZ,
    sla_breached      BOOLEAN DEFAULT FALSE,
    created_ts        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    updated_ts        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    resolution_note   STRING,
    evidence          VARIANT
);

CREATE OR REPLACE TABLE CQC_ACTION.WORKFLOW_EVENT (
    event_id          STRING DEFAULT UUID_STRING(),
    workflow_item_id  STRING,
    event_type        STRING,        -- STATE_CHANGE/ASSIGN/FORWARD/COMMENT/AUTO_REOPEN/SLA_ESCALATION
    actor             STRING,
    from_state        STRING,
    to_state          STRING,
    note              STRING,
    event_ts          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE CQC_ACTION.NOTIFICATION (
    notification_id   STRING DEFAULT UUID_STRING(),
    workflow_item_id  STRING,
    owner_id          STRING,
    channel           STRING,        -- IN_APP/EMAIL/TEAMS
    payload           STRING,
    sent_ts           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
);

-- -------------------------------------------------------------------------
-- ACTION procedures
-- Source: platform/ddl/081_action_procs.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ACTION;

-- ---------------------------------------------------------------------
-- Promote an INSIGHT_ALERT into a tracked WORKFLOW_ITEM (idempotent by alert).
-- Snapshots evidence, computes SLA from pillar+severity. Returns workflow_item_id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE CQC_ACTION.SP_PROMOTE_TO_WORKFLOW(P_ALERT_ID STRING, P_ACTOR STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_id STRING;
    v_existing STRING;
BEGIN
    SELECT MAX(workflow_item_id) INTO :v_existing
      FROM CQC_ACTION.WORKFLOW_ITEM WHERE insight_alert_id = :P_ALERT_ID;
    IF (v_existing IS NOT NULL) THEN
        RETURN v_existing;
    END IF;

    v_id := 'WF-' || SUBSTR(REPLACE(UUID_STRING(),'-',''), 1, 12);

    INSERT INTO CQC_ACTION.WORKFLOW_ITEM
        (workflow_item_id, source_type, insight_issue_id, insight_alert_id, insight_action_id,
         title, pillar, severity, state, owner_id, persona_scope, time_window,
         sla_due_ts, sla_breached, resolution_note, evidence)
    SELECT
        :v_id, 'ALERT', a.issue_id, a.alert_id, NULL,
        a.headline, i.quality_dimension, a.severity, 'NEW', NULL, NULL,
        i.next_action_window,
        DATEADD('hour', COALESCE(p.ack_hours, 24), CURRENT_TIMESTAMP())::TIMESTAMP_NTZ,
        FALSE, NULL, i.evidence
    FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ALERT a
    JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON a.issue_id = i.issue_id
    LEFT JOIN CQC_ACTION.SLA_POLICY p
           ON p.pillar = i.quality_dimension AND p.severity = a.severity
    WHERE a.alert_id = :P_ALERT_ID;

    INSERT INTO CQC_ACTION.WORKFLOW_EVENT (workflow_item_id, event_type, actor, from_state, to_state, note)
    VALUES (:v_id, 'STATE_CHANGE', :P_ACTOR, NULL, 'NEW', 'Promoted from alert ' || :P_ALERT_ID);

    RETURN :v_id;
END;
$$;

-- ---------------------------------------------------------------------
-- Validated state transition with safety-gate enforcement + audit event.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE CQC_ACTION.SP_TRANSITION_WORKFLOW(
    P_ITEM_ID STRING, P_TO_STATE STRING, P_ACTOR STRING, P_NOTE STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_from STRING;
    v_pillar STRING;
    v_owner STRING;
    v_sev STRING;
    v_ack NUMBER;
    v_res NUMBER;
    v_ok BOOLEAN;
BEGIN
    SELECT state, pillar, owner_id, severity
      INTO :v_from, :v_pillar, :v_owner, :v_sev
      FROM CQC_ACTION.WORKFLOW_ITEM WHERE workflow_item_id = :P_ITEM_ID;

    IF (v_from IS NULL) THEN
        RETURN 'ERROR: unknown workflow_item_id';
    END IF;

    -- allowed transitions
    v_ok := (
        (v_from = 'NEW'          AND P_TO_STATE IN ('ACKNOWLEDGED','DISMISSED')) OR
        (v_from = 'ACKNOWLEDGED' AND P_TO_STATE IN ('ASSIGNED','FORWARDED','DISMISSED')) OR
        (v_from = 'FORWARDED'    AND P_TO_STATE IN ('ASSIGNED')) OR
        (v_from = 'ASSIGNED'     AND P_TO_STATE IN ('IN_PROGRESS','FORWARDED')) OR
        (v_from = 'IN_PROGRESS'  AND P_TO_STATE IN ('RESOLVED')) OR
        (v_from = 'RESOLVED'     AND P_TO_STATE IN ('VERIFIED','IN_PROGRESS')) OR
        (v_from = 'VERIFIED'     AND P_TO_STATE IN ('IN_PROGRESS'))
    );
    IF (NOT v_ok) THEN
        RETURN 'ERROR: illegal transition ' || v_from || ' -> ' || P_TO_STATE;
    END IF;

    -- safety-gate: cannot DISMISS a SAFETY item without owner + note
    IF (P_TO_STATE = 'DISMISSED' AND v_pillar = 'SAFETY'
        AND (v_owner IS NULL OR P_NOTE IS NULL OR LENGTH(TRIM(P_NOTE)) = 0)) THEN
        RETURN 'ERROR: SAFETY item requires owner + reason to dismiss';
    END IF;

    -- recompute SLA on state entry
    SELECT ack_hours, resolve_hours INTO :v_ack, :v_res
      FROM CQC_ACTION.SLA_POLICY WHERE pillar = :v_pillar AND severity = :v_sev;

    UPDATE CQC_ACTION.WORKFLOW_ITEM
       SET state = :P_TO_STATE,
           updated_ts = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
           resolution_note = CASE WHEN :P_TO_STATE = 'RESOLVED' THEN :P_NOTE ELSE resolution_note END,
           sla_due_ts = CASE
               WHEN :P_TO_STATE IN ('ASSIGNED','IN_PROGRESS')
                    THEN DATEADD('hour', COALESCE(:v_res, 72), CURRENT_TIMESTAMP())::TIMESTAMP_NTZ
               WHEN :P_TO_STATE IN ('RESOLVED','VERIFIED','DISMISSED') THEN NULL
               ELSE sla_due_ts END,
           sla_breached = CASE WHEN :P_TO_STATE IN ('RESOLVED','VERIFIED','DISMISSED') THEN FALSE ELSE sla_breached END
     WHERE workflow_item_id = :P_ITEM_ID;

    INSERT INTO CQC_ACTION.WORKFLOW_EVENT (workflow_item_id, event_type, actor, from_state, to_state, note)
    VALUES (:P_ITEM_ID,
            IFF(:P_TO_STATE = 'DISMISSED','STATE_CHANGE','STATE_CHANGE'),
            :P_ACTOR, :v_from, :P_TO_STATE, :P_NOTE);

    RETURN 'OK: ' || v_from || ' -> ' || P_TO_STATE;
END;
$$;

-- ---------------------------------------------------------------------
-- Assign owner -> ASSIGNED.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE CQC_ACTION.SP_ASSIGN_WORKFLOW(P_ITEM_ID STRING, P_OWNER_ID STRING, P_ACTOR STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_from STRING;
    v_scope STRING;
    v_res NUMBER;
    v_pillar STRING;
    v_sev STRING;
BEGIN
    SELECT w.state, w.pillar, w.severity, o.persona_scope
      INTO :v_from, :v_pillar, :v_sev, :v_scope
      FROM CQC_ACTION.WORKFLOW_ITEM w
      LEFT JOIN CQC_ACTION.OWNER o ON o.owner_id = :P_OWNER_ID
     WHERE w.workflow_item_id = :P_ITEM_ID;

    IF (v_from IS NULL) THEN RETURN 'ERROR: unknown workflow_item_id'; END IF;

    SELECT resolve_hours INTO :v_res
      FROM CQC_ACTION.SLA_POLICY WHERE pillar = :v_pillar AND severity = :v_sev;

    UPDATE CQC_ACTION.WORKFLOW_ITEM
       SET owner_id = :P_OWNER_ID,
           persona_scope = :v_scope,
           state = 'ASSIGNED',
           sla_due_ts = DATEADD('hour', COALESCE(:v_res, 72), CURRENT_TIMESTAMP())::TIMESTAMP_NTZ,
           updated_ts = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
     WHERE workflow_item_id = :P_ITEM_ID;

    INSERT INTO CQC_ACTION.WORKFLOW_EVENT (workflow_item_id, event_type, actor, from_state, to_state, note)
    VALUES (:P_ITEM_ID, 'ASSIGN', :P_ACTOR, :v_from, 'ASSIGNED', 'Assigned to ' || :P_OWNER_ID);

    RETURN 'OK: assigned ' || :P_OWNER_ID;
END;
$$;

-- ---------------------------------------------------------------------
-- Forward an alert: promote (if needed) + FORWARDED + notification.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE CQC_ACTION.SP_FORWARD_ALERT(
    P_ALERT_ID STRING, P_OWNER_ID STRING, P_ACTOR STRING, P_CHANNEL STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_id STRING;
    v_from STRING;
    v_scope STRING;
BEGIN
    v_id := (CALL CQC_ACTION.SP_PROMOTE_TO_WORKFLOW(:P_ALERT_ID, :P_ACTOR));

    SELECT state INTO :v_from FROM CQC_ACTION.WORKFLOW_ITEM WHERE workflow_item_id = :v_id;
    SELECT persona_scope INTO :v_scope FROM CQC_ACTION.OWNER WHERE owner_id = :P_OWNER_ID;

    UPDATE CQC_ACTION.WORKFLOW_ITEM
       SET state = 'FORWARDED', owner_id = :P_OWNER_ID, persona_scope = :v_scope,
           updated_ts = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
     WHERE workflow_item_id = :v_id;

    INSERT INTO CQC_ACTION.WORKFLOW_EVENT (workflow_item_id, event_type, actor, from_state, to_state, note)
    VALUES (:v_id, 'FORWARD', :P_ACTOR, :v_from, 'FORWARDED', 'Forwarded to ' || :P_OWNER_ID || ' via ' || :P_CHANNEL);

    INSERT INTO CQC_ACTION.NOTIFICATION (workflow_item_id, owner_id, channel, payload)
    SELECT :v_id, :P_OWNER_ID, :P_CHANNEL,
           'Alert forwarded: ' || w.title || ' [' || w.pillar || '/' || w.severity || ']'
      FROM CQC_ACTION.WORKFLOW_ITEM w WHERE w.workflow_item_id = :v_id;

    RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------
-- SLA breach sweep (schedulable). Flips sla_breached + escalation events.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE CQC_ACTION.SP_CHECK_SLA_BREACHES()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_n NUMBER;
BEGIN
    INSERT INTO CQC_ACTION.WORKFLOW_EVENT (workflow_item_id, event_type, actor, from_state, to_state, note)
    SELECT workflow_item_id, 'SLA_ESCALATION', 'system', state, state,
           'SLA breached (due ' || TO_VARCHAR(sla_due_ts) || ')'
      FROM CQC_ACTION.WORKFLOW_ITEM
     WHERE state NOT IN ('RESOLVED','VERIFIED','DISMISSED')
       AND sla_due_ts IS NOT NULL AND sla_due_ts < CURRENT_TIMESTAMP()
       AND sla_breached = FALSE;

    UPDATE CQC_ACTION.WORKFLOW_ITEM
       SET sla_breached = TRUE, updated_ts = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
     WHERE state NOT IN ('RESOLVED','VERIFIED','DISMISSED')
       AND sla_due_ts IS NOT NULL AND sla_due_ts < CURRENT_TIMESTAMP()
       AND sla_breached = FALSE;

    v_n := SQLROWCOUNT;
    RETURN 'breached=' || v_n;
END;
$$;

-- -------------------------------------------------------------------------
-- ACTION views
-- Source: platform/ddl/082_action_views.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ACTION;

-- Open work items with issue context, owner, SLA countdown (Resolution Tracker).
CREATE OR REPLACE VIEW CQC_ACTION.V_WORKFLOW_OPEN AS
SELECT
    w.workflow_item_id,
    w.title,
    w.pillar,
    w.severity,
    w.state,
    w.insight_issue_id,
    w.insight_alert_id,
    w.time_window,
    w.owner_id,
    o.owner_name,
    o.persona_scope,
    w.sla_due_ts,
    w.sla_breached,
    DATEDIFF('hour', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, w.sla_due_ts) AS sla_hours_remaining,
    w.created_ts,
    w.updated_ts,
    i.priority_rank,
    i.model,
    i.system_group,
    i.failure_mode,
    i.vtc_usd,
    i.pro_sif_risk
FROM CQC_ACTION.WORKFLOW_ITEM w
LEFT JOIN CQC_ACTION.OWNER o ON o.owner_id = w.owner_id
LEFT JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON i.issue_id = w.insight_issue_id
WHERE w.state NOT IN ('VERIFIED','DISMISSED');

-- Per-item ordered audit history (item drill / audit).
CREATE OR REPLACE VIEW CQC_ACTION.V_WORKFLOW_TIMELINE AS
SELECT
    e.workflow_item_id,
    e.event_ts,
    e.event_type,
    e.actor,
    e.from_state,
    e.to_state,
    e.note
FROM CQC_ACTION.WORKFLOW_EVENT e
ORDER BY e.event_ts;

-- Alert inbox: every alert LEFT JOIN its workflow state (Quality Alerts feed).
CREATE OR REPLACE VIEW CQC_ACTION.V_ALERT_INBOX AS
SELECT
    a.alert_id,
    a.issue_id,
    a.alert_ts,
    a.severity,
    a.headline,
    a.body,
    i.quality_dimension AS pillar,
    i.priority_rank,
    w.workflow_item_id,
    COALESCE(w.state, 'NEW') AS workflow_state,
    w.owner_id,
    o.owner_name,
    w.sla_due_ts,
    w.sla_breached
FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ALERT a
JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON i.issue_id = a.issue_id
LEFT JOIN CQC_ACTION.WORKFLOW_ITEM w ON w.insight_alert_id = a.alert_id
LEFT JOIN CQC_ACTION.OWNER o ON o.owner_id = w.owner_id;

-- Per-owner backlog + SLA posture (persona "my queue").
CREATE OR REPLACE VIEW CQC_ACTION.V_OWNER_QUEUE AS
SELECT
    o.owner_id,
    o.owner_name,
    o.persona_scope,
    COUNT(w.workflow_item_id) AS open_items,
    COUNT_IF(w.sla_breached) AS breached_items,
    COUNT_IF(w.pillar = 'SAFETY') AS safety_items
FROM CQC_ACTION.OWNER o
LEFT JOIN CQC_ACTION.WORKFLOW_ITEM w
       ON w.owner_id = o.owner_id AND w.state NOT IN ('VERIFIED','DISMISSED')
GROUP BY o.owner_id, o.owner_name, o.persona_scope;

-- Overdue items for exec escalation.
CREATE OR REPLACE VIEW CQC_ACTION.V_SLA_BREACHES AS
SELECT * FROM CQC_ACTION.V_WORKFLOW_OPEN
WHERE sla_breached = TRUE
ORDER BY CASE pillar WHEN 'SAFETY' THEN 1 WHEN 'PRODUCTIVITY' THEN 2 ELSE 3 END, sla_due_ts;

-- -------------------------------------------------------------------------
-- ACTION archetype routing
-- Source: platform/ddl/083_action_archetype_routing.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ACTION;

-- Archetype-channel owners (idempotent). OWN-DEALER (Local) already exists.
INSERT INTO CQC_ACTION.OWNER (owner_id, owner_name, persona_scope, org_unit, email)
SELECT 'OWN-ACCT-TEAM','Strategic Account Team','enterprise','Account & Executive Engagement','account.team@acme.example'
WHERE NOT EXISTS (SELECT 1 FROM CQC_ACTION.OWNER WHERE owner_id='OWN-ACCT-TEAM')
UNION ALL
SELECT 'OWN-ACCT-MGR','Account Manager','national','Corporate Accounts + Dealer Coordination','account.manager@acme.example'
WHERE NOT EXISTS (SELECT 1 FROM CQC_ACTION.OWNER WHERE owner_id='OWN-ACCT-MGR')
UNION ALL
SELECT 'OWN-SVC-COUNTER','Dealer Service Counter','independent','Dealer Service Network','service.counter@acme.example'
WHERE NOT EXISTS (SELECT 1 FROM CQC_ACTION.OWNER WHERE owner_id='OWN-SVC-COUNTER');

-- Pain-channel -> owner / response-mode / play mapping.
CREATE OR REPLACE TABLE CQC_ACTION.MAP_PAIN_CHANNEL (
    pain_channel_cd STRING, archetype STRING, owner_id STRING, response_mode STRING, response_play STRING
);
INSERT INTO CQC_ACTION.MAP_PAIN_CHANNEL
SELECT 'ACCOUNT_TEAM_EXEC','ENTERPRISE','OWN-ACCT-TEAM','PROACTIVE','Account team briefs the customer; executive touchpoint on portfolio TCO impact.'
UNION ALL SELECT 'ACCOUNT_MGR_DEALER','NATIONAL','OWN-ACCT-MGR','PROACTIVE','Account manager coordinates dealer to protect fleet-wide uptime and site consistency.'
UNION ALL SELECT 'DEALER_RELATIONSHIP','LOCAL','OWN-DEALER','MANAGED_REACTIVE','Dealer proactively schedules service to hold cost-per-hour reliability.'
UNION ALL SELECT 'SERVICE_COUNTER','INDEPENDENT','OWN-SVC-COUNTER','REACTIVE','Flag units at the service counter, machine-by-machine, so it is fixed when it arrives.';

-- Per-issue routing view: archetype mix joined to owner + response mode.
CREATE OR REPLACE VIEW CQC_ACTION.V_ARCHETYPE_ROUTING AS
SELECT a.issue_id, a.archetype, a.archetype_rank, a.units, a.pain_share_pct,
       a.pain_channel, a.pain_channel_cd, a.quality_definition,
       m.owner_id, o.owner_name, o.org_unit, m.response_mode, m.response_play,
       a.is_dominant_pain
FROM CQC_INSIGHTS.INSIGHT_ISSUE_ARCHETYPE a
JOIN CQC_ACTION.MAP_PAIN_CHANNEL m ON m.pain_channel_cd = a.pain_channel_cd
JOIN CQC_ACTION.OWNER o ON o.owner_id = m.owner_id;

-- validation
SELECT archetype, units, pain_share_pct, owner_name, response_mode
FROM CQC_ACTION.V_ARCHETYPE_ROUTING
WHERE issue_id = '28981e2d09f89322a87dba34c2947cb7' ORDER BY archetype_rank;

-- -------------------------------------------------------------------------
-- ACTION demo workflow history
-- Source: platform/ddl/084_action_demo_seed.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ACTION;

EXECUTE IMMEDIATE $$
DECLARE
    n NUMBER;
    a_anchor STRING; a_top STRING; a_r7 STRING; a_r8 STRING; a_r11 STRING;
    wf STRING;
    r STRING;
BEGIN
    SELECT COUNT(*) INTO :n FROM CQC_ACTION.WORKFLOW_ITEM;
    IF (n > 0) THEN
        RETURN 'skipped: workflow items already present';
    END IF;

    -- resolve alert ids by issue identity (model | system group | failure mode)
    SELECT MAX(IFF(i.model = 'LX-950' AND i.system_group = 'ENGINE_FUEL' AND i.failure_mode = 'SUDDEN_SHUTDOWN', a.alert_id, NULL)),
           MAX(IFF(i.model = 'EX-220' AND i.system_group = 'ENGINE_FUEL' AND i.failure_mode = 'SUDDEN_SHUTDOWN', a.alert_id, NULL)),
           MAX(IFF(i.model = 'EX-260' AND i.system_group = 'ENGINE_FUEL' AND i.failure_mode = 'SUDDEN_SHUTDOWN', a.alert_id, NULL)),
           MAX(IFF(i.model = 'MG-14'  AND i.system_group = 'ENGINE_FUEL' AND i.failure_mode = 'SUDDEN_SHUTDOWN', a.alert_id, NULL)),
           MAX(IFF(i.model = 'EX-260' AND i.system_group = 'STRUCTURES'  AND i.failure_mode = 'CRACK_FRACTURE',  a.alert_id, NULL))
      INTO :a_anchor, :a_top, :a_r7, :a_r8, :a_r11
      FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ALERT a
      JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON i.issue_id = a.issue_id;

    -- 1. anchor safety item: forwarded -> assigned -> in progress -> resolved (Story Mode close)
    IF (a_anchor IS NOT NULL) THEN
        wf := (CALL CQC_ACTION.SP_FORWARD_ALERT(:a_anchor, 'OWN-SC', 'demo_seed', 'IN_APP'));
        r  := (CALL CQC_ACTION.SP_ASSIGN_WORKFLOW(:wf, 'OWN-SC', 'demo_seed'));
        r  := (CALL CQC_ACTION.SP_TRANSITION_WORKFLOW(:wf, 'IN_PROGRESS', 'demo_seed', 'Containment on suspect injector lots; supplier SCAR opened.'));
        r  := (CALL CQC_ACTION.SP_TRANSITION_WORKFLOW(:wf, 'RESOLVED', 'demo_seed', 'Suspect lots quarantined; field service campaign covers exposed serials.'));
    END IF;

    -- 2. top-ranked safety item: acknowledged -> assigned -> in progress
    IF (a_top IS NOT NULL) THEN
        wf := (CALL CQC_ACTION.SP_PROMOTE_TO_WORKFLOW(:a_top, 'demo_seed'));
        r  := (CALL CQC_ACTION.SP_TRANSITION_WORKFLOW(:wf, 'ACKNOWLEDGED', 'demo_seed', NULL));
        r  := (CALL CQC_ACTION.SP_TRANSITION_WORKFLOW(:wf, 'ASSIGNED', 'demo_seed', NULL));
        r  := (CALL CQC_ACTION.SP_TRANSITION_WORKFLOW(:wf, 'IN_PROGRESS', 'demo_seed', 'Root-cause review underway.'));
    END IF;

    -- 3-5. forwarded to persona owners, awaiting assignment
    IF (a_r8 IS NOT NULL)  THEN wf := (CALL CQC_ACTION.SP_FORWARD_ALERT(:a_r8,  'OWN-PRODUCT', 'demo_seed', 'IN_APP')); END IF;
    IF (a_r7 IS NOT NULL)  THEN wf := (CALL CQC_ACTION.SP_FORWARD_ALERT(:a_r7,  'OWN-DEALER',  'demo_seed', 'IN_APP')); END IF;
    IF (a_r11 IS NOT NULL) THEN wf := (CALL CQC_ACTION.SP_FORWARD_ALERT(:a_r11, 'OWN-MFG',     'demo_seed', 'IN_APP')); END IF;

    SELECT COUNT(*) INTO :n FROM CQC_ACTION.WORKFLOW_ITEM;
    RETURN 'seeded workflow items: ' || n;
END;
$$;

-- -------------------------------------------------------------------------
-- Semantic view for Cortex Analyst
-- Source: platform/semantic_model/customer_quality_model.yaml
-- -------------------------------------------------------------------------

DROP SEMANTIC VIEW IF EXISTS SF_SOLUTIONS.CQC_ML.CUSTOMER_QUALITY_MODEL;
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('SF_SOLUTIONS.CQC_ML', $$
name: customer_quality_model
description: >
  CQC — Acme Industrial Construction Equipment Division customer-quality semantic model.
  Conversational access to governable quality ISSUES and their business impact,
  root cause, exposure, persona metrics, recommended actions, impacted fleet, and
  alerts. Primary grain is the ISSUE (from CQC_INSIGHTS.INSIGHT_ISSUE); thin drill to
  machine and quality-event detail. Safety > Productivity > Experience hierarchy.

tables:
  # ------------------------------------------------------------------ hero
  - name: insight_issue
    description: One row per governable quality issue (the unit personas act on).
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_ISSUE}
    primary_key: {columns: [ISSUE_ID]}
    dimensions:
      - {name: issue_id, expr: ISSUE_ID, data_type: TEXT, description: Unique issue id}
      - {name: title, expr: TITLE, data_type: TEXT, description: Human-readable issue title}
      - {name: summary_text, expr: SUMMARY_TEXT, data_type: TEXT, description: AI brief of the issue}
      - {name: quality_dimension, expr: QUALITY_DIMENSION, data_type: TEXT, description: "S/P/E pillar: SAFETY, PRODUCTIVITY, or EXPERIENCE", synonyms: [pillar, dimension, category]}
      - {name: status, expr: STATUS, data_type: TEXT, description: Workflow status, synonyms: [state]}
      - {name: lifecycle_stage, expr: LIFECYCLE_STAGE, data_type: TEXT, description: EMERGING / CONFIRMED / CONTAINED / RESOLVED}
      - {name: product_family, expr: PRODUCT_FAMILY, data_type: TEXT, description: CED product family, synonyms: [family, product line]}
      - {name: model, expr: MODEL, data_type: TEXT, description: Machine model e.g. LX-950, synonyms: [machine model]}
      - {name: system_group, expr: SYSTEM_GROUP, data_type: TEXT, description: Machine system e.g. ENGINE_FUEL, synonyms: [system, subsystem]}
      - {name: failure_mode, expr: FAILURE_MODE, data_type: TEXT, description: Canonical failure mode}
      - {name: root_cause_type, expr: ROOT_CAUSE_TYPE, data_type: TEXT, description: "LOT / DESIGN / ISOLATED / PLANT / SUPPLIER", synonyms: [root cause]}
      - {name: root_cause_summary, expr: ROOT_CAUSE_SUMMARY, data_type: TEXT, description: Plain-language root cause statement}
      - {name: lot_key, expr: LOT_KEY, data_type: TEXT, description: Suspect supplier lot number, synonyms: [lot, supplier lot]}
      - {name: geography_top, expr: GEOGRAPHY_TOP, data_type: TEXT, description: Most-impacted US subregion, synonyms: [region, area]}
      - {name: data_confidence_band, expr: DATA_CONFIDENCE_BAND, data_type: TEXT, description: HIGH / MED / LOW data readiness}
      - {name: rationale_text, expr: RATIONALE_TEXT, data_type: TEXT, description: Grounded explanation of why this issue matters}
    time_dimensions:
      - {name: first_detected, expr: FIRST_DETECTED_TS, data_type: DATE, description: When the issue was first detected}
    facts:
      - {name: priority_rank, expr: PRIORITY_RANK, data_type: NUMBER, description: Safety-gated lexicographic priority (1 = highest)}
      - {name: priority_score, expr: PRIORITY_SCORE, data_type: FLOAT, description: Composite priority magnitude}
      - {name: exposed_fleet_count, expr: EXPOSED_FLEET_COUNT, data_type: NUMBER, description: Machines exposed to this issue, synonyms: [exposed units, affected machines]}
      - {name: impacted_customer_count, expr: IMPACTED_CUSTOMER_COUNT, data_type: NUMBER, description: Distinct impacted customers}
      - {name: impacted_dealer_count, expr: IMPACTED_DEALER_COUNT, data_type: NUMBER, description: Distinct impacted dealers}
      - {name: impacted_facility_count, expr: IMPACTED_FACILITY_COUNT, data_type: NUMBER, description: Build facilities involved}
      - {name: pro_sif_risk, expr: PRO_SIF_RISK, data_type: NUMBER, description: Serious Injury Potential (SIP) risk score (safety), synonyms: [SIP, SIP risk, serious injury potential, safety risk]}
      - {name: vtc_usd, expr: VTC_USD, data_type: FLOAT, description: Value-to-cost productivity impact in USD}
      - {name: vtc_p90, expr: VTC_P90, data_type: FLOAT, description: VTC P90}
      - {name: cei_score, expr: CEI_SCORE, data_type: FLOAT, description: Customer experience index impact}
      - {name: nps_delta, expr: NPS_DELTA, data_type: NUMBER, description: NPS delta vs fleet}
      - {name: warranty_exposure_p50, expr: WARRANTY_EXPOSURE_P50, data_type: FLOAT, description: Likely warranty exposure USD (central estimate; Monte-Carlo median), synonyms: [likely exposure, likely cost, typical exposure, expected exposure]}
      - {name: warranty_exposure_p90, expr: WARRANTY_EXPOSURE_P90, data_type: FLOAT, description: Plan-for warranty exposure USD (the figure to budget; 9-in-10 chance it is not exceeded), synonyms: [exposure, plan-for exposure, plan for, budget exposure, cost to plan for]}
      - {name: warranty_exposure_cvar, expr: WARRANTY_EXPOSURE_CVAR, data_type: FLOAT, description: Bad-case warranty exposure USD (average of the worst 1-in-20 outcomes), synonyms: [bad-case exposure, bad case, worst case exposure, tail risk, downside exposure]}
      - {name: mtbf, expr: MTBF, data_type: FLOAT, description: Mean time between failures (operating hours)}
      - {name: mttr, expr: MTTR, data_type: NUMBER, description: Mean time to repair (hours)}
      - {name: data_confidence, expr: DATA_CONFIDENCE, data_type: FLOAT, description: Per-insight data-readiness confidence 0-1}
      - {name: recommended_action_count, expr: RECOMMENDED_ACTION_COUNT, data_type: NUMBER, description: Number of recommended actions}

  # ------------------------------------------------------------- persona view
  - name: insight_persona_view
    description: One issue rendered as five persona decision surfaces (dealer, product, manufacturing, supply chain, executive).
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_PERSONA_VIEW}
    dimensions:
      - {name: issue_id, expr: ISSUE_ID, data_type: TEXT}
      - {name: persona, expr: PERSONA, data_type: TEXT, description: "DEALER / PRODUCT / MANUFACTURING / SUPPLY_CHAIN / EXECUTIVE", synonyms: [role, lens]}
      - {name: view_level, expr: VIEW_LEVEL, data_type: TEXT}
      - {name: diagnose_question, expr: DIAGNOSE_QUESTION, data_type: TEXT}
      - {name: diagnose_answer_text, expr: DIAGNOSE_ANSWER_TEXT, data_type: TEXT}
      - {name: primary_metric_name, expr: PRIMARY_METRIC_NAME, data_type: TEXT, description: "Persona metric: PDI/MTBF/rework/SQPI/exposure"}
      - {name: action_summary, expr: ACTION_SUMMARY, data_type: TEXT}
    facts:
      - {name: primary_metric_value, expr: PRIMARY_METRIC_VALUE, data_type: FLOAT, description: Value of the persona primary metric}
      - {name: primary_metric_target, expr: PRIMARY_METRIC_TARGET, data_type: NUMBER, description: Target for the persona metric}

  # --------------------------------------------------------- risk assessment
  - name: insight_risk_assessment
    description: Per-issue multi-pillar risk ratings (safety, productivity, downtime, exposure, customer).
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_RISK_ASSESSMENT}
    dimensions:
      - {name: issue_id, expr: ISSUE_ID, data_type: TEXT}
      - {name: safety_rating, expr: SAFETY_RATING, data_type: TEXT}
      - {name: productivity_rating, expr: PRODUCTIVITY_RATING, data_type: TEXT}
      - {name: downtime_rating, expr: DOWNTIME_RATING, data_type: TEXT}
      - {name: warranty_exposure_rating, expr: WARRANTY_EXPOSURE_RATING, data_type: TEXT}
      - {name: customer_impact_rating, expr: CUSTOMER_IMPACT_RATING, data_type: TEXT}
      - {name: overall_risk, expr: OVERALL_RISK, data_type: TEXT, synonyms: [risk level]}
      - {name: headline_text, expr: HEADLINE_TEXT, data_type: TEXT}

  # ---------------------------------------------------------------- actions
  - name: insight_action
    description: Recommended, time-windowed next-best actions per issue (closed-loop).
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_ACTION}
    primary_key: {columns: [ACTION_ID]}
    dimensions:
      - {name: action_id, expr: ACTION_ID, data_type: TEXT}
      - {name: issue_id, expr: ISSUE_ID, data_type: TEXT}
      - {name: owner_persona, expr: OWNER_PERSONA, data_type: TEXT, synonyms: [owner, responsible]}
      - {name: time_window, expr: TIME_WINDOW, data_type: TEXT, description: "0_24h / 24_48h / 48_72h / ONGOING"}
      - {name: action_text, expr: ACTION_TEXT, data_type: TEXT, synonyms: [action, recommendation]}
      - {name: action_rationale, expr: ACTION_RATIONALE, data_type: TEXT}
      - {name: source, expr: SOURCE, data_type: TEXT}
      - {name: status, expr: STATUS, data_type: TEXT}
    facts:
      - {name: expected_risk_reduction, expr: EXPECTED_RISK_REDUCTION, data_type: NUMBER, description: Expected fractional risk reduction}

  # ------------------------------------------------------- impacted rollups
  - name: insight_impacted_customers
    description: Customers impacted per issue.
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_IMPACTED_CUSTOMERS}
    dimensions:
      - {name: issue_id, expr: ISSUE_ID, data_type: TEXT}
      - {name: entity_name, expr: ENTITY_NAME, data_type: TEXT, synonyms: [customer, account]}
      - {name: geo, expr: GEO, data_type: TEXT}
      - {name: end_market_cd, expr: END_MARKET_CD, data_type: TEXT, synonyms: [segment, end market]}
    facts:
      - {name: units_impacted, expr: EXPOSURE_COUNT, data_type: NUMBER, description: Units impacted for this customer}

  - name: insight_impacted_areas
    description: Geographic areas (US subregions) impacted per issue.
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_IMPACTED_AREAS}
    dimensions:
      - {name: issue_id, expr: ISSUE_ID, data_type: TEXT}
      - {name: area, expr: ENTITY_NAME, data_type: TEXT, synonyms: [region, subregion]}
    facts:
      - {name: units_impacted, expr: EXPOSURE_COUNT, data_type: NUMBER}

  # ------------------------------------------------- customer archetype (customer-back)
  - name: insight_issue_archetype
    description: Per-issue exposure mix across the four customer archetypes (Enterprise/National/Local/Independent) with relative pain and the channel through which each tier's pain surfaces.
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_ISSUE_ARCHETYPE}
    dimensions:
      - {name: issue_id, expr: ISSUE_ID, data_type: TEXT}
      - {name: archetype, expr: ARCHETYPE, data_type: TEXT, synonyms: [customer tier, account tier, customer type, customer archetype]}
      - {name: basis, expr: BASIS, data_type: TEXT, description: EXPOSED (lot) or IMPACTED footprint}
      - {name: quality_definition, expr: QUALITY_DEFINITION, data_type: TEXT, description: How this archetype defines quality}
      - {name: pain_channel, expr: PAIN_CHANNEL, data_type: TEXT, synonyms: [how pain surfaces, channel]}
      - {name: response_mode, expr: RESPONSE_MODE, data_type: TEXT, synonyms: [proactive, reactive]}
    facts:
      - {name: archetype_rank, expr: ARCHETYPE_RANK, data_type: NUMBER}
      - {name: units, expr: UNITS, data_type: NUMBER, description: Exposed/impacted units for this archetype}
      - {name: customers, expr: CUSTOMERS, data_type: NUMBER}
      - {name: per_unit_usd, expr: PER_UNIT_USD, data_type: NUMBER}
      - {name: relative_pain_per_unit, expr: RELATIVE_PAIN_PER_UNIT, data_type: NUMBER, description: Per-unit dollar impact as a share of the archetype's operation}
      - {name: pain_share_pct, expr: PAIN_SHARE_PCT, data_type: NUMBER, synonyms: [felt pain share, share of pain]}

  - name: insight_issue_customer_back
    description: Customer-back priority rollup per issue — standard rank vs customer-back rank (pain intensity; safety stays absolute) plus the dominant-pain archetype and channel.
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_ISSUE_CUSTOMER_BACK}
    dimensions:
      - {name: issue_id, expr: ISSUE_ID, data_type: TEXT}
      - {name: quality_dimension, expr: QUALITY_DIMENSION, data_type: TEXT}
      - {name: dominant_archetype, expr: DOMINANT_ARCHETYPE, data_type: TEXT, synonyms: [most affected tier, most vulnerable archetype]}
      - {name: dominant_channel, expr: DOMINANT_CHANNEL, data_type: TEXT}
    facts:
      - {name: orig_priority_rank, expr: ORIG_PRIORITY_RANK, data_type: NUMBER, synonyms: [standard rank]}
      - {name: customer_back_rank, expr: CUSTOMER_BACK_RANK, data_type: NUMBER}
      - {name: rank_in_tier, expr: RANK_IN_TIER, data_type: NUMBER}
      - {name: rank_delta, expr: RANK_DELTA, data_type: NUMBER}
      - {name: pain_intensity, expr: PAIN_INTENSITY, data_type: NUMBER}
      - {name: dominant_pain_share_pct, expr: DOMINANT_PAIN_SHARE_PCT, data_type: NUMBER}
      - {name: dominant_units, expr: DOMINANT_UNITS, data_type: NUMBER}

  # ----------------------------------------------------------- metric trend
  - name: insight_metric_trend
    description: Business KPI time series (quality events by pillar and family over time).
    base_table: {database: SF_SOLUTIONS, schema: CQC_INSIGHTS, table: INSIGHT_METRIC_TREND}
    dimensions:
      - {name: metric_name, expr: METRIC_NAME, data_type: TEXT, synonyms: [kpi, metric]}
      - {name: grain, expr: GRAIN, data_type: TEXT}
    time_dimensions:
      - {name: period, expr: PERIOD, data_type: TIMESTAMP_NTZ}
    facts:
      - {name: value, expr: VALUE, data_type: NUMBER}

  # --------------------------------------------------- thin ATOMIC drill: machine
  - name: machine
    description: Machine master (thin drill for serial-level questions).
    base_table: {database: SF_SOLUTIONS, schema: CQC_ATOMIC, table: DIM_MACHINE}
    primary_key: {columns: [MACHINE_KEY]}
    dimensions:
      - {name: machine_key, expr: MACHINE_KEY, data_type: NUMBER}
      - {name: machine_sn, expr: MACHINE_SN, data_type: TEXT, synonyms: [serial, serial number, machine]}
      - {name: model, expr: MODEL, data_type: TEXT}
      - {name: product_family, expr: PRODUCT_FAMILY, data_type: TEXT}
      - {name: global_region, expr: GLOBAL_REGION, data_type: TEXT}
      - {name: us_subregion, expr: US_SUBREGION, data_type: TEXT}
      - {name: build_facility_cd, expr: BUILD_FACILITY_CD, data_type: TEXT, synonyms: [plant, factory]}
    time_dimensions:
      - {name: delivery_date, expr: DELIVERY_DT, data_type: DATE}

  # --------------------------------------------------- thin ATOMIC drill: event
  - name: quality_event
    description: Individual quality events (thin drill for "show events on serial X").
    base_table: {database: SF_SOLUTIONS, schema: CQC_ATOMIC, table: FACT_QUALITY_EVENT}
    primary_key: {columns: [EVENT_KEY]}
    dimensions:
      - {name: event_key, expr: EVENT_KEY, data_type: NUMBER}
      - {name: machine_key, expr: MACHINE_KEY, data_type: NUMBER}
      - {name: model, expr: MODEL, data_type: TEXT}
      - {name: source_system, expr: SOURCE_SYSTEM, data_type: TEXT, synonyms: [source, channel]}
      - {name: system_group_cd, expr: SYSTEM_GROUP_CD, data_type: TEXT}
      - {name: failure_mode_cd, expr: FAILURE_MODE_CD, data_type: TEXT}
      - {name: quality_dimension_cd, expr: QUALITY_DIMENSION_CD, data_type: TEXT}
      - {name: severity_cd, expr: SEVERITY_CD, data_type: TEXT}
    time_dimensions:
      - {name: event_date, expr: EVENT_DATE, data_type: DATE}
    facts:
      - {name: repair_cost_usd, expr: REPAIR_COST_USD, data_type: FLOAT}
      - {name: downtime_hours, expr: DOWNTIME_HOURS, data_type: FLOAT}

relationships:
  - {name: persona_to_issue, left_table: insight_persona_view, right_table: insight_issue, relationship_columns: [{left_column: ISSUE_ID, right_column: ISSUE_ID}], relationship_type: many_to_one}
  - {name: risk_to_issue, left_table: insight_risk_assessment, right_table: insight_issue, relationship_columns: [{left_column: ISSUE_ID, right_column: ISSUE_ID}], relationship_type: many_to_one}
  - {name: action_to_issue, left_table: insight_action, right_table: insight_issue, relationship_columns: [{left_column: ISSUE_ID, right_column: ISSUE_ID}], relationship_type: many_to_one}
  - {name: impcust_to_issue, left_table: insight_impacted_customers, right_table: insight_issue, relationship_columns: [{left_column: ISSUE_ID, right_column: ISSUE_ID}], relationship_type: many_to_one}
  - {name: imparea_to_issue, left_table: insight_impacted_areas, right_table: insight_issue, relationship_columns: [{left_column: ISSUE_ID, right_column: ISSUE_ID}], relationship_type: many_to_one}
  - {name: event_to_machine, left_table: quality_event, right_table: machine, relationship_columns: [{left_column: MACHINE_KEY, right_column: MACHINE_KEY}], relationship_type: many_to_one}
  - {name: archetype_to_issue, left_table: insight_issue_archetype, right_table: insight_issue, relationship_columns: [{left_column: ISSUE_ID, right_column: ISSUE_ID}], relationship_type: many_to_one}
  - {name: custback_to_issue, left_table: insight_issue_customer_back, right_table: insight_issue, relationship_columns: [{left_column: ISSUE_ID, right_column: ISSUE_ID}], relationship_type: many_to_one}

verified_queries:
  - name: top_issues_by_impact
    question: What are the top 10 quality issues by customer impact right now?
    sql: SELECT title, quality_dimension, priority_rank, exposed_fleet_count, impacted_customer_count, warranty_exposure_p90 FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE ORDER BY priority_rank ASC LIMIT 10
  - name: biggest_safety_issue
    question: What is our biggest safety-priority quality issue and why?
    sql: SELECT title, model, system_group, failure_mode, exposed_fleet_count, pro_sif_risk, root_cause_summary, rationale_text, data_confidence_band FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE WHERE quality_dimension = 'SAFETY' ORDER BY priority_rank ASC LIMIT 1
  - name: fuel_system_exposure
    question: What is the warranty exposure for the LX-950 fuel-system issue?
    sql: SELECT title, exposed_fleet_count, warranty_exposure_p50, warranty_exposure_p90, warranty_exposure_cvar, root_cause_summary FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE WHERE model = 'LX-950' AND system_group = 'ENGINE_FUEL' AND failure_mode = 'POWER_LOSS'
  - name: most_affected_segment
    question: Which end-market segment is most affected?
    sql: SELECT end_market_cd, SUM(exposure_count) AS units FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_IMPACTED_CUSTOMERS GROUP BY 1 ORDER BY units DESC
  - name: emerging_vs_recurring
    question: Which failure modes are emerging versus recurring?
    sql: SELECT system_group, failure_mode, lifecycle_stage, COUNT(*) AS issues, SUM(exposed_fleet_count) AS exposed FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE GROUP BY 1,2,3 ORDER BY exposed DESC
  - name: systemic_or_isolated
    question: Is the LX-950 fuel-system issue systemic or isolated to a lot?
    sql: SELECT title, root_cause_type, lot_key, root_cause_summary, root_cause_confidence FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE WHERE model = 'LX-950' AND system_group = 'ENGINE_FUEL' AND root_cause_type = 'LOT'
  - name: mtbf_affected_component
    question: What is the MTBF on the affected LX-950 fuel system component?
    sql: SELECT title, mtbf, mttr, failure_mode FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE WHERE model = 'LX-950' AND system_group = 'ENGINE_FUEL' ORDER BY priority_rank
  - name: exec_persona_view
    question: Show the executive view for the top priority issue
    sql: SELECT p.persona, p.diagnose_answer_text, p.primary_metric_name, p.primary_metric_value, p.action_summary FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_PERSONA_VIEW p JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON i.issue_id = p.issue_id WHERE i.priority_rank = 1 AND p.persona = 'EXECUTIVE'
  - name: actions_next_72h
    question: What should we do in the next 72 hours for the fuel-system issue?
    sql: SELECT a.time_window, a.action_text, a.owner_persona, a.expected_risk_reduction FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ACTION a JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON i.issue_id = a.issue_id WHERE i.model = 'LX-950' AND i.system_group = 'ENGINE_FUEL' ORDER BY a.time_window
  - name: archetype_mix_fuel
    question: For the LX-950 fuel-system power-loss issue, how is the exposed fleet split across customer archetypes and who bears the most pain?
    sql: SELECT a.archetype, a.units, a.pain_share_pct, a.quality_definition, a.pain_channel FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE_ARCHETYPE a JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON i.issue_id = a.issue_id WHERE i.model = 'LX-950' AND i.system_group = 'ENGINE_FUEL' AND i.root_cause_type = 'LOT' ORDER BY a.archetype_rank
  - name: most_vulnerable_archetype
    question: Which customer archetype feels the LX-950 fuel-system issue most acutely and how should we reach them?
    sql: SELECT cb.dominant_archetype, cb.dominant_pain_share_pct, cb.dominant_channel FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE_CUSTOMER_BACK cb JOIN SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE i ON i.issue_id = cb.issue_id WHERE i.model = 'LX-950' AND i.system_group = 'ENGINE_FUEL' AND i.root_cause_type = 'LOT'

custom_instructions: >
  CQC is Acme Industrial's Construction Equipment Division customer-quality command system.
  ALWAYS respect the customer-pain hierarchy: SAFETY outranks PRODUCTIVITY outranks
  EXPERIENCE (safety-gated). When ranking or summarizing issues, surface SAFETY-dimension
  issues first, then order by priority_rank (1 = highest). Persona metrics: Dealer=PDI rate,
  Product=MTBF/MTTR, Manufacturing=rework minutes / first-pass yield, Supply Chain=SQPI,
  Executive=downtime & warranty exposure. Ideal-state metrics: SIP (safety), VTC
  value-to-cost (productivity), CEI customer experience index (experience). When a persona
  is supplied, answer through that persona's lens and lead with their primary metric from
  insight_persona_view. Speak in business terms: machine serials, operating hours, USD exposure,
  supplier lots, build facilities. The flagship anchor scenario is a LX-950 Large Excavator
  fuel-system defect concentrated in supplier lots L-4471, L-4472 and L-4480 (strongest: L-4480) built at South Plant, GA. Always cite
  data_confidence when available. Never invent numbers not present in the data.
  Describe warranty exposure in plain language: warranty_exposure_p50 = "likely exposure",
  warranty_exposure_p90 = "plan-for exposure" (the budgeting figure), warranty_exposure_cvar =
  "bad-case exposure". Never use the terms P50, P90, CVaR or percentile in answers.
  CUSTOMER ARCHETYPE (customer-back): every customer is one of four tiers — ENTERPRISE
  (strategic, portfolio TCO, reached via account team + exec), NATIONAL (corporate, fleet
  uptime, reached via account manager + dealer), LOCAL (regional, cost-per-hour, reached via
  dealer), INDEPENDENT (owner-operator, "machine works when needed", reached at the service
  counter). The SAME defect is felt differently by tier: use insight_issue_archetype for the
  per-issue mix and pain_share_pct (felt pain), and insight_issue_customer_back for the
  dominant archetype/channel and customer-back rank. Safety stays absolute; customer-back only
  re-ranks productivity/experience. When asked who is most hurt or how to reach them, lead with
  the dominant archetype, its pain_share_pct, and its pain_channel.
$$);

-- -------------------------------------------------------------------------
-- Cortex Search services and Cortex Agent
-- Source: platform/cortex/deploy_customer_quality_agent.sql
-- -------------------------------------------------------------------------

-- Tech-doc search (TSB / bulletins / advisories) for action grounding
CREATE OR REPLACE CORTEX SEARCH SERVICE SF_SOLUTIONS.CQC_DOCS.TECH_DOC_SEARCH
  ON content
  ATTRIBUTES doc_id, doc_type, model, system_group_cd
  WAREHOUSE = SF_SOLUTIONS_WH TARGET_LAG = '1 day'
  COMMENT = 'Cortex Search over technical documents (bulletins, service procedures, safety advisories)'
AS (
  SELECT doc_id, doc_type, model, system_group_cd,
         title || '. ' || body_txt AS content
  FROM SF_SOLUTIONS.CQC_STAGING.STG_DOC_TECH
);

-- Insight evidence search (the "why" — grounded rationale + root cause per issue)
CREATE OR REPLACE CORTEX SEARCH SERVICE SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_EVIDENCE_SEARCH
  ON content
  ATTRIBUTES issue_id, model, system_group, quality_dimension
  WAREHOUSE = SF_SOLUTIONS_WH TARGET_LAG = '1 day'
  COMMENT = 'Cortex Search over CQC insight rationale + root cause for why-questions'
AS (
  SELECT issue_id, model, system_group, quality_dimension,
         title || '. ' || COALESCE(summary_text,'') || ' ' || COALESCE(rationale_text,'')
           || ' Root cause: ' || COALESCE(root_cause_summary,'') AS content
  FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE
);

CREATE OR REPLACE AGENT SF_SOLUTIONS.CQC_ML.CUSTOMER_QUALITY_AGENT
FROM SPECIFICATION $$
{
  "models": {"orchestration": "auto"},
  "orchestration": {"budget": {"seconds": 900, "tokens": 400000}},
  "instructions": {
    "orchestration": "You are CQC, Acme Industrial's Construction Equipment Division customer-quality command-and-response engine. You turn quality questions into data-grounded, decision-ready answers in seconds for dealers, product, manufacturing, supply-chain, and executive personas.\n\nCustomer-pain hierarchy (ALWAYS honor, safety-gated): SAFETY > PRODUCTIVITY > EXPERIENCE. Surface SAFETY-dimension issues first, then order by priority_rank (1 = highest).\n\nData model: everything is organized around governable ISSUES (insight_issue), each with business impact (SIP safety risk, VTC productivity USD, CEI experience), financial exposure (P50/P90/CVaR), root cause (LOT/DESIGN/ISOLATED), exposed fleet, impacted customers/dealers/facilities/areas, persona views, risk assessment, and time-windowed recommended actions. A per-insight data_confidence quantifies readiness.\n\nAnchor context: the flagship scenario is a LX-950 Large Excavator fuel-system defect concentrated in supplier lots L-4471, L-4472 and L-4480 (strongest: L-4480) built at South Plant, GA (infant-mortality failures, safety-gated sudden-shutdown + productivity power-loss).\n\nCustomer archetype (customer-back): every customer is one of four tiers — ENTERPRISE (portfolio TCO; reach via account team + executive touchpoints), NATIONAL (fleet uptime & consistency; account manager + dealer), LOCAL (cost-per-hour; dealer relationship), INDEPENDENT (machine works when needed; service counter, machine-by-machine). The SAME defect is felt differently by tier. Use quality_analyst over insight_issue_archetype (pain_share_pct = felt pain) and insight_issue_customer_back (dominant archetype/channel, customer-back rank). Safety stays absolute; customer-back only re-ranks productivity/experience. For 'who is hurt most / how do we reach them', lead with the dominant archetype, its pain_share_pct and pain_channel.\n\nTool selection:\n- quality_analyst: ALL quantitative questions over INSIGHTS (issues, impact, exposure, persona metrics PDI/MTBF/MTTR/rework/SQPI/downtime, trends, impacted rollups).\n- insight_evidence_search: 'why' questions — retrieve the grounded rationale and root cause.\n- tech_doc_search: service bulletins / service procedures / safety advisories for action grounding.\n- detect_emerging: 'what is emerging / getting worse' — CUSUM/change-point signals.\n- simulate_exposure: 'what if this spreads' financial exposure for an issue.\n- recommend_actions: time-windowed next-best actions for an issue.\n- allocate_resources: executive 'allocate limited containment/field capacity'.\nWhen a persona is provided in the message, answer through that persona's lens and lead with their primary metric from insight_persona_view.",
    "response": "Executive-ready and concise.\n- Lead with the direct answer, then cite the materialized evidence (stats, root cause, exposure).\n- ALWAYS state data-confidence when available (e.g. 'confidence: HIGH').\n- End with the recommended action and its time window.\n- Use tables for comparisons; show USD exposure and machine serials/operating hours in business terms.\n- Never invent numbers not present in the data.\n- Describe warranty exposure in plain language: 'likely exposure' (warranty_exposure_p50), 'plan-for exposure' (warranty_exposure_p90, the budgeting figure) and 'bad-case exposure' (warranty_exposure_cvar, average of the worst 1-in-20 outcomes). Never write P50, P90, CVaR, percentile or value-at-risk.",
    "sample_questions": [
      {"question": "What's our biggest safety-priority quality issue and why?"},
      {"question": "What is the warranty exposure if the LX-950 fuel-system issue spreads?"},
      {"question": "Which of my customers are most at risk?"},
      {"question": "Which failure modes are emerging versus recurring?"},
      {"question": "Is the fuel-system issue systemic or isolated to a lot?"},
      {"question": "What should we do in the next 72 hours?"}
    ]
  },
  "tools": [
    {"tool_spec": {"type": "cortex_analyst_text_to_sql", "name": "quality_analyst", "description": "CQCQualityAnalytics: queries governable quality issues, S/P/E classification and priority, SIP/VTC/CEI impact, financial exposure (P50/P90/CVaR), root cause, exposed fleet, impacted customers/dealers/facilities/areas, persona metrics (PDI, MTBF/MTTR, rework, SQPI, downtime), risk assessments, recommended actions, and KPI trends. Use for ALL quantitative questions."}},
    {"tool_spec": {"type": "cortex_search", "name": "insight_evidence_search", "description": "InsightEvidenceSearch: grounded rationale and root-cause narratives per quality issue. Use for 'why' questions and to explain a diagnosis. Filter by issue_id, model, system_group, quality_dimension."}},
    {"tool_spec": {"type": "cortex_search", "name": "tech_doc_search", "description": "TechDocSearch: Acme Industrial service bulletins, service procedures, and safety advisories. Use to ground recommended actions and repair guidance. Filter by model, system_group_cd, doc_type."}},
    {"tool_spec": {"type": "generic", "name": "detect_emerging", "description": "DetectEmerging: returns quality issues currently alarming (CUSUM/change-point) by model and system group. Use for 'what is emerging / getting worse'.", "input_schema": {"type": "object", "properties": {}, "required": []}}},
    {"tool_spec": {"type": "generic", "name": "simulate_exposure", "description": "SimulateExposure: returns Gaussian-copula Monte Carlo financial exposure (P50/P90/CVaR) for an issue. Use for 'what if this spreads'.", "input_schema": {"type": "object", "properties": {"ISSUE_ID": {"type": "string", "description": "The issue_id to simulate exposure for."}}, "required": ["ISSUE_ID"]}}},
    {"tool_spec": {"type": "generic", "name": "recommend_actions", "description": "RecommendActions: returns time-windowed (0-24h/24-48h/48-72h) next-best actions for an issue. Use when asked what to do.", "input_schema": {"type": "object", "properties": {"ISSUE_ID": {"type": "string", "description": "The issue_id to recommend actions for."}}, "required": ["ISSUE_ID"]}}},
    {"tool_spec": {"type": "generic", "name": "allocate_resources", "description": "AllocateResources: greedy safety-first allocation of limited containment/field-service capacity across issues. Use for executive resource allocation.", "input_schema": {"type": "object", "properties": {"CAPACITY_UNITS": {"type": "number", "description": "Number of capacity units available."}}, "required": ["CAPACITY_UNITS"]}}}
  ],
  "tool_resources": {
    "quality_analyst": {"execution_environment": {"query_timeout": 299, "type": "warehouse", "warehouse": "SF_SOLUTIONS_WH"}, "semantic_view": "SF_SOLUTIONS.CQC_ML.CUSTOMER_QUALITY_MODEL"},
    "insight_evidence_search": {"execution_environment": {"query_timeout": 299, "type": "warehouse", "warehouse": "SF_SOLUTIONS_WH"}, "search_service": "SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_EVIDENCE_SEARCH"},
    "tech_doc_search": {"execution_environment": {"query_timeout": 299, "type": "warehouse", "warehouse": "SF_SOLUTIONS_WH"}, "search_service": "SF_SOLUTIONS.CQC_DOCS.TECH_DOC_SEARCH"},
    "detect_emerging": {"type": "procedure", "identifier": "SF_SOLUTIONS.CQC_ML.SP_DETECT_EMERGING_ISSUES", "execution_environment": {"type": "warehouse", "warehouse": "SF_SOLUTIONS_WH", "query_timeout": 300}},
    "simulate_exposure": {"type": "procedure", "identifier": "SF_SOLUTIONS.CQC_ML.SP_SIMULATE_EXPOSURE", "execution_environment": {"type": "warehouse", "warehouse": "SF_SOLUTIONS_WH", "query_timeout": 300}},
    "recommend_actions": {"type": "procedure", "identifier": "SF_SOLUTIONS.CQC_ML.SP_RECOMMEND_ACTIONS", "execution_environment": {"type": "warehouse", "warehouse": "SF_SOLUTIONS_WH", "query_timeout": 300}},
    "allocate_resources": {"type": "procedure", "identifier": "SF_SOLUTIONS.CQC_ML.SP_ALLOCATE_RESOURCES", "execution_environment": {"type": "warehouse", "warehouse": "SF_SOLUTIONS_WH", "query_timeout": 300}}
  }
}
$$;

ALTER AGENT SF_SOLUTIONS.CQC_ML.CUSTOMER_QUALITY_AGENT SET COMMENT = 'CQC — Acme Industrial CED Customer-Quality command agent (Ask CQC); 7 tools over INSIGHTS';

SHOW AGENTS LIKE 'CUSTOMER_QUALITY_AGENT' IN SCHEMA SF_SOLUTIONS.CQC_ML;

-- -------------------------------------------------------------------------
-- Agent evaluation dataset and weekly task
-- Source: platform/cortex/evaluations/054_agent_eval.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_ML;

CREATE OR REPLACE TABLE EVAL_DATASET_CUSTOMER_QUALITY_AGENT (
    id NUMBER, category STRING, question STRING,
    expected_tools ARRAY, ground_truth STRING
);
INSERT INTO EVAL_DATASET_CUSTOMER_QUALITY_AGENT
SELECT 1,'anchor','Why are LX-950 units disproportionately affected by the fuel-system issue?',
       ARRAY_CONSTRUCT('insight_evidence_search','quality_analyst'),
       'Root cause is supplier lot L-4471/4472/4480 built at South Plant, GA; concentration lift ~3.4-4.3x, z~5.9; infant-mortality.'
UNION ALL SELECT 2,'anchor','What is the warranty exposure if the LX-950 fuel-system issue spreads?',
       ARRAY_CONSTRUCT('simulate_exposure','quality_analyst'),
       'Exposed fleet ~63; exposure P50 ~$174k, P90 ~$237k, CVaR95 ~$264k (Gaussian copula).'
UNION ALL SELECT 3,'safety','What is our biggest safety-priority quality issue and why?',
       ARRAY_CONSTRUCT('quality_analyst','insight_evidence_search'),
       'A SAFETY-dimension SUDDEN_SHUTDOWN issue surfaces first (safety gate); cite SIP risk and exposed fleet.'
UNION ALL SELECT 4,'executive','Top 10 quality issues by customer impact right now',
       ARRAY_CONSTRUCT('quality_analyst'),
       'Ranked by priority_rank with SAFETY issues first; returns 10 rows.'
UNION ALL SELECT 5,'dealer','Which of my customers are most at risk?',
       ARRAY_CONSTRUCT('quality_analyst'),
       'Impacted customers ranked by units_impacted from insight_impacted_customers.'
UNION ALL SELECT 6,'product','Which failure modes are emerging versus recurring?',
       ARRAY_CONSTRUCT('quality_analyst','detect_emerging'),
       'Group by lifecycle_stage; fuel-system on LX-950 flagged EMERGING (changepoint 2024-08).'
UNION ALL SELECT 7,'manufacturing','Which line/lot is driving the LX-950 fuel issue?',
       ARRAY_CONSTRUCT('quality_analyst','insight_evidence_search'),
       'Lot L-4471 group built at South Plant, GA; lot-concentrated root cause.'
UNION ALL SELECT 8,'supply_chain','Is the fuel-system issue systemic or isolated to a lot?',
       ARRAY_CONSTRUCT('quality_analyst'),
       'Isolated to specific supplier lots (root_cause_type=LOT), not systemic across the family.'
UNION ALL SELECT 9,'action','What should we do in the next 72 hours for the fuel-system issue?',
       ARRAY_CONSTRUCT('recommend_actions','tech_doc_search'),
       'Contain suspect lot (0-24/24-48h, supply_chain owner) + safety advisory; cite bulletin TSB-2025-FUEL-01.'
UNION ALL SELECT 10,'trust','What is the data confidence behind the fuel-system insight?',
       ARRAY_CONSTRUCT('quality_analyst'),
       'data_confidence_band HIGH; based on thousands of events across the exposed fleet.'
UNION ALL SELECT 11,'exec_action','Allocate our limited containment capacity across issues',
       ARRAY_CONSTRUCT('allocate_resources'),
       'Greedy safety-first allocation; SAFETY issues get capacity before productivity.'
UNION ALL SELECT 12,'edge','What is the MTBF on the affected LX-950 fuel component?',
       ARRAY_CONSTRUCT('quality_analyst'),
       'MTBF from reliability fit for LX-950 ENGINE_FUEL; degraded vs family baseline.';

-- Weekly regression task (runs the eval when a judge model is configured).
-- Placeholder body calls a harness proc; enable once EXECUTE_AI_EVALUATION judge available.
CREATE OR REPLACE TASK CQC_ML.TASK_AGENT_EVAL_WEEKLY
  WAREHOUSE = SF_SOLUTIONS_WH
  SCHEDULE = 'USING CRON 0 6 * * 1 America/Chicago'
  COMMENT = 'Weekly CQC agent eval regression (enable when LLM judge model available)'
AS
  SELECT 'CQC agent eval regression placeholder — wire EXECUTE_AI_EVALUATION with claude-opus-5-5 judge' AS note;
-- (left SUSPENDED by default; ALTER TASK ... RESUME to enable)

SELECT category, COUNT(*) n FROM EVAL_DATASET_CUSTOMER_QUALITY_AGENT GROUP BY 1 ORDER BY 1;

-- Make the agent visible in Snowflake Intelligence / CoWork
GRANT USAGE ON AGENT SF_SOLUTIONS.CQC_ML.CUSTOMER_QUALITY_AGENT TO ROLE PUBLIC;

SELECT 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
    || '/#/agents/database/SF_SOLUTIONS/schema/CQC_ML/agent/CUSTOMER_QUALITY_AGENT/details' AS AGENT_URL;
