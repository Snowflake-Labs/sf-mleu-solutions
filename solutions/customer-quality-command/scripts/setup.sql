-- =============================================================================
-- Solution: Customer Quality Command (CQC) - setup
-- Database: SF_SOLUTIONS
-- Schemas:  CQC_RAW, CQC_STAGING, CQC_ATOMIC, CQC_FEATURE_STORE, CQC_ML, CQC_ANALYTICS, CQC_INSIGHTS, CQC_ACTION, CQC_DOCS
-- Creates schemas, RAW landing tables, and the Python generator / ML procedures.
-- Run order: setup.sql -> data.sql -> pipeline.sql
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Shared infrastructure (idempotent; never dropped by teardown)
CREATE DATABASE IF NOT EXISTS SF_SOLUTIONS;
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
    WITH WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Solution schemas
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_RAW
  COMMENT = 'Source-shaped landing of synthetic customer-quality feeds (native grain).';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_STAGING
  COMMENT = 'Conformed feeds: STG_* + REF_* vocabularies + MAP_* crosswalks + data-quality checks.';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_ATOMIC
  COMMENT = 'Dimensions, FACT_QUALITY_EVENT spine, S/P/E classification, lot genealogy.';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_FEATURE_STORE
  COMMENT = 'Model features for the ML suite.';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_ML
  COMMENT = 'ML outputs, Model Registry models, agent procedures, semantic view, agent.';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_ANALYTICS
  COMMENT = 'Derived ISSUE entity, persona and ideal-state metrics, impacted rollups.';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_INSIGHTS
  COMMENT = 'INSIGHT_ISSUE hub + satellites, explainability as data.';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_ACTION
  COMMENT = 'Closed-loop workflow: items, events, SLA, owners.';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_DOCS
  COMMENT = 'Technical documents for Cortex Search (bulletins, procedures, advisories).';

-- Scale setting read by SP_GENERATE_RAW (default 40,800 machines, the size the demo
-- story is written for). For a quicker, smaller build run this before data.sql:
--   UPDATE SF_SOLUTIONS.CQC_RAW.CQC_CONFIG SET VALUE = '5000' WHERE KEY = 'N_MACHINES';
CREATE TABLE IF NOT EXISTS SF_SOLUTIONS.CQC_RAW.CQC_CONFIG (KEY VARCHAR, VALUE VARCHAR);
MERGE INTO SF_SOLUTIONS.CQC_RAW.CQC_CONFIG t USING (SELECT 'N_MACHINES' AS KEY, '40800' AS VALUE) s
  ON t.KEY = s.KEY
  WHEN NOT MATCHED THEN INSERT VALUES (s.KEY, s.VALUE);

-- -------------------------------------------------------------------------
-- RAW landing tables
-- Source: platform/ddl/010_raw.sql
-- -------------------------------------------------------------------------

USE SCHEMA CQC_RAW;

-- ---------------------------------------------------------------------------
-- A. Product genealogy & master data — the stitch backbone
-- ---------------------------------------------------------------------------

-- 1 row per component installed on a machine (as-built / serial build).
CREATE OR REPLACE TABLE RAW_PRODUCT_GENEALOGY (
    machine_sn   STRING       NOT NULL,        -- machine serial (join backbone)
    engine_sn          STRING,                       -- engine serial
    config_no     STRING,                        -- configuration number
    part_no            STRING,                        -- installed part number
    component_sn       STRING,                        -- component serial
    supplier_lot_no    STRING,                        -- supplier lot (lot-tracing key)
    supplier_id        STRING,                        -- supplier of the component
    build_facility_cd  STRING,                        -- assembling facility code
    build_dt           DATE,                          -- component install / build date
    system_group       STRING                         -- e.g. Fuel System, Hydraulics
) COMMENT = 'As-built genealogy: one row per component on a machine. Lot-tracing spine.';

-- 1 row per machine (warranty registration / owner portal).
CREATE OR REPLACE TABLE RAW_MACHINE_REGISTRATION (
    machine_sn   STRING       NOT NULL,
    model              STRING,                         -- e.g. LX-950, EX-220, DZ-60, WL-190
    model_family       STRING,                         -- Large Excavator, Dozer, Wheel Loader...
    sales_model        STRING,                         -- marketed sales model string
    customer_acct      STRING,                         -- owning customer account
    dealer_cd          STRING,                         -- selling/servicing dealer
    delivery_dt        DATE,
    warranty_start_dt  DATE,
    warranty_months    NUMBER(4,0),
    ext_coverage_flag           BOOLEAN,                         -- extended coverage plan
    service_agreement_flag           BOOLEAN,                         -- service agreement
    build_facility_cd  STRING,
    region_cd          STRING
) COMMENT = 'One row per machine: registration, model, ownership, coverage.';

-- 1 row per part (Service Info / parts master).
CREATE OR REPLACE TABLE RAW_PART_MASTER (
    part_no          STRING       NOT NULL,
    part_desc        STRING,
    system_group     STRING,                            -- Fuel System, Hydraulics, Powertrain...
    supplier_id      STRING,
    serviceable_flag BOOLEAN
) COMMENT = 'One row per part: description, system group, supplier.';

-- 1 row per customer account (dealer / CRM master).
CREATE OR REPLACE TABLE RAW_CUSTOMER_MASTER (
    acct_no     STRING       NOT NULL,
    name        STRING,
    industry    STRING,                                 -- Infra / NonRes / Res / Quarry&Agg / Rental
    size_band   STRING,                                 -- Small / Medium / Large / Major
    region_cd   STRING,
    country_cd  STRING,
    state_cd    STRING
) COMMENT = 'One row per customer account.';

-- 1 row per dealer (dealer master).
CREATE OR REPLACE TABLE RAW_DEALER_MASTER (
    dealer_cd  STRING       NOT NULL,
    name       STRING,
    branch     STRING,
    territory  STRING,
    region_cd  STRING,
    country_cd STRING,
    state_cd   STRING
) COMMENT = 'One row per dealer.';

-- ---------------------------------------------------------------------------
-- B. Field service & product problems — highest-volume signal
-- ---------------------------------------------------------------------------

-- Dealer Service Records: 1 row per dealer service/repair report. 3C coding.
CREATE OR REPLACE TABLE RAW_DEALER_SERVICE (
    service_record_id         STRING       NOT NULL,
    machine_sn STRING,
    dealer_cd       STRING,
    repair_dt       DATE,
    op_hours       NUMBER(10,1),                       -- operating hours at repair
    complaint_cd    STRING,                             -- 3C: Complaint
    cause_cd        STRING,                             -- 3C: Cause
    correction_cd   STRING,                             -- 3C: Correction
    system_group    STRING,
    part_no         STRING,
    labor_hrs       NUMBER(8,2),
    job_story_txt   STRING                              -- free-text technician narrative
) COMMENT = 'Dealer Service Records service/repair reports at dealer-report grain (3C coded).';

-- Warranty claim: header + labor/parts summarized on the row.
CREATE OR REPLACE TABLE RAW_WARRANTY_CLAIM (
    claim_no          STRING       NOT NULL,
    machine_sn  STRING,
    dealer_cd         STRING,
    failure_dt        DATE,
    claim_dt          DATE,
    part_no           STRING,
    group_no          STRING,                           -- warranty group
    system_group      STRING,
    labor_hrs         NUMBER(8,2),
    parts_amt         NUMBER(12,2),
    labor_amt         NUMBER(12,2),
    total_claim_amt   NUMBER(12,2),
    months_in_service NUMBER(6,2),
    op_hours_at_failure    NUMBER(10,1)
) COMMENT = 'Warranty claims: failure/claim dates, cost, months-in-service, operating hours.';

-- TAC: 1 row per technical case dealer -> manufacturer.
CREATE OR REPLACE TABLE RAW_TECH_ASSIST_CASE (
    tac_id          STRING       NOT NULL,
    machine_sn STRING,
    model            STRING,
    system_group     STRING,
    open_ts          TIMESTAMP_NTZ,
    close_ts         TIMESTAMP_NTZ,
    status           STRING,
    problem_txt      STRING,
    resolution_txt   STRING
) COMMENT = 'TAC technical communication cases (dealer to manufacturer).';

-- Inspection App: 1 row per inspection checklist item (PDI / FIELD_INSP_A / FIELD_INSP_B).
CREATE OR REPLACE TABLE RAW_INSPECTION (
    inspection_id    STRING       NOT NULL,
    machine_sn STRING,
    dealer_cd        STRING,
    inspect_dt       DATE,
    inspect_type     STRING,                            -- PDI / FIELD_INSP_A / FIELD_INSP_B
    item_cd          STRING,
    system_group     STRING,
    condition_rating STRING,                            -- Green / Yellow / Red
    finding_txt      STRING
) COMMENT = 'Inspection App digital inspection checklist items.';

-- Fluid Analysis fluid sample: 1 row per sample.
CREATE OR REPLACE TABLE RAW_FLUID_ANALYSIS (
    sample_id        STRING       NOT NULL,
    machine_sn STRING,
    compartment      STRING,                            -- engine / hydraulic / transmission
    sample_dt        DATE,
    op_hours        NUMBER(10,1),
    fe_ppm           NUMBER(8,1),                       -- iron
    cu_ppm           NUMBER(8,1),                       -- copper
    al_ppm           NUMBER(8,1),                       -- aluminum
    si_ppm           NUMBER(8,1),                       -- silicon (dirt ingress)
    visc_cst         NUMBER(8,2),                       -- viscosity
    interp_cd        STRING                             -- normal / monitor / action
) COMMENT = 'Fluid analysis (oil sample) lab results.';

-- ---------------------------------------------------------------------------
-- C. Telematics — machine-generated (telematics platform)
-- ---------------------------------------------------------------------------

-- 1 row per emitted diagnostic code (OEM diagnostic codes (module/component/FMI) + J1939 SPN-FMI). Typed, not VARIANT.
CREATE OR REPLACE TABLE RAW_TELEMATICS_FAULT (
    fault_id         STRING       NOT NULL,
    machine_sn STRING,
    event_ts         TIMESTAMP_NTZ,
    module_id              NUMBER(6,0),                        -- Module Identifier
    component_id              NUMBER(6,0),                        -- Component Identifier
    fmi              NUMBER(4,0),                        -- Failure Mode Identifier
    spn              NUMBER(8,0),                        -- J1939 Suspect Parameter Number
    j1939_fmi        NUMBER(4,0),                        -- J1939 FMI
    system_group     STRING,
    severity_lvl     NUMBER(2,0),                        -- 1..3
    occurrence_cnt   NUMBER(8,0),
    lat              NUMBER(9,6),
    lon              NUMBER(9,6)
) COMMENT = 'Telematics diagnostic fault codes (OEM diagnostic codes (module/component/FMI) + J1939 SPN-FMI).';

-- 1 row per daily machine health snapshot.
CREATE OR REPLACE TABLE RAW_TELEMATICS_HEALTH (
    machine_sn STRING       NOT NULL,
    snapshot_dt      DATE         NOT NULL,
    op_hours        NUMBER(10,1),
    fuel_used_l      NUMBER(10,1),
    idle_pct         NUMBER(5,2),
    load_factor      NUMBER(5,2),
    avg_engine_temp  NUMBER(6,2),
    peak_engine_temp NUMBER(6,2),
    derate_events    NUMBER(6,0)
) COMMENT = 'Telematics periodic machine health snapshots (daily).';

-- ---------------------------------------------------------------------------
-- D. Plant & supplier quality — upstream origination
-- ---------------------------------------------------------------------------

-- MES: 1 row per station inspection/test on a serial.
CREATE OR REPLACE TABLE RAW_MES_QUALITY (
    mes_id           STRING       NOT NULL,
    machine_sn STRING,
    facility_cd      STRING,
    line             STRING,
    shift            STRING,
    station          STRING,
    test_dt          DATE,
    result           STRING,                            -- PASS / FAIL / REWORK
    defect_cd        STRING,
    system_group     STRING,
    rework_min       NUMBER(8,1)
) COMMENT = 'Plant MES station inspection/test records per serial.';

-- Supplier incoming: 1 row per received lot inspected.
CREATE OR REPLACE TABLE RAW_SUPPLIER_INCOMING (
    incoming_id     STRING       NOT NULL,
    supplier_id     STRING,
    part_no         STRING,
    supplier_lot_no STRING,
    recv_dt         DATE,
    qty_recv        NUMBER(10,0),
    qty_reject      NUMBER(10,0),
    defect_cd       STRING
) COMMENT = 'Incoming supplier lot inspection (receiving quality).';

-- SCAR: 1 row per Supplier Corrective Action Request.
CREATE OR REPLACE TABLE RAW_SUPPLIER_SCAR (
    scar_id         STRING       NOT NULL,
    supplier_id     STRING,
    part_no         STRING,
    supplier_lot_no STRING,
    open_dt         DATE,
    close_dt        DATE,
    status          STRING,
    root_cause_txt  STRING,
    corrective_txt  STRING
) COMMENT = 'Supplier Corrective Action Requests (SQE).';

-- ---------------------------------------------------------------------------
-- E. Voice of customer & safety
-- ---------------------------------------------------------------------------

-- VOC survey: 1 row per survey response.
CREATE OR REPLACE TABLE RAW_VOC_SURVEY (
    resp_id          STRING       NOT NULL,
    customer_acct    STRING,
    machine_sn STRING,
    survey_dt        DATE,
    nps              NUMBER(4,0),                        -- -100..100 or 0..10 raw; store raw score
    csat             NUMBER(4,1),
    verbatim_txt     STRING
) COMMENT = 'Customer loyalty / NPS survey responses.';

-- Customer case: 1 row per contact-center case.
CREATE OR REPLACE TABLE RAW_CUSTOMER_CASE (
    case_id          STRING       NOT NULL,
    customer_acct    STRING,
    machine_sn STRING,
    open_ts          TIMESTAMP_NTZ,
    close_ts         TIMESTAMP_NTZ,
    channel          STRING,                             -- phone / web / dealer / app
    category         STRING,
    narrative_txt    STRING
) COMMENT = 'Customer/dealer contact-center cases.';

-- Safety incident: 1 row per incident / near-miss.
CREATE OR REPLACE TABLE RAW_SAFETY_INCIDENT (
    incident_id       STRING       NOT NULL,
    machine_sn  STRING,
    part_no           STRING,
    event_dt          DATE,
    severity          STRING,                            -- Low / Medium / High / Critical
    injury_flag       BOOLEAN,
    sif_potential_flag BOOLEAN,                          -- Serious Injury/Fatality potential
    system_group      STRING,
    description_txt   STRING
) COMMENT = 'Product safety incidents / near-misses.';

-- Field service campaign (FSC). One row per affected serial per program.
CREATE OR REPLACE TABLE RAW_FIELD_CAMPAIGN (
    program_id     STRING       NOT NULL,
    program_type   STRING,                               -- FSC
    model          STRING,
    system_group   STRING,
    affected_sn    STRING,                               -- affected machine_sn
    open_dt        DATE,
    completion_dt  DATE,
    issue_txt      STRING,
    status         STRING
) COMMENT = 'Field service campaigns (FSC): affected serials + completions.';

-- ---------------------------------------------------------------------------
-- F. Unstructured knowledge (-> Cortex Search later)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW_DOC_TECH (
    doc_id       STRING       NOT NULL,
    doc_type     STRING,                                 -- Service Bulletin / Service Procedure / Safety Advisory
    model        STRING,
    system_group STRING,
    issue_dt     DATE,
    title        STRING,
    body_txt     STRING
) COMMENT = 'Technical documents: bulletins, procedures, safety advisories.';

SHOW TABLES IN SCHEMA SF_SOLUTIONS.CQC_RAW;

-- -------------------------------------------------------------------------
-- Synthetic RAW data generator (failure physics)
-- Source: platform/generators/generate_raw.py (ported to a stored procedure)
-- -------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CQC_RAW.SP_GENERATE_RAW()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python==1.53.0', 'snowflake-ml-python==1.46.0', 'pandas==2.3.3', 'numpy', 'scipy==1.15.3', 'scikit-learn==1.7.2', 'xgboost==3.2.0', 'lifelines==0.30.0')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
#!/usr/bin/env python3
"""
CQC Customer Quality — RAW synthetic data generator (failure-physics).

Implements doc 1 §7: genuine stochastic processes, not hand-placed rows.
  1  Latent Weibull(beta, eta) per component x model x failure_mode; right-censored.
  2  Planted lot-concentrated fuel-system defect (the anchor scenario, LX-950).
  3  Pre-failure telematics degradation + precursor diagnostic-code + Fluid Analysis uptick.
  4  Duty-cycle / application covariate (Quarry&Agg accelerates hazard).
  5  MIS build cohorts spread across build months.
  6  Rate change-point after the bad lot ships.
  7  VOC detractors correlated with unresolved fleet issues.
  8  Rare serious-injury-potential (SIP) safety events on fuel sudden-shutdown.
  9  Natural-language text that clusters by underlying issue.
 10  Field campaign (FSC) opened after detection for the exposed serials.

Physics + event-level tables are generated here (Python, numpy vectorized) and
bulk-loaded via write_pandas. The very-high-volume PERIODIC telematics health and
background fault streams are generated in-warehouse by 015_raw_periodic_gen.sql,
coupled to the FAILURE_PROFILE helper table this script writes.

Usage:
    SNOWFLAKE_CONNECTION_NAME=my_snowflake python3 generate_raw.py [--machines N]
"""
import datetime as dt

import numpy as np
import pandas as pd

# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #
SEED = 20260715
OBS_DATE = dt.date(2026, 7, 15)          # "today" — right-censor boundary
BUILD_START = dt.date(2019, 1, 1)
DB = "SF_SOLUTIONS"
SCHEMA = "CQC_RAW"

rng = np.random.default_rng(SEED)

# CED portfolio: model, family, installed count, build facility, avg warranty months.
PORTFOLIO = [
    # model, family,              n,     facility,        warranty_mo
    ("EX-220", "Excavator",         6500,  "PLT_PACIFIC",     12),
    ("EX-260", "Excavator",         3800,  "PLT_PACIFIC",     12),
    ("LX-520", "Large Excavator",   2600,  "PLT_SOUTH",   12),
    ("LX-740", "Large Excavator",   1700,  "PLT_SOUTH",   12),
    ("LX-950", "Large Excavator",   3200,  "PLT_SOUTH",   12),   # ANCHOR family
    ("DZ-60", "Dozer",             4200,  "PLT_CENTRAL",12),
    ("DZ-80", "Dozer",             2400,  "PLT_CENTRAL",12),
    ("WL-150", "Wheel Loader",      5200,  "PLT_NORTH",     12),
    ("WL-170", "Wheel Loader",      3600,  "PLT_NORTH",     12),
    ("WL-190", "Wheel Loader",      2200,  "PLT_NORTH",     12),
    ("MG-14", "Motor Grader",      3100,  "PLT_WEST",        12),
    ("AT-45", "Articulated Truck", 2300,  "PLT_EAST",    12),
]

_BASE_PORTFOLIO = tuple(PORTFOLIO)

INDUSTRIES = ["Infrastructure", "NonResidential", "Residential", "Quarry&Agg", "Rental"]
INDUSTRY_W = [0.28, 0.24, 0.14, 0.20, 0.14]
# Duty cycle: operating hours/day and hazard multiplier (Quarry&Agg is hardest).
DUTY = {
    "Infrastructure": (7.0, 1.05),
    "NonResidential": (6.0, 0.95),
    "Residential":    (4.5, 0.80),
    "Quarry&Agg":     (9.0, 1.55),
    "Rental":         (8.0, 1.20),
}

REGIONS = ["US_SE", "US_S_CENTRAL", "US_MW", "US_W", "US_NE", "CA_W", "CA_E"]
REGION_W = [0.20, 0.18, 0.17, 0.15, 0.12, 0.10, 0.08]
STATES = {
    "US_SE": ["FL", "GA", "NC", "SC", "TN"], "US_S_CENTRAL": ["TX", "OK", "LA", "AR"],
    "US_MW": ["IL", "OH", "IN", "MO", "MI"], "US_W": ["CA", "AZ", "NV", "CO", "WA"],
    "US_NE": ["NY", "PA", "NJ", "MA"], "CA_W": ["BC", "AB"], "CA_E": ["ON", "QC"],
}

# Component x failure_mode catalog: latent Weibull params (eta in operating hours).
# system_group, component, failure_mode, beta, eta_hours, supplier, 3C complaint/cause/correction
COMPONENTS = [
    ("Fuel System", "Fuel Injector",  "injector_fouling",   1.8, 24000, "SUP_FUELSYS_A", "LOW_POWER",     "INJ_DEPOSIT",   "REPLACE_INJECTOR"),
    ("Fuel System", "Fuel Pump",      "pump_pressure_loss", 2.0, 32000, "SUP_FUELSYS_A", "HARD_START",    "PUMP_WEAR",     "REPLACE_PUMP"),
    ("Hydraulics",  "Main Pump",      "pump_cavitation",    2.2, 28000, "SUP_HYD_B",     "SLOW_HYD",      "CAVITATION",    "REPLACE_HYD_PUMP"),
    ("Hydraulics",  "Cylinder Seal",  "seal_leak",          1.5, 20000, "SUP_HYD_B",     "OIL_LEAK",      "SEAL_FAIL",     "RESEAL_CYLINDER"),
    ("Powertrain",  "Final Drive",    "bearing_wear",       2.5, 34000, "SUP_DRV_C",     "NOISE_DRIVE",   "BEARING_WEAR",  "REBUILD_FINAL_DRIVE"),
    ("Powertrain",  "Transmission",   "clutch_slip",        2.3, 38000, "SUP_DRV_C",     "SHIFT_FAULT",   "CLUTCH_WEAR",   "REBUILD_TRANS"),
    ("Engine",      "Turbocharger",   "turbo_failure",      1.9, 30000, "SUP_ENG_D",     "LOW_POWER",     "TURBO_WEAR",    "REPLACE_TURBO"),
    ("Engine",      "Water Pump",     "coolant_leak",       1.7, 27000, "SUP_ENG_D",     "OVERHEAT",      "WPUMP_SEAL",    "REPLACE_WATER_PUMP"),
    ("Cooling",     "Radiator",       "radiator_fouling",   1.6, 30000, "SUP_COOL_E",    "OVERHEAT",      "RAD_BLOCK",     "CLEAN_RADIATOR"),
    ("Electrical",  "Wiring Harness", "harness_chafe",      1.3, 24000, "SUP_ELEC_F",    "INTERMITTENT",  "HARNESS_CHAFE", "REPAIR_HARNESS"),
    ("Undercarriage","Track Group",   "track_wear",         2.8, 20000, "SUP_UC_G",      "TRACK_NOISE",   "UC_WEAR",       "REPLACE_TRACK"),
    ("Structures",  "Boom",           "boom_crack",         3.0, 75000, "SUP_STR_H",     "STRUCT_CRACK",  "FATIGUE_CRACK", "WELD_REPAIR"),
]

# ANCHOR planted defect (#2): fuel injector on LX-950, bad supplier lots built at
# PLT_SOUTH in a build window get infant-mortality hazard (beta<1, small eta).
ANCHOR_MODEL = "LX-950"
ANCHOR_SYSTEM = "Fuel System"
ANCHOR_COMPONENT = "Fuel Injector"
ANCHOR_FACILITY = "PLT_SOUTH"
ANCHOR_SUPPLIER = "SUP_FUELSYS_A"
ANCHOR_BAD_LOTS = ["L-4471", "L-4472", "L-4480"]     # concentrated bad lots
ANCHOR_BUILD_WINDOW = (dt.date(2024, 3, 1), dt.date(2024, 4, 30))
ANCHOR_BETA = 0.7            # infant mortality
ANCHOR_ETA = 3500           # fails far earlier (operating hours)

FAILURE_TEXT = {
    "injector_fouling":   "Engine down on power under load; fault codes for fuel rail pressure. Found fouled injectors, sudden derate reported by operator.",
    "pump_pressure_loss": "Hard starting and low fuel pressure. Fuel transfer pump worn, replaced per procedure.",
    "pump_cavitation":    "Slow hydraulic response, whining pump. Main pump cavitation, replaced pump and filtered system.",
    "seal_leak":          "Hydraulic oil leak at cylinder rod seal. Resealed cylinder, topped hydraulic oil.",
    "bearing_wear":       "Noise from final drive, metal in oil. Final drive bearing wear, rebuilt.",
    "clutch_slip":        "Transmission slipping under load, shift faults. Clutch pack worn, rebuilt transmission.",
    "turbo_failure":      "Low power, blue smoke. Turbocharger failure, replaced turbo and checked oil supply.",
    "coolant_leak":       "Overheating, coolant loss. Water pump seal failure, replaced water pump.",
    "radiator_fouling":   "High engine temperature in dusty conditions. Radiator core fouled, cleaned and inspected.",
    "harness_chafe":      "Intermittent electrical faults. Wiring harness chafe near frame, repaired and secured.",
    "track_wear":         "Track noise and excessive wear. Undercarriage worn beyond spec, replaced track group.",
    "boom_crack":         "Crack observed at boom weld. Structural fatigue crack, weld repair per bulletin.",
}

def _rand_dates(start, end, n):
    span = (end - start).days
    offs = rng.integers(0, max(span, 1), size=n)
    return np.array([start + dt.timedelta(days=int(o)) for o in offs])

def load(conn, df, table):
    df = df.copy()
    df.columns = [c.upper() for c in df.columns]
    # pandas 3.0 defaults to datetime64[s], which write_pandas serializes as NUMBER;
    # coerce all date/timestamp columns to ns (incl. all-null ones) so they map correctly.
    for c in df.columns:
        if str(df[c].dtype).startswith("datetime64") or c.endswith("_DT") or c.endswith("_TS"):
            df[c] = pd.to_datetime(df[c], errors="coerce").astype("datetime64[ns]")
    nrows = len(df)
    conn.write_pandas(
        df, table, database=DB, schema=SCHEMA,
        quote_identifiers=True, auto_create_table=False, overwrite=True, chunk_size=100000, use_logical_type=True,
    )
    print(f"  loaded {nrows:>9,} rows -> {table}")
    return nrows

# --------------------------------------------------------------------------- #
# Master data
# --------------------------------------------------------------------------- #
def gen_masters(n_customers=2500, n_dealers=180):
    # Dealers
    d_region = rng.choice(REGIONS, size=n_dealers, p=REGION_W)
    dealers = pd.DataFrame({
        "dealer_cd": [f"DLR{n:04d}" for n in range(1, n_dealers + 1)],
        "name": [f"Dealer {n}" for n in range(1, n_dealers + 1)],
        "branch": [f"BR{rng.integers(1,9)}" for _ in range(n_dealers)],
        "territory": d_region,
        "region_cd": d_region,
        "country_cd": ["CA" if r.startswith("CA") else "US" for r in d_region],
        "state_cd": [rng.choice(STATES[r]) for r in d_region],
    })
    # Customers
    c_region = rng.choice(REGIONS, size=n_customers, p=REGION_W)
    c_ind = rng.choice(INDUSTRIES, size=n_customers, p=INDUSTRY_W)
    customers = pd.DataFrame({
        "acct_no": [f"ACC{n:06d}" for n in range(1, n_customers + 1)],
        "name": [f"Customer {n}" for n in range(1, n_customers + 1)],
        "industry": c_ind,
        "size_band": rng.choice(["Small", "Medium", "Large", "Major"], size=n_customers, p=[0.4, 0.35, 0.18, 0.07]),
        "region_cd": c_region,
        "country_cd": ["CA" if r.startswith("CA") else "US" for r in c_region],
        "state_cd": [rng.choice(STATES[r]) for r in c_region],
    })
    # Suppliers (from component catalog) + a generic pool
    sup_ids = sorted({c[5] for c in COMPONENTS})
    # Parts master: one part per component x model-family scope (simplify to component-level)
    parts = pd.DataFrame([
        {"part_no": f"{sg[:3].upper()}-{comp.replace(' ','').upper()[:6]}",
         "part_desc": f"{comp} ({sg})", "system_group": sg, "supplier_id": sup, "serviceable_flag": True}
        for sg, comp, _m, _b, _e, sup, *_ in COMPONENTS
    ]).drop_duplicates("part_no")
    return dealers, customers, parts, sup_ids

# --------------------------------------------------------------------------- #
# Machines (registration) + per-machine physics attributes
# --------------------------------------------------------------------------- #
def gen_machines(dealers, customers):
    rows = []
    sn = 1
    for model, family, n, facility, warr in PORTFOLIO:
        for _ in range(n):
            rows.append((f"AX{model.replace('-', '')}{sn:06d}", model, family, facility, warr))
            sn += 1
    M = pd.DataFrame(rows, columns=["machine_sn", "model", "model_family", "build_facility_cd", "warranty_months"])
    nM = len(M)
    M["engine_sn"] = [f"ENG{i:07d}" for i in range(1, nM + 1)]
    M["config_no"] = [f"CFG{rng.integers(1000,9999)}" for _ in range(nM)]
    M["sales_model"] = M["model"] + rng.choice([" ", " LE ", " HD "], size=nM)
    # ownership
    M["customer_acct"] = rng.choice(customers["acct_no"].values, size=nM)
    cust_map = customers.set_index("acct_no")
    M["industry"] = cust_map.loc[M["customer_acct"], "industry"].values
    M["region_cd"] = cust_map.loc[M["customer_acct"], "region_cd"].values
    # dealer in same region where possible
    dlr_by_region = dealers.groupby("region_cd")["dealer_cd"].apply(list).to_dict()
    M["dealer_cd"] = [rng.choice(dlr_by_region.get(r, dealers["dealer_cd"].values)) for r in M["region_cd"]]
    # delivery cohort (#5): spread across build months, slight recency weight
    span = (OBS_DATE - dt.timedelta(days=60) - BUILD_START).days
    u = rng.beta(1.3, 1.0, size=nM)     # skew toward more recent
    M["delivery_dt"] = [BUILD_START + dt.timedelta(days=int(x * span)) for x in u]
    M["build_dt"] = [d - dt.timedelta(days=int(rng.integers(25, 95))) for d in M["delivery_dt"]]
    M["warranty_start_dt"] = M["delivery_dt"]
    M["ext_coverage_flag"] = rng.random(nM) < 0.30
    M["service_agreement_flag"] = rng.random(nM) < 0.42
    M["warranty_months"] = np.where(M["ext_coverage_flag"], 36, M["warranty_months"])
    # duty cycle (#4)
    M["op_hours_per_day"] = [max(1.5, rng.normal(DUTY[i][0], 1.2)) for i in M["industry"]]
    M["hazard_mult"] = [DUTY[i][1] for i in M["industry"]]
    M["load_factor"] = np.clip([rng.normal(0.55 if i != "Quarry&Agg" else 0.72, 0.08) for i in M["industry"]], 0.2, 0.95)
    M["days_in_service"] = [(OBS_DATE - d).days for d in M["delivery_dt"]]
    M["age_hours"] = M["op_hours_per_day"] * M["days_in_service"]
    M["months_in_service"] = M["days_in_service"] / 30.44
    M["op_hours_now"] = M["age_hours"].round(1)
    # anchor eligibility: LX-950 built at PLT_SOUTH inside the bad-lot window
    in_win = M["build_dt"].apply(lambda d: ANCHOR_BUILD_WINDOW[0] <= d <= ANCHOR_BUILD_WINDOW[1])
    M["anchor_eligible"] = (M["model"] == ANCHOR_MODEL) & (M["build_facility_cd"] == ANCHOR_FACILITY) & in_win
    # 75% of eligible carry a bad fuel-injector lot
    M["has_bad_lot"] = M["anchor_eligible"] & (rng.random(nM) < 0.75)
    M["fuel_inj_lot"] = np.where(
        M["has_bad_lot"],
        rng.choice(ANCHOR_BAD_LOTS, size=nM),
        [f"L-{rng.integers(1000, 8000)}" for _ in range(nM)],
    )
    return M

# --------------------------------------------------------------------------- #
# Genealogy (one row per component per machine); plants the anchor lot
# --------------------------------------------------------------------------- #
def gen_genealogy(M):
    nM = len(M)
    frames = []
    for ci, (sg, comp, mode, beta, eta, sup, *_c) in enumerate(COMPONENTS):
        part_no = f"{sg[:3].upper()}-{comp.replace(' ','').upper()[:6]}"
        lot = np.array([f"{sup.split('_')[-1]}-{rng.integers(1000,9999)}" for _ in range(nM)])
        if comp == ANCHOR_COMPONENT:
            lot = M["fuel_inj_lot"].values.copy()
        frames.append(pd.DataFrame({
            "machine_sn": M["machine_sn"].values,
            "engine_sn": M["engine_sn"].values,
            "config_no": M["config_no"].values,
            "part_no": part_no,
            "component_sn": [f"C{ci}{i:07d}" for i in range(nM)],
            "supplier_lot_no": lot,
            "supplier_id": sup,
            "build_facility_cd": M["build_facility_cd"].values,
            "build_dt": M["build_dt"].values,
            "system_group": sg,
        }))
    return pd.concat(frames, ignore_index=True)

# --------------------------------------------------------------------------- #
# Latent Weibull failure sampling (#1) with covariates + planted anchor (#2)
# --------------------------------------------------------------------------- #
def sample_failures(M):
    nM = len(M)
    parts = []
    for (sg, comp, mode, beta, eta, sup, comp3, cause3, corr3) in COMPONENTS:
        is_anchor_comp = (comp == ANCHOR_COMPONENT)
        b = np.full(nM, beta)
        e = eta / M["hazard_mult"].values                     # duty-cycle covariate (#4)
        if is_anchor_comp:
            bad = M["has_bad_lot"].values
            b = np.where(bad, ANCHOR_BETA, b)
            e = np.where(bad, ANCHOR_ETA, e)                  # infant mortality (#2)
        # Weibull TTF in operating hours: eta * (-ln U)^(1/beta)
        u = rng.random(nM)
        ttf = e * (-np.log(1 - u)) ** (1.0 / b)
        observed = ttf < M["age_hours"].values
        idx = np.where(observed)[0]
        if len(idx) == 0:
            continue
        ttf_days = (ttf[idx] / M["op_hours_per_day"].values[idx])
        fail_dt = [M["delivery_dt"].values[i] + dt.timedelta(days=int(t)) for i, t in zip(idx, ttf_days)]
        parts.append(pd.DataFrame({
            "machine_sn": M["machine_sn"].values[idx],
            "system_group": sg, "component": comp, "failure_mode": mode,
            "complaint_cd": comp3, "cause_cd": cause3, "correction_cd": corr3,
            "part_no": f"{sg[:3].upper()}-{comp.replace(' ','').upper()[:6]}",
            "failure_dt": fail_dt,
            "op_hours_at_failure": (ttf[idx]).round(1),
            "is_anchor": is_anchor_comp & M["has_bad_lot"].values[idx],
        }))
    F = pd.concat(parts, ignore_index=True)
    F = F[F["failure_dt"].apply(lambda d: d <= OBS_DATE)].reset_index(drop=True)
    # attach machine attrs
    mattr = M.set_index("machine_sn")
    for col in ["model", "model_family", "dealer_cd", "customer_acct", "delivery_dt",
                "warranty_months", "industry", "region_cd", "op_hours_per_day"]:
        F[col] = mattr.loc[F["machine_sn"], col].values
    F["months_in_service"] = F.apply(
        lambda r: (r["failure_dt"] - r["delivery_dt"]).days / 30.44, axis=1)
    return F

# --------------------------------------------------------------------------- #
# Propagate failures -> field feeds (correlated), plus routine records
# --------------------------------------------------------------------------- #
def gen_dealer_service(F):
    n = len(F)
    return pd.DataFrame({
        "service_record_id": [f"DSR{i:08d}" for i in range(n)],
        "machine_sn": F["machine_sn"].values,
        "dealer_cd": F["dealer_cd"].values,
        "repair_dt": F["failure_dt"].values,
        "op_hours": F["op_hours_at_failure"].values,
        "complaint_cd": F["complaint_cd"].values,
        "cause_cd": F["cause_cd"].values,
        "correction_cd": F["correction_cd"].values,
        "system_group": F["system_group"].values,
        "part_no": F["part_no"].values,
        "labor_hrs": np.clip(rng.normal(6, 2.5, n), 1, 40).round(2),
        "job_story_txt": [FAILURE_TEXT[m] for m in F["failure_mode"].values],
    })

def gen_warranty(F):
    inwarr = F["months_in_service"].values <= F["warranty_months"].values
    W = F[inwarr].reset_index(drop=True)
    n = len(W)
    parts_amt = np.clip(rng.normal(3200, 1500, n), 200, 40000).round(2)
    labor_amt = (W["failure_mode"].map(lambda m: 1).values * np.clip(rng.normal(1400, 700, n), 100, 12000)).round(2)
    return pd.DataFrame({
        "claim_no": [f"WC{i:08d}" for i in range(n)],
        "machine_sn": W["machine_sn"].values,
        "dealer_cd": W["dealer_cd"].values,
        "failure_dt": W["failure_dt"].values,
        "claim_dt": [d + dt.timedelta(days=int(rng.integers(2, 20))) for d in W["failure_dt"].values],
        "part_no": W["part_no"].values,
        "group_no": ["G" + str(abs(hash(s)) % 900 + 100) for s in W["system_group"].values],
        "system_group": W["system_group"].values,
        "labor_hrs": np.clip(rng.normal(6, 2.5, n), 1, 40).round(2),
        "parts_amt": parts_amt,
        "labor_amt": labor_amt,
        "total_claim_amt": (parts_amt + labor_amt).round(2),
        "months_in_service": W["months_in_service"].values.round(2),
        "op_hours_at_failure": W["op_hours_at_failure"].values,
    })

def gen_tech_assist(F):
    sub = F.sample(frac=0.22, random_state=SEED).reset_index(drop=True)
    n = len(sub)
    base = pd.to_datetime(pd.Series(sub["failure_dt"].values))
    open_ts = base - pd.to_timedelta(rng.integers(0, 10, n), unit="D") + pd.to_timedelta(rng.integers(6, 18, n), unit="h")
    close_ts = open_ts + pd.to_timedelta(rng.integers(1, 30, n), unit="D")
    return pd.DataFrame({
        "tac_id": [f"TAC{i:07d}" for i in range(n)],
        "machine_sn": sub["machine_sn"].values,
        "model": sub["model"].values,
        "system_group": sub["system_group"].values,
        "open_ts": open_ts.values,
        "close_ts": close_ts.values,
        "status": rng.choice(["Closed", "Open", "Escalated"], n, p=[0.7, 0.2, 0.1]),
        "problem_txt": [FAILURE_TEXT[m] for m in sub["failure_mode"].values],
        "resolution_txt": ["Followed diagnostic tree; corrective action applied." for _ in range(n)],
    })

def gen_precursor_faults(F):
    """#3 precursor diagnostic-code codes in the weeks before failure (vectorized)."""
    fmi_pool = {"Fuel System": (3, 100, 5), "Hydraulics": (5, 200, 3), "Powertrain": (7, 300, 4),
                "Engine": (2, 110, 4), "Cooling": (4, 111, 3), "Electrical": (8, 400, 2),
                "Undercarriage": (6, 500, 2), "Structures": (9, 600, 1)}
    n = len(F)
    k = rng.integers(1, 5, n)
    idx = np.repeat(np.arange(n), k)
    m = len(idx)
    lead = rng.integers(3, 56, m)
    base = pd.to_datetime(pd.Series(F["failure_dt"].values)).values[idx]
    event_ts = pd.to_datetime(base) - pd.to_timedelta(lead, unit="D") + pd.to_timedelta(rng.integers(0, 23, m), unit="h")
    deliv = pd.to_datetime(pd.Series(F["delivery_dt"].values)).values[idx]
    keep = event_ts.values >= deliv
    sg = F["system_group"].values[idx]
    module_id = np.array([fmi_pool.get(s, (1, 100, 3))[0] for s in sg])
    component_id = np.array([fmi_pool.get(s, (1, 100, 3))[1] for s in sg])
    fmi = np.array([fmi_pool.get(s, (1, 100, 3))[2] for s in sg])
    faults = pd.DataFrame({
        "machine_sn": F["machine_sn"].values[idx],
        "event_ts": event_ts.values,
        "module_id": module_id, "component_id": component_id, "fmi": fmi,
        "spn": component_id * 3 + 190, "j1939_fmi": fmi,
        "system_group": sg,
        "severity_lvl": rng.integers(1, 4, m),
        "occurrence_cnt": rng.integers(1, 20, m),
        "lat": np.round(rng.uniform(25, 49, m), 6),
        "lon": np.round(rng.uniform(-125, -70, m), 6),
    })[keep].reset_index(drop=True)
    faults.insert(0, "fault_id", [f"FLT{i:09d}" for i in range(len(faults))])
    return faults

def gen_fluid_analysis(F):
    """#3 Fluid Analysis wear-metal uptick around engine/fuel/cooling failures + action sample."""
    sub = F[F["system_group"].isin(["Fuel System", "Engine", "Cooling", "Powertrain"])].reset_index(drop=True)
    n = len(sub)
    return pd.DataFrame({
        "sample_id": [f"FLA{i:08d}" for i in range(n)],
        "machine_sn": sub["machine_sn"].values,
        "compartment": rng.choice(["engine", "hydraulic", "transmission"], n, p=[0.6, 0.25, 0.15]),
        "sample_dt": [d - dt.timedelta(days=int(rng.integers(1, 30))) for d in sub["failure_dt"].values],
        "op_hours": (sub["op_hours_at_failure"].values * rng.uniform(0.9, 0.99, n)).round(1),
        "fe_ppm": np.clip(rng.normal(85, 25, n), 5, 300).round(1),
        "cu_ppm": np.clip(rng.normal(30, 12, n), 1, 150).round(1),
        "al_ppm": np.clip(rng.normal(18, 8, n), 1, 120).round(1),
        "si_ppm": np.clip(rng.normal(22, 10, n), 1, 150).round(1),
        "visc_cst": np.clip(rng.normal(14, 2, n), 8, 22).round(2),
        "interp_cd": rng.choice(["action", "monitor"], n, p=[0.65, 0.35]),
    })

def gen_safety(F):
    """#8 rare serious-injury-potential (SIP) on fuel-system sudden shutdown under load."""
    fuel = F[(F["system_group"] == "Fuel System")].reset_index(drop=True)
    hit = fuel.sample(frac=0.05, random_state=SEED).reset_index(drop=True)
    n = len(hit)
    sif = rng.random(n) < 0.35
    return pd.DataFrame({
        "incident_id": [f"SAF{i:06d}" for i in range(n)],
        "machine_sn": hit["machine_sn"].values,
        "part_no": hit["part_no"].values,
        "event_dt": hit["failure_dt"].values,
        "severity": np.where(sif, "High", rng.choice(["Low", "Medium"], n)),
        "injury_flag": rng.random(n) < 0.05,
        "sif_potential_flag": sif,
        "system_group": "Fuel System",
        "description_txt": ["Sudden engine shutdown during high-load operation; operator reported loss of control risk." for _ in range(n)],
    })

def gen_inspection(M, F):
    # PDI at delivery for every machine
    nM = len(M)
    pdi = pd.DataFrame({
        "inspection_id": [f"INSP{i:08d}" for i in range(nM)],
        "machine_sn": M["machine_sn"].values,
        "dealer_cd": M["dealer_cd"].values,
        "inspect_dt": M["delivery_dt"].values,
        "inspect_type": "PDI",
        "item_cd": "PDI_ALL",
        "system_group": "General",
        "condition_rating": rng.choice(["Green", "Yellow"], nM, p=[0.92, 0.08]),
        "finding_txt": "Pre-delivery inspection completed.",
    })
    # TA findings near failures (subset)
    sub = F.sample(frac=0.3, random_state=SEED + 1).reset_index(drop=True)
    n = len(sub)
    ta = pd.DataFrame({
        "inspection_id": [f"INSP9{i:07d}" for i in range(n)],
        "machine_sn": sub["machine_sn"].values,
        "dealer_cd": sub["dealer_cd"].values,
        "inspect_dt": [d - dt.timedelta(days=int(rng.integers(5, 40))) for d in sub["failure_dt"].values],
        "inspect_type": rng.choice(["FIELD_INSP_A", "FIELD_INSP_B"], n),
        "item_cd": sub["system_group"].map(lambda s: s[:3].upper() + "_CHK").values,
        "system_group": sub["system_group"].values,
        "condition_rating": rng.choice(["Yellow", "Red"], n, p=[0.5, 0.5]),
        "finding_txt": ["Condition trending toward action; recommend service." for _ in range(n)],
    })
    return pd.concat([pdi, ta], ignore_index=True)

def gen_voc_cases(M, F):
    """#7 detractors correlated with unresolved fleet issues."""
    fail_by_cust = F.groupby("customer_acct").size()
    custs = M[["customer_acct", "machine_sn", "delivery_dt", "region_cd"]].drop_duplicates("machine_sn")
    voc = custs.sample(frac=0.35, random_state=SEED).reset_index(drop=True)
    n = len(voc)
    fc = voc["customer_acct"].map(fail_by_cust).fillna(0).values
    base_nps = np.clip(rng.normal(35, 25, n) - 12 * np.minimum(fc, 4), -100, 100).round(0)
    voc_df = pd.DataFrame({
        "resp_id": [f"VOC{i:08d}" for i in range(n)],
        "customer_acct": voc["customer_acct"].values,
        "machine_sn": voc["machine_sn"].values,
        "survey_dt": _rand_dates(dt.date(2023, 1, 1), OBS_DATE, n),
        "nps": base_nps,
        "csat": np.clip((base_nps / 20 + 6), 1, 10).round(1),
        "verbatim_txt": np.where(fc > 0,
                                 "Uptime has been a problem this year; support responsive but repeated repairs frustrating.",
                                 "Machine performing well; satisfied with dealer support."),
    })
    # customer cases: baseline + correlated
    sub = F.sample(frac=0.5, random_state=SEED + 2).reset_index(drop=True)
    nc = len(sub)
    base = pd.to_datetime(pd.Series(sub["failure_dt"].values))
    open_ts = base - pd.to_timedelta(rng.integers(0, 5, nc), unit="D") + pd.to_timedelta(rng.integers(6, 18, nc), unit="h")
    close_ts = open_ts + pd.to_timedelta(rng.integers(1, 15, nc), unit="D")
    cases = pd.DataFrame({
        "case_id": [f"CASE{i:08d}" for i in range(nc)],
        "customer_acct": sub["customer_acct"].values,
        "machine_sn": sub["machine_sn"].values,
        "open_ts": open_ts.values,
        "close_ts": close_ts.values,
        "channel": rng.choice(["phone", "web", "dealer", "app"], nc),
        "category": sub["system_group"].values,
        "narrative_txt": [FAILURE_TEXT[m] for m in sub["failure_mode"].values],
    })
    return voc_df, cases

def gen_mes(M, G):
    """Plant MES test per machine; elevated fail for bad-lot fuel injectors."""
    nM = len(M)
    fail_p = np.where(M["has_bad_lot"].values, 0.28, 0.03)
    result = np.where(rng.random(nM) < fail_p, "REWORK", "PASS")
    return pd.DataFrame({
        "mes_id": [f"MES{i:08d}" for i in range(nM)],
        "machine_sn": M["machine_sn"].values,
        "facility_cd": M["build_facility_cd"].values,
        "line": rng.choice(["L1", "L2", "L3"], nM),
        "shift": rng.choice(["A", "B", "C"], nM),
        "station": rng.choice(["FUEL_TEST", "HYD_TEST", "FINAL_QC", "ENGINE_RUN"], nM),
        "test_dt": M["build_dt"].values,
        "result": result,
        "defect_cd": np.where(result == "REWORK",
                              np.where(M["has_bad_lot"].values, "FUEL_INJ_LEAK", "MINOR_ADJ"), None),
        "system_group": np.where(M["has_bad_lot"].values, "Fuel System", "General"),
        "rework_min": np.where(result == "REWORK", np.clip(rng.normal(35, 15, nM), 5, 180).round(1), 0.0),
    })

def gen_supplier(G):
    """Incoming lot inspection (elevated reject for bad lots) + SCAR."""
    lots = G.groupby(["supplier_id", "part_no", "supplier_lot_no"]).size().reset_index(name="qty")
    lots = lots.sample(min(len(lots), 8000), random_state=SEED).reset_index(drop=True)
    n = len(lots)
    is_bad = lots["supplier_lot_no"].isin(ANCHOR_BAD_LOTS).values
    qty_recv = np.clip(rng.normal(120, 40, n), 10, 400).astype(int)
    rej_rate = np.where(is_bad, rng.uniform(0.12, 0.22, n), rng.uniform(0.001, 0.02, n))
    incoming = pd.DataFrame({
        "incoming_id": [f"INC{i:08d}" for i in range(n)],
        "supplier_id": lots["supplier_id"].values,
        "part_no": lots["part_no"].values,
        "supplier_lot_no": lots["supplier_lot_no"].values,
        "recv_dt": _rand_dates(dt.date(2023, 6, 1), dt.date(2025, 6, 1), n),
        "qty_recv": qty_recv,
        "qty_reject": (qty_recv * rej_rate).astype(int),
        "defect_cd": np.where(is_bad, "INJ_SEAT_TOLERANCE", rng.choice(["NONE", "MINOR_DIM", "COSMETIC"], n)),
    })
    # SCAR for bad lots + a few random
    scar_lots = list(ANCHOR_BAD_LOTS)
    scar_rows = []
    for i, lot in enumerate(scar_lots):
        scar_rows.append((f"SCAR{i:04d}", ANCHOR_SUPPLIER, "FUE-FUELIN", lot,
                          dt.date(2025, 6, 15) + dt.timedelta(days=i * 3), None, "Open",
                          "Injector seat tolerance out of spec traced to tooling wear at supplier; lot escaped incoming.",
                          "Containment on suspect lots; tooling replaced; enhanced incoming gauging."))
    scar = pd.DataFrame(scar_rows, columns=[
        "scar_id", "supplier_id", "part_no", "supplier_lot_no", "open_dt", "close_dt",
        "status", "root_cause_txt", "corrective_txt"])
    return incoming, scar

def gen_field_campaign(M):
    """#10 FSC opened after detection for exposed LX-950 serials carrying bad lots."""
    exposed = M[M["has_bad_lot"]]["machine_sn"].values
    n = len(exposed)
    return pd.DataFrame({
        "program_id": "FSC-2025-0417",
        "program_type": "FSC",
        "model": ANCHOR_MODEL,
        "system_group": ANCHOR_SYSTEM,
        "affected_sn": exposed,
        "open_dt": dt.date(2025, 10, 1),
        "completion_dt": [dt.date(2025, 10, 1) + dt.timedelta(days=int(rng.integers(10, 160))) if rng.random() < 0.6 else None for _ in range(n)],
        "issue_txt": "Fuel injector from suspect supplier lots may cause power loss / sudden shutdown under high load on LX-950.",
        "status": rng.choice(["Completed", "Open"], n, p=[0.6, 0.4]),
    })

def gen_docs():
    docs = [
        ("TSB-2025-FUEL-01", "Service Bulletin", "LX-950", "Fuel System", dt.date(2025, 9, 20),
         "Fuel Injector Inspection and Replacement — LX-950 (Suspect Supplier Lots)",
         "This bulletin covers inspection and replacement of fuel injectors on LX-950 Large Excavators built at South Plant, GA from suspect supplier lots. Symptoms include power loss under load, fuel rail pressure fault codes, and potential sudden shutdown. Follow the diagnostic procedure and replace injectors on affected serials."),
        ("SVC-HYD-0042", "Service Procedure", "ALL", "Hydraulics", dt.date(2024, 3, 10),
         "Main Hydraulic Pump Cavitation Diagnosis",
         "Procedure to diagnose main pump cavitation: check tank level, inspect suction hose, verify charge pressure, and analyze Fluid Analysis trends for aeration indicators."),
        ("SA-2025-SAFE-07", "Safety Advisory", "LX-950", "Fuel System", dt.date(2025, 10, 2),
         "Safety Advisory: Sudden Power Loss Under Load",
         "Operators of affected LX-950 machines should be aware of potential sudden power loss under high-load operation. Cease operation and contact your dealer if power loss or derate occurs."),
    ]
    return pd.DataFrame(docs, columns=["doc_id", "doc_type", "model", "system_group", "issue_dt", "title", "body_txt"])

def gen_failure_profile(M, F):
    """Machine-level helper for the SQL periodic generator (degradation coupling)."""
    first_fail = F.groupby("machine_sn")["failure_dt"].min()
    P = M[["machine_sn", "model", "model_family", "build_facility_cd", "delivery_dt",
           "industry", "region_cd", "op_hours_per_day", "load_factor", "days_in_service",
           "op_hours_now", "has_bad_lot"]].copy()
    P["first_failure_dt"] = P["machine_sn"].map(first_fail)
    P["degrade_start_dt"] = P["first_failure_dt"].apply(
        lambda d: (d - dt.timedelta(days=45)) if pd.notnull(d) else None)
    return P

def main(session, machines=None):
    global rng
    rng = np.random.default_rng(SEED)
    PORTFOLIO[:] = list(_BASE_PORTFOLIO)

    if machines:
        # scale portfolio proportionally
        total = sum(p[2] for p in PORTFOLIO)
        factor = machines / total
        for i, p in enumerate(PORTFOLIO):
            PORTFOLIO[i] = (p[0], p[1], max(50, int(p[2] * factor)), p[3], p[4])

    print("Generating masters ...")
    dealers, customers, parts, sup_ids = gen_masters()
    print("Generating machines ...")
    M = gen_machines(dealers, customers)
    print(f"  {len(M):,} machines; anchor bad-lot units: {int(M['has_bad_lot'].sum()):,}")
    print("Building genealogy ...")
    G = gen_genealogy(M)
    print("Sampling latent Weibull failures ...")
    F = sample_failures(M)
    print(f"  {len(F):,} observed failures (anchor: {int(F['is_anchor'].sum()):,})")

    conn = session
    session.sql("USE WAREHOUSE SF_SOLUTIONS_WH").collect()
    print("Loading RAW tables ...")

    # masters
    load(conn, dealers, "RAW_DEALER_MASTER")
    load(conn, customers, "RAW_CUSTOMER_MASTER")
    load(conn, parts, "RAW_PART_MASTER")
    reg = M[["machine_sn", "model", "model_family", "sales_model", "customer_acct",
             "dealer_cd", "delivery_dt", "warranty_start_dt", "warranty_months", "ext_coverage_flag",
             "service_agreement_flag", "build_facility_cd", "region_cd"]]
    load(conn, reg, "RAW_MACHINE_REGISTRATION")
    load(conn, G, "RAW_PRODUCT_GENEALOGY")

    # field feeds (correlated with failures)
    load(conn, gen_dealer_service(F), "RAW_DEALER_SERVICE")
    load(conn, gen_warranty(F), "RAW_WARRANTY_CLAIM")
    load(conn, gen_tech_assist(F), "RAW_TECH_ASSIST_CASE")
    load(conn, gen_inspection(M, F), "RAW_INSPECTION")
    load(conn, gen_fluid_analysis(F), "RAW_FLUID_ANALYSIS")
    load(conn, gen_precursor_faults(F), "RAW_TELEMATICS_FAULT")

    # plant + supplier
    load(conn, gen_mes(M, G), "RAW_MES_QUALITY")
    incoming, scar = gen_supplier(G)
    load(conn, incoming, "RAW_SUPPLIER_INCOMING")
    load(conn, scar, "RAW_SUPPLIER_SCAR")

    # VOC + safety + campaign + docs
    voc, cases = gen_voc_cases(M, F)
    load(conn, voc, "RAW_VOC_SURVEY")
    load(conn, cases, "RAW_CUSTOMER_CASE")
    load(conn, gen_safety(F), "RAW_SAFETY_INCIDENT")
    load(conn, gen_field_campaign(M), "RAW_FIELD_CAMPAIGN")
    load(conn, gen_docs(), "RAW_DOC_TECH")

    # helper table for SQL periodic generation (health + background faults)
    P = gen_failure_profile(M, F)
    P.columns = [c.upper() for c in P.columns]
    for c in P.columns:
        if str(P[c].dtype).startswith("datetime64"):
            P[c] = P[c].astype("datetime64[ns]")
    conn.write_pandas(P, "FAILURE_PROFILE", database=DB, schema=SCHEMA,
                 quote_identifiers=True, auto_create_table=True, overwrite=True, chunk_size=100000, use_logical_type=True)
    print(f"  wrote CQC_RAW.FAILURE_PROFILE ({len(P):,} rows) for periodic SQL gen")

    print("Done. Next: run 015_raw_periodic_gen.sql for telematics health + background faults.")

def run(session):
    """Stored-procedure handler: generate RAW data at the configured machine count."""
    import contextlib
    import io

    rows = session.sql("SELECT VALUE FROM SF_SOLUTIONS.CQC_RAW.CQC_CONFIG WHERE KEY = 'N_MACHINES'").collect()
    machines = int(rows[0][0]) if rows else 40800
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        main(session, machines)
    return buf.getvalue()[-16000:]
$$;

-- -------------------------------------------------------------------------
-- ML module 1: Weibull reliability
-- Source: platform/ml/module1_reliability.py (ported to a stored procedure)
-- -------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CQC_ML.SP_ML_RELIABILITY()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python==1.53.0', 'snowflake-ml-python==1.46.0', 'pandas==2.3.3', 'numpy', 'scipy==1.15.3', 'scikit-learn==1.7.2', 'xgboost==3.2.0', 'lifelines==0.30.0')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
#!/usr/bin/env python3
"""
CQC Module 1 — Reliability & warranty projection (survival analysis).

Fits Weibull(beta, eta) with RIGHT-CENSORING per (model x system_group x failure_mode)
using lifelines. In-service units that have NOT failed a given mode are censored at
their current operating hours. Produces:
  CQC_ML.RELIABILITY_PARAMS   — fitted beta/eta, MTBF, infant-mortality flag per group
  CQC_ML.MTBF_ESTIMATES       — MTBF per (model, system_group)
  CQC_ML.WARRANTY_PROJECTION  — Nevada-style expected failures/cost next 12 months by cohort

Validation: fitted beta should recover the planted Weibull shapes (doc 4 §6.1).

Run: SNOWFLAKE_CONNECTION_NAME=my_snowflake .venv/bin/python platform/ml/module1_reliability.py
"""
import sys, os

import numpy as np
import pandas as pd
from scipy.special import gamma as gamma_fn
from lifelines import WeibullFitter

MIN_EVENTS = 15          # minimum failures to attempt a fit
HORIZON_DAYS = 365

def main(session):
    session.sql("USE DATABASE SF_SOLUTIONS").collect()
    session.sql("USE WAREHOUSE SF_SOLUTIONS_WH").collect()

    # first failure per (machine, system_group, failure_mode) from service repairs
    fails = session.sql("""
        SELECT model, system_group_cd, failure_mode_cd, machine_key, MIN(op_hours) AS op_hours
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_SERVICE_REPAIR
        WHERE op_hours > 0 AND failure_mode_cd IS NOT NULL
        GROUP BY 1,2,3,4
    """).to_pandas()
    machines = session.sql("""
        SELECT machine_key, model, op_hours_now, op_hours_per_day, build_month, product_family
        FROM SF_SOLUTIONS.CQC_FEATURE_STORE.FEAT_MACHINE
    """).to_pandas()
    # avg cost per (model, system_group) for projection
    cost = session.sql("""
        SELECT model, system_group_cd, AVG(total_claim_amt) AS avg_cost
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_WARRANTY_CLAIM WHERE total_claim_amt > 0
        GROUP BY 1,2
    """).to_pandas()
    cost_map = {(r.MODEL, r.SYSTEM_GROUP_CD): r.AVG_COST for r in cost.itertuples()}

    mach_by_model = {m: g for m, g in machines.groupby("MODEL")}

    params = []
    for (model, sg, fm), grp in fails.groupby(["MODEL", "SYSTEM_GROUP_CD", "FAILURE_MODE_CD"]):
        if len(grp) < MIN_EVENTS:
            continue
        mm = mach_by_model.get(model)
        if mm is None:
            continue
        failed_keys = set(grp["MACHINE_KEY"])
        # event rows: failures at their operating hours; censored rows: non-failed machines at op_hours_now
        dur_e = grp["OP_HOURS"].values.astype(float)
        cens = mm[~mm["MACHINE_KEY"].isin(failed_keys)]
        dur_c = cens["OP_HOURS_NOW"].values.astype(float)
        durations = np.concatenate([dur_e, dur_c])
        observed = np.concatenate([np.ones(len(dur_e)), np.zeros(len(dur_c))])
        keep = durations > 0
        durations, observed = durations[keep], observed[keep]
        if observed.sum() < MIN_EVENTS:
            continue
        try:
            wf = WeibullFitter().fit(durations, observed)
            beta = float(wf.rho_)          # shape
            eta = float(wf.lambda_)        # scale (characteristic life)
        except Exception as e:
            print(f"  fit failed {model}/{sg}/{fm}: {e}")
            continue
        mtbf = eta * gamma_fn(1 + 1 / beta)
        params.append({
            "MODEL": model, "SYSTEM_GROUP_CD": sg, "FAILURE_MODE_CD": fm,
            "N_EVENTS": int(observed.sum()), "N_CENSORED": int((observed == 0).sum()),
            "BETA": round(beta, 4), "ETA": round(eta, 1),
            "MTBF_HOURS": round(mtbf, 1),
            "INFANT_MORTALITY_FLAG": beta < 1.0,
        })
    params_df = pd.DataFrame(params)
    print(f"Fitted {len(params_df)} Weibull groups")

    # --- CQC_ML.RELIABILITY_PARAMS ---
    session.write_pandas(params_df, "RELIABILITY_PARAMS", database="SF_SOLUTIONS",
                         schema="CQC_ML", auto_create_table=True, overwrite=True,
                         quote_identifiers=False, use_logical_type=True)

    # --- CQC_ML.MTBF_ESTIMATES (dominant mode per model x system_group) ---
    mtbf_df = (params_df.sort_values("N_EVENTS", ascending=False)
               .groupby(["MODEL", "SYSTEM_GROUP_CD"], as_index=False)
               .agg(MTBF_HOURS=("MTBF_HOURS", "first"), BETA=("BETA", "first"),
                    ETA=("ETA", "first"), N_EVENTS=("N_EVENTS", "sum")))
    session.write_pandas(mtbf_df, "MTBF_ESTIMATES", database="SF_SOLUTIONS",
                         schema="CQC_ML", auto_create_table=True, overwrite=True,
                         quote_identifiers=False, use_logical_type=True)

    # --- CQC_ML.WARRANTY_PROJECTION (Nevada): expected failures next 12 mo by cohort ---
    dominant = (params_df.sort_values("N_EVENTS", ascending=False)
                .drop_duplicates(["MODEL", "SYSTEM_GROUP_CD"]))
    proj_rows = []
    for r in dominant.itertuples():
        mm = mach_by_model.get(r.MODEL)
        if mm is None:
            continue
        t0 = mm["OP_HOURS_NOW"].values.astype(float)
        t1 = t0 + mm["OP_HOURS_PER_DAY"].values.astype(float) * HORIZON_DAYS
        S0 = np.exp(-((np.maximum(t0, 1e-6) / r.ETA) ** r.BETA))
        S1 = np.exp(-((t1 / r.ETA) ** r.BETA))
        p_fail = np.clip((S0 - S1) / np.maximum(S0, 1e-9), 0, 1)
        # by build cohort
        tmp = pd.DataFrame({"build_month": mm["BUILD_MONTH"].values, "p": p_fail})
        agg = tmp.groupby("build_month").agg(units=("p", "size"), exp_fail=("p", "sum")).reset_index()
        avg_cost = cost_map.get((r.MODEL, r.SYSTEM_GROUP_CD), 4500.0) or 4500.0
        for a in agg.itertuples():
            proj_rows.append({
                "MODEL": r.MODEL, "SYSTEM_GROUP_CD": r.SYSTEM_GROUP_CD,
                "BUILD_MONTH": a.build_month, "IN_SERVICE_UNITS": int(a.units),
                "EXPECTED_FAILURES_12MO": round(float(a.exp_fail), 2),
                "EXPECTED_COST_12MO": round(float(a.exp_fail) * float(avg_cost), 0),
            })
    proj_df = pd.DataFrame(proj_rows)
    session.write_pandas(proj_df, "WARRANTY_PROJECTION", database="SF_SOLUTIONS",
                         schema="CQC_ML", auto_create_table=True, overwrite=True,
                         quote_identifiers=False, use_logical_type=True)
    print(f"WARRANTY_PROJECTION rows: {len(proj_df)}")

    # --- Validation: fitted beta for the anchor fuel modes on LX-950 ---
    print("\n=== VALIDATION: fitted beta vs planted (anchor context) ===")
    val = params_df[(params_df.SYSTEM_GROUP_CD == "ENGINE_FUEL")][
        ["MODEL", "FAILURE_MODE_CD", "N_EVENTS", "BETA", "ETA", "MTBF_HOURS", "INFANT_MORTALITY_FLAG"]]
    print(val.sort_values("N_EVENTS", ascending=False).head(12).to_string(index=False))
    print("\nPlanted truth: injector beta=1.8 eta=24000; pump beta=2.0 eta=32000; "
          "anchor bad-lot injector beta=0.7 eta=3500 (infant mortality).")

def run(session):
    """Stored-procedure handler: run the module and return its validation output."""
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        main(session)
    return buf.getvalue()[-16000:]
$$;

-- -------------------------------------------------------------------------
-- ML module 2: emerging-issue detection
-- Source: platform/ml/module2_emerging.py (ported to a stored procedure)
-- -------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CQC_ML.SP_ML_EMERGING()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python==1.53.0', 'snowflake-ml-python==1.46.0', 'pandas==2.3.3', 'numpy', 'scipy==1.15.3', 'scikit-learn==1.7.2', 'xgboost==3.2.0', 'lifelines==0.30.0')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
#!/usr/bin/env python3
"""
CQC Module 2 — Emerging-issue detection (SPC + change-point + anomaly).

Monthly failure-rate series per (model x system_group). Computes:
  - EWMA control chart (lambda=0.3)
  - tabular CUSUM (proper iterative, k=0.5 sigma slack, h=4 sigma alarm)
  - change-point month (first sustained CUSUM alarm)
  - IsolationForest anomaly flag on [rate, mom_change, z] month features
Writes CQC_ML.EMERGING_ISSUE_SIGNALS. A companion SQL creates SP_DETECT_EMERGING_ISSUES.

Validation (doc 4 §6.2): detector fires on the planted LX-950 ENGINE_FUEL ramp
in 2024 BEFORE it dominates raw counts.

Run: SNOWFLAKE_CONNECTION_NAME=my_snowflake .venv/bin/python platform/ml/module2_emerging.py
"""
import sys, os
import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest

LAMBDA = 0.3          # EWMA weight
K = 0.5               # CUSUM slack (in sigma)
H = 4.0               # CUSUM alarm threshold (in sigma)

def main(session):
    for s in ("USE WAREHOUSE SF_SOLUTIONS_WH", "USE DATABASE SF_SOLUTIONS", "USE SCHEMA CQC_ML"):
        session.sql(s).collect()

    # monthly severe-event counts + active fleet -> rate per (model, system_group)
    df = session.sql("""
        WITH ev AS (
            SELECT model, system_group_cd, event_month, COUNT(*) n
            FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT
            WHERE source_system IN ('WARRANTY','DEALER_SERVICE') AND event_month >= '2020-01-01'
            GROUP BY 1,2,3),
        fleet AS (
            SELECT model, DATE_TRUNC('month', d.date_day) event_month, COUNT(DISTINCT m.machine_key) active
            FROM SF_SOLUTIONS.CQC_ATOMIC.DIM_MACHINE m
            JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_DATE d
              ON d.date_day = LAST_DAY(d.date_day) AND m.delivery_dt <= d.date_day
            WHERE d.date_day >= '2020-01-01' GROUP BY 1,2)
        SELECT ev.model, ev.system_group_cd, ev.event_month, ev.n,
               COALESCE(f.active, 0) active,
               DIV0(ev.n, NULLIF(f.active,0)) * 1000 rate_per_1k
        FROM ev LEFT JOIN fleet f ON f.model=ev.model AND f.event_month=ev.event_month
        ORDER BY 1,2,3
    """).to_pandas()

    out = []
    for (model, sg), g in df.groupby(["MODEL", "SYSTEM_GROUP_CD"]):
        g = g.sort_values("EVENT_MONTH").reset_index(drop=True)
        if len(g) < 12:
            continue
        r = g["RATE_PER_1K"].values.astype(float)
        # baseline from first 12 months (pre-ramp)
        base_mu, base_sd = r[:12].mean(), r[:12].std() or 1e-6
        z = (r - base_mu) / base_sd
        # EWMA
        ewma = np.zeros_like(r); ewma[0] = r[0]
        for i in range(1, len(r)):
            ewma[i] = LAMBDA * r[i] + (1 - LAMBDA) * ewma[i - 1]
        # tabular CUSUM (upper)
        cpos = np.zeros_like(r); alarm = np.zeros(len(r), dtype=int)
        for i in range(1, len(r)):
            cpos[i] = max(0.0, cpos[i - 1] + (z[i] - K))
            alarm[i] = 1 if cpos[i] > H else 0
        change_idx = int(np.argmax(alarm)) if alarm.any() else -1
        change_month = g["EVENT_MONTH"].iloc[change_idx] if change_idx >= 0 else None
        # IsolationForest anomaly on month features
        mom = np.diff(r, prepend=r[0])
        feats = np.column_stack([r, mom, z])
        try:
            iso = IsolationForest(contamination=0.1, random_state=42).fit(feats)
            anomaly = (iso.predict(feats) == -1).astype(int)
        except Exception:
            anomaly = np.zeros(len(r), dtype=int)
        for i in range(len(g)):
            out.append({
                "MODEL": model, "SYSTEM_GROUP_CD": sg,
                "EVENT_MONTH": g["EVENT_MONTH"].iloc[i], "N": int(g["N"].iloc[i]),
                "ACTIVE_FLEET": int(g["ACTIVE"].iloc[i]),
                "RATE_PER_1K": round(float(r[i]), 3), "BASELINE_RATE": round(float(base_mu), 3),
                "Z": round(float(z[i]), 3), "EWMA": round(float(ewma[i]), 3),
                "CUSUM": round(float(cpos[i]), 3), "ALARM": int(alarm[i]),
                "IS_CHANGEPOINT": bool(change_idx == i),
                "ANOMALY_FLAG": int(anomaly[i]),
            })
    res = pd.DataFrame(out)
    session.write_pandas(res, "EMERGING_ISSUE_SIGNALS", database="SF_SOLUTIONS", schema="CQC_ML",
                         auto_create_table=True, overwrite=True, quote_identifiers=False, use_logical_type=True)
    print(f"EMERGING_ISSUE_SIGNALS rows: {len(res):,}")

    # validation: anchor LX-950 ENGINE_FUEL change-point
    anchor = res[(res.MODEL == "LX-950") & (res.SYSTEM_GROUP_CD == "ENGINE_FUEL")]
    cp = anchor[anchor.IS_CHANGEPOINT]
    print("\n=== VALIDATION: LX-950 ENGINE_FUEL emerging signal ===")
    if len(cp):
        print(f"change-point month: {cp.EVENT_MONTH.iloc[0]}  (first CUSUM alarm)")
    alarms = anchor[anchor.ALARM == 1]
    print(f"alarm months: {len(alarms)}; first alarm: {alarms.EVENT_MONTH.min() if len(alarms) else 'none'}")
    print(f"total (model,system_group) series with >=1 alarm: {res[res.ALARM==1].groupby(['MODEL','SYSTEM_GROUP_CD']).ngroups}")

def run(session):
    """Stored-procedure handler: run the module and return its validation output."""
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        main(session)
    return buf.getvalue()[-16000:]
$$;

-- -------------------------------------------------------------------------
-- ML module 3: failure-risk model
-- Source: platform/ml/module3_failure_risk.py (ported to a stored procedure)
-- -------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CQC_ML.SP_ML_FAILURE_RISK()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python==1.53.0', 'snowflake-ml-python==1.46.0', 'pandas==2.3.3', 'numpy', 'scipy==1.15.3', 'scikit-learn==1.7.2', 'xgboost==3.2.0', 'lifelines==0.30.0')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
#!/usr/bin/env python3
"""
CQC Module 3 — Predictive failure / RUL (gradient-boosted hazard).

Point-in-time supervised setup to avoid leakage:
  - features computed AS-OF a cut date (OBS - 90d), from telematics/Fluid Analysis/repairs before cut
  - label = machine had a severe failure (warranty claim or major Dealer Service Records repair) in the
    forward 90-day window (cut, OBS]
Trains XGBoost, evaluates AUC + whether suspect-lot machines rank high, registers
FAILURE_RISK_MODEL in the Model Registry, and scores the CURRENT fleet ->
CQC_ML.MACHINE_FAILURE_RISK (P(failure <= 90 days)).

has_suspect_lot is EXCLUDED from features (it is what we detect from telematics).

Run: SNOWFLAKE_CONNECTION_NAME=my_snowflake .venv/bin/python platform/ml/module3_failure_risk.py
"""
import sys, os

import numpy as np
import pandas as pd
from xgboost import XGBClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, average_precision_score

OBS = "2026-07-15"
CUT = "2026-04-16"        # OBS - 90d
NUM_FEATURES = [
    "MONTHS_IN_SERVICE","OP_HOURS_NOW","OP_HOURS_PER_DAY","AVG_LOAD_FACTOR","AVG_IDLE_PCT",
    "T90_AVG_TEMP","T90_MAX_TEMP","T90_DERATE_SUM","TEMP_TREND_90D",
    "F90_FAULT_CNT","F90_HIGHSEV_CNT","F90_FUEL_FAULT_CNT",
    "FLUID_FE_PPM","FLUID_CU_PPM","FLUID_AL_PPM","FLUID_SI_PPM","FLUID_ACTION_CNT",
    "PRIOR_REPAIR_CNT","PRIOR_FUEL_REPAIR_CNT","DAYS_SINCE_LAST_REPAIR",
]
CATEGORICAL_FEATURES = ["PRODUCT_FAMILY","END_MARKET_CD"]

def feat_sql(as_of: str) -> str:
    """Machine features as-of a date (telematics/Fluid Analysis/repairs strictly before as_of)."""
    return f"""
    WITH obs AS (SELECT DATE '{as_of}' AS d),
    h_all AS (
        SELECT machine_sn, MAX(op_hours) op_hours_now, AVG(load_factor) avg_load_factor,
               AVG(idle_pct) avg_idle_pct
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_HEALTH_DAILY, obs
        WHERE event_date <= obs.d GROUP BY 1),
    h90 AS (
        SELECT machine_sn, AVG(avg_engine_temp) t90_avg_temp, MAX(peak_engine_temp) t90_max_temp,
               SUM(derate_events) t90_derate_sum
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_HEALTH_DAILY, obs
        WHERE event_date BETWEEN DATEADD('day',-90,obs.d) AND obs.d GROUP BY 1),
    hprior AS (
        SELECT machine_sn, AVG(avg_engine_temp) tprior
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_HEALTH_DAILY, obs
        WHERE event_date BETWEEN DATEADD('day',-180,obs.d) AND DATEADD('day',-90,obs.d) GROUP BY 1),
    flt90 AS (
        SELECT machine_sn, COUNT(*) f90_fault_cnt, COUNT_IF(severity_cd='HIGH') f90_highsev_cnt,
               COUNT_IF(system_group_cd='ENGINE_FUEL') f90_fuel_fault_cnt
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_TELEMATICS_FAULT, obs
        WHERE event_date BETWEEN DATEADD('day',-90,obs.d) AND obs.d GROUP BY 1),
    fluid AS (
        SELECT machine_sn, MAX_BY(fe_ppm,event_date) fluid_fe_ppm, MAX_BY(cu_ppm,event_date) fluid_cu_ppm,
               MAX_BY(al_ppm,event_date) fluid_al_ppm, MAX_BY(si_ppm,event_date) fluid_si_ppm,
               COUNT_IF(interp_cd='action') fluid_action_cnt
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_FLUID_SAMPLE, obs WHERE event_date <= obs.d GROUP BY 1),
    rep AS (
        SELECT machine_sn, COUNT(*) prior_repair_cnt, COUNT_IF(system_group_cd='ENGINE_FUEL') prior_fuel_repair_cnt,
               DATEDIFF('day', MAX(event_date), (SELECT d FROM obs)) days_since_last_repair
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_SERVICE_REPAIR, obs WHERE event_date <= obs.d GROUP BY 1),
    suspect AS (SELECT DISTINCT machine_key, TRUE has_suspect_lot FROM SF_SOLUTIONS.CQC_ATOMIC.BRIDGE_LOT_MACHINE WHERE is_suspect)
    SELECT m.machine_key, m.product_family, c.end_market_cd,
        DATEDIFF('day', m.delivery_dt, (SELECT d FROM obs))/30.44 months_in_service,
        COALESCE(h.op_hours_now,0) op_hours_now,
        DIV0(COALESCE(h.op_hours_now,0), GREATEST(DATEDIFF('day', m.delivery_dt,(SELECT d FROM obs)),1)) op_hours_per_day,
        h.avg_load_factor, h.avg_idle_pct, h90.t90_avg_temp, h90.t90_max_temp, h90.t90_derate_sum,
        (h90.t90_avg_temp - hprior.tprior) temp_trend_90d,
        COALESCE(flt90.f90_fault_cnt,0) f90_fault_cnt, COALESCE(flt90.f90_highsev_cnt,0) f90_highsev_cnt,
        COALESCE(flt90.f90_fuel_fault_cnt,0) f90_fuel_fault_cnt,
        fluid.fluid_fe_ppm, fluid.fluid_cu_ppm, fluid.fluid_al_ppm, fluid.fluid_si_ppm, COALESCE(fluid.fluid_action_cnt,0) fluid_action_cnt,
        COALESCE(rep.prior_repair_cnt,0) prior_repair_cnt, COALESCE(rep.prior_fuel_repair_cnt,0) prior_fuel_repair_cnt,
        rep.days_since_last_repair,
        COALESCE(s.has_suspect_lot,FALSE) has_suspect_lot
    FROM SF_SOLUTIONS.CQC_ATOMIC.DIM_MACHINE m
    LEFT JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_CUSTOMER c ON c.customer_acct=m.customer_acct
    LEFT JOIN h_all h ON h.machine_sn=m.machine_sn
    LEFT JOIN h90 ON h90.machine_sn=m.machine_sn
    LEFT JOIN hprior ON hprior.machine_sn=m.machine_sn
    LEFT JOIN flt90 ON flt90.machine_sn=m.machine_sn
    LEFT JOIN fluid ON fluid.machine_sn=m.machine_sn
    LEFT JOIN rep ON rep.machine_sn=m.machine_sn
    LEFT JOIN suspect s ON s.machine_key=m.machine_key
    WHERE m.delivery_dt <= DATEADD('day',-30,(SELECT d FROM obs))
    """

def prep(df):
    X = df[NUM_FEATURES].astype(float).fillna(0.0)
    for c in CATEGORICAL_FEATURES:
        d = pd.get_dummies(df[c].fillna("NA"), prefix=c)
        X = pd.concat([X, d], axis=1)
    import re
    X.columns = [re.sub(r"[^0-9A-Za-z_]", "_", str(c)) for c in X.columns]
    return X

def main(session):
    session.sql("USE WAREHOUSE SF_SOLUTIONS_WH").collect()
    session.sql("USE DATABASE SF_SOLUTIONS").collect()
    session.sql("USE SCHEMA CQC_ML").collect()

    # training frame: features as-of CUT, label = severe failure in (CUT, OBS]
    train = session.sql(feat_sql(CUT)).to_pandas()
    label = session.sql(f"""
        SELECT DISTINCT machine_key, 1 AS y FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT
        WHERE event_date > DATE '{CUT}' AND event_date <= DATE '{OBS}'
          AND source_system IN ('WARRANTY','DEALER_SERVICE')
          AND system_group_cd IN ('ENGINE_FUEL','ENGINE','HYDRAULICS','POWERTRAIN')
    """).to_pandas()
    train = train.merge(label, on="MACHINE_KEY", how="left")
    train["Y"] = train["Y"].fillna(0).astype(int)
    print(f"Training rows: {len(train):,}  positive rate: {train['Y'].mean():.3f}")

    X = prep(train); y = train["Y"].values
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.25, random_state=42, stratify=y)
    clf = XGBClassifier(n_estimators=300, max_depth=5, learning_rate=0.06,
                        subsample=0.9, colsample_bytree=0.8, eval_metric="logloss",
                        scale_pos_weight=(y == 0).sum() / max((y == 1).sum(), 1))
    clf.fit(Xtr, ytr)
    proba = clf.predict_proba(Xte)[:, 1]
    auc = roc_auc_score(yte, proba); ap = average_precision_score(yte, proba)
    print(f"Test AUC={auc:.3f}  PR-AUC={ap:.3f}")

    # validation: do suspect-lot machines rank higher?
    train["risk"] = clf.predict_proba(X)[:, 1]
    sl = train.groupby("HAS_SUSPECT_LOT")["risk"].mean()
    print(f"Mean risk — suspect-lot: {sl.get(True, float('nan')):.3f}  others: {sl.get(False, float('nan')):.3f}")

    # score CURRENT fleet (as-of OBS)
    score = session.sql(feat_sql(OBS)).to_pandas()
    Xs = prep(score).reindex(columns=X.columns, fill_value=0)
    score["FAILURE_RISK_90D"] = clf.predict_proba(Xs)[:, 1]
    out = score[["MACHINE_KEY", "FAILURE_RISK_90D"]].copy()
    # quantile-based watchlist bands: top 8% HIGH, next 22% MEDIUM, rest LOW
    q92, q70 = out["FAILURE_RISK_90D"].quantile([0.92, 0.70])
    out["RISK_BAND"] = np.where(out["FAILURE_RISK_90D"] >= q92, "HIGH",
                        np.where(out["FAILURE_RISK_90D"] >= q70, "MEDIUM", "LOW"))
    out["SCORED_AT"] = OBS
    out["FAILURE_RISK_90D"] = out["FAILURE_RISK_90D"].round(4)
    session.write_pandas(out, "MACHINE_FAILURE_RISK", database="SF_SOLUTIONS", schema="CQC_ML",
                         auto_create_table=True, overwrite=True, quote_identifiers=False, use_logical_type=True)
    print(f"Scored fleet -> CQC_ML.MACHINE_FAILURE_RISK ({len(out):,}); HIGH band: {(out.RISK_BAND=='HIGH').sum():,}")

    # register in Model Registry (non-fatal if conda resolution differs)
    try:
        from snowflake.ml.registry import Registry
        reg = Registry(session, database_name="SF_SOLUTIONS", schema_name="CQC_ML")
        mv = reg.log_model(clf, model_name="FAILURE_RISK_MODEL", version_name="V1",
                           sample_input_data=Xtr.head(50),
                           comment=f"XGBoost 90-day failure risk; test AUC={auc:.3f}",
                           conda_dependencies=["xgboost"], target_platforms=["WAREHOUSE"])
        print(f"Registered FAILURE_RISK_MODEL {mv.version_name}")
    except Exception as e:
        print(f"[registry] skipped/failed (non-fatal): {e}")

def run(session):
    """Stored-procedure handler: run the module and return its validation output."""
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        main(session)
    return buf.getvalue()[-16000:]
$$;

-- -------------------------------------------------------------------------
-- ML module 4: issue clustering
-- Source: platform/ml/module4_issue_clustering.py (ported to a stored procedure)
-- -------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CQC_ML.SP_ML_ISSUE_CLUSTERING()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python==1.53.0', 'snowflake-ml-python==1.46.0', 'pandas==2.3.3', 'numpy', 'scipy==1.15.3', 'scikit-learn==1.7.2', 'xgboost==3.2.0', 'lifelines==0.30.0')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
#!/usr/bin/env python3
"""
CQC Module 4 — Signal fusion into ISSUES (embeddings + clustering + brief).

Collapses ~250k quality events into a governable set of ISSUES at
(model x system_group x failure_mode) grain. Uses Cortex AI_EMBED on a
representative failure narrative per issue, HDBSCAN (sklearn) to group
semantically-similar issue types, and AI_COMPLETE to write a crisp brief.

Outputs:
  CQC_ML.EVENT_EMBEDDINGS  — issue_id + representative-text embedding (VECTOR pulled as array)
  CQC_ML.ISSUE_CLUSTERS    — the ISSUE registry: issue_id, identity, dimension, base metrics,
                         cluster_id, brief (feeds CQC_ANALYTICS.ISSUE assembly)

Run: SNOWFLAKE_CONNECTION_NAME=my_snowflake .venv/bin/python platform/ml/module4_issue_clustering.py
"""
import sys, os
import numpy as np
import pandas as pd
from sklearn.cluster import HDBSCAN

MIN_EVENTS = 40          # governable-issue threshold
EMBED_MODEL = "snowflake-arctic-embed-m-v1.5"
BRIEF_MODEL = "llama3.1-8b"

def main(session):
    for s in ("USE WAREHOUSE SF_SOLUTIONS_WH", "USE DATABASE SF_SOLUTIONS", "USE SCHEMA CQC_ML"):
        session.sql(s).collect()

    # candidate issues at (model, system_group, failure_mode) grain + representative text
    # + Cortex embedding + AI brief, all computed server-side.
    sql = f"""
    WITH base AS (
        SELECT e.model, e.system_group_cd, e.failure_mode_cd,
               COUNT(*) events, COUNT(DISTINCT e.machine_key) fleet,
               MIN(e.event_date) first_seen, MAX(e.event_date) last_seen,
               MODE(e.quality_dimension_cd) dimension,
               SUM(IFF(e.quality_dimension_cd='SAFETY',1,0)) safety_events,
               SUM(COALESCE(e.repair_cost_usd,0)) total_cost
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT e
        WHERE e.failure_mode_cd IS NOT NULL
        GROUP BY 1,2,3
        HAVING COUNT(*) >= {MIN_EVENTS}
    ),
    story AS (   -- one representative technician narrative per issue
        SELECT model, system_group_cd, failure_mode_cd,
               ANY_VALUE(job_story_txt) rep_story
        FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_SERVICE_REPAIR
        WHERE job_story_txt IS NOT NULL
        GROUP BY 1,2,3
    )
    SELECT b.*,
        MD5(b.model || '|' || b.system_group_cd || '|' || b.failure_mode_cd) AS issue_id,
        sg.system_group_name, fm.failure_mode_name,
        b.model || ' ' || sg.system_group_name || ' - ' || fm.failure_mode_name AS rep_text,
        COALESCE(s.rep_story, fm.failure_mode_name) AS rep_story
    FROM base b
    LEFT JOIN story s USING (model, system_group_cd, failure_mode_cd)
    LEFT JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_SYSTEM_GROUP sg ON sg.system_group_cd=b.system_group_cd
    LEFT JOIN SF_SOLUTIONS.CQC_ATOMIC.DIM_FAILURE_MODE fm ON fm.failure_mode_cd=b.failure_mode_cd
    """
    iss = session.sql(sql).to_pandas()
    print(f"Candidate issues: {len(iss)}")

    # embeddings via Cortex AI_EMBED (batch over the small issue set)
    session.sql("CREATE OR REPLACE TEMP TABLE _issue_stage AS " + sql).collect()
    emb = session.sql(f"""
        SELECT issue_id,
               AI_EMBED('{EMBED_MODEL}', rep_text || '. ' || rep_story)::ARRAY AS emb
        FROM _issue_stage
    """).to_pandas()
    emb["EMB"] = emb["EMB"].apply(lambda a: np.array(eval(a) if isinstance(a, str) else a, dtype=float))
    E = np.vstack(emb["EMB"].values)
    print(f"Embeddings: {E.shape}")

    # HDBSCAN over issue embeddings
    labels = HDBSCAN(min_cluster_size=2, metric="euclidean").fit_predict(E)
    emb["CLUSTER_ID"] = labels
    print(f"Clusters (excl noise): {len(set(labels)) - (1 if -1 in labels else 0)}; noise: {(labels==-1).sum()}")

    # AI brief per issue (short title + one-line description)
    briefs = session.sql(f"""
        SELECT issue_id,
          AI_COMPLETE('{BRIEF_MODEL}',
            'In one sentence (max 20 words), summarize this equipment quality issue for an executive: '
            || rep_text || '. Example narrative: ' || rep_story) AS brief
        FROM _issue_stage
    """).to_pandas()

    reg = (iss.merge(emb[["ISSUE_ID", "CLUSTER_ID"]], on="ISSUE_ID")
              .merge(briefs, on="ISSUE_ID", how="left"))
    reg["BRIEF"] = reg["BRIEF"].fillna("").str.strip().str.slice(0, 400)
    keep = ["ISSUE_ID", "MODEL", "SYSTEM_GROUP_CD", "SYSTEM_GROUP_NAME", "FAILURE_MODE_CD",
            "FAILURE_MODE_NAME", "DIMENSION", "EVENTS", "FLEET", "SAFETY_EVENTS",
            "TOTAL_COST", "FIRST_SEEN", "LAST_SEEN", "CLUSTER_ID", "BRIEF"]
    reg = reg[keep]
    session.write_pandas(reg, "ISSUE_CLUSTERS", database="SF_SOLUTIONS", schema="CQC_ML",
                         auto_create_table=True, overwrite=True, quote_identifiers=False, use_logical_type=True)

    emb_out = emb[["ISSUE_ID", "CLUSTER_ID"]].copy()
    emb_out["EMBEDDING"] = emb["EMB"].apply(lambda a: [round(float(x), 5) for x in a])
    session.write_pandas(emb_out, "EVENT_EMBEDDINGS", database="SF_SOLUTIONS", schema="CQC_ML",
                         auto_create_table=True, overwrite=True, quote_identifiers=False, use_logical_type=True)
    print(f"ISSUE_CLUSTERS: {len(reg)} issues written")

    # validation: the anchor issue + its brief
    anchor = reg[(reg.MODEL == "LX-950") & (reg.SYSTEM_GROUP_CD == "ENGINE_FUEL")]
    print("\n=== VALIDATION: LX-950 ENGINE_FUEL issues ===")
    for r in anchor.itertuples():
        print(f"  {r.FAILURE_MODE_CD}: events={r.EVENTS} fleet={r.FLEET} dim={r.DIMENSION}")
        print(f"    brief: {r.BRIEF[:160]}")

def run(session):
    """Stored-procedure handler: run the module and return its validation output."""
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        main(session)
    return buf.getvalue()[-16000:]
$$;

-- -------------------------------------------------------------------------
-- ML module 7: Monte-Carlo exposure
-- Source: platform/ml/module7_exposure.py (ported to a stored procedure)
-- -------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CQC_ML.SP_ML_EXPOSURE()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python==1.53.0', 'snowflake-ml-python==1.46.0', 'pandas==2.3.3', 'numpy', 'scipy==1.15.3', 'scikit-learn==1.7.2', 'xgboost==3.2.0', 'lifelines==0.30.0')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
#!/usr/bin/env python3
"""
CQC Module 7 — Financial & fleet exposure (Gaussian-copula Monte Carlo).

For each ISSUE, projects total forward exposure on the exposed fleet with
CORRELATED failures (shared root cause) via a Gaussian copula, and cost drawn
from a lognormal. Produces the exposure distribution -> P50 / P90 / mean / CVaR95.
Writes CQC_ML.EXPOSURE_SIMULATION and registers EXPOSURE_SIMULATOR (custom model)
so the agent's SP_SIMULATE_EXPOSURE can run what-if spread scenarios.

Copula = Gaussian (doc 4 §8.3). Run:
  SNOWFLAKE_CONNECTION_NAME=my_snowflake .venv/bin/python platform/ml/module7_exposure.py
"""
import sys, os
import numpy as np
import pandas as pd

N_SIMS = 20000
RHO = 0.20            # intra-issue failure correlation (shared cause)

def simulate(exposed_n, p_fail, cost_mu, cost_sigma, rho=RHO, n=N_SIMS, seed=7):
    """Gaussian-copula correlated Bernoulli failures x lognormal cost."""
    if exposed_n <= 0 or p_fail <= 0:
        return np.zeros(n)
    rng = np.random.default_rng(seed)
    thr = float(np.clip(p_fail, 1e-4, 0.999))
    from scipy.stats import norm
    z_thr = norm.ppf(thr)
    # one shared factor + idiosyncratic -> exchangeable correlation rho
    f = rng.standard_normal(n)
    exposures = np.empty(n)
    b = np.sqrt(max(rho, 0.0)); a = np.sqrt(max(1 - rho, 1e-6))
    for i in range(n):
        latent = b * f[i] + a * rng.standard_normal(exposed_n)
        fails = int((latent < z_thr).sum())
        if fails > 0:
            costs = rng.lognormal(cost_mu, cost_sigma, fails)
            exposures[i] = costs.sum()
        else:
            exposures[i] = 0.0
    return exposures

def main(session):
    for s in ("USE WAREHOUSE SF_SOLUTIONS_WH", "USE DATABASE SF_SOLUTIONS", "USE SCHEMA CQC_ML"):
        session.sql(s).collect()

    # per-issue exposure inputs: exposed fleet, forward failure prob, cost params
    issues = session.sql("""
        WITH d AS (
            SELECT MD5(e.model||'|'||e.system_group_cd||'|'||e.failure_mode_cd) issue_id,
                   ANY_VALUE(e.model) model, ANY_VALUE(e.failure_mode_cd) failure_mode_cd,
                   ANY_VALUE(e.system_group_cd) system_group_cd,
                   COUNT(*) events, COUNT(DISTINCT e.machine_key) fleet,
                   AVG(NULLIF(e.repair_cost_usd,0)) avg_cost,
                   STDDEV(NULLIF(e.repair_cost_usd,0)) sd_cost
            FROM SF_SOLUTIONS.CQC_ATOMIC.FACT_QUALITY_EVENT e
            WHERE e.failure_mode_cd IS NOT NULL GROUP BY 1 HAVING COUNT(*) >= 40)
        SELECT d.*,
               COALESCE(rc.exposed, 0) suspect_exposed
        FROM d
        LEFT JOIN (
            SELECT MD5(model||'|'||system_group_cd||'|'||failure_mode_cd) issue_id,
                   SUM(fleet_with_attr) exposed
            FROM SF_SOLUTIONS.CQC_ML.ROOT_CAUSE_ATTRIBUTION WHERE is_significant
            GROUP BY 1) rc ON rc.issue_id = d.issue_id
    """).to_pandas()

    rows = []
    for r in issues.itertuples():
        # exposed = suspect fleet if a significant concentration exists else full issue fleet
        exposed = int(r.SUSPECT_EXPOSED) if r.SUSPECT_EXPOSED and r.SUSPECT_EXPOSED > 0 else int(r.FLEET)
        # forward failure prob on exposed (remaining risk proxy)
        p_fail = float(np.clip((r.EVENTS / max(r.FLEET, 1)) * 0.35, 0.02, 0.6))
        cost_mean = float(r.AVG_COST) if r.AVG_COST and r.AVG_COST > 0 else 4500.0
        cost_sd = float(r.SD_COST) if r.SD_COST and r.SD_COST > 0 else cost_mean * 0.5
        # lognormal params from mean/sd
        var = cost_sd ** 2
        mu = np.log(cost_mean ** 2 / np.sqrt(var + cost_mean ** 2))
        sigma = np.sqrt(np.log(1 + var / cost_mean ** 2))
        sims = simulate(exposed, p_fail, mu, sigma)
        rows.append({
            "ISSUE_ID": r.ISSUE_ID, "MODEL": r.MODEL, "FAILURE_MODE_CD": r.FAILURE_MODE_CD,
            "EXPOSED_FLEET": exposed, "P_FAIL_FORWARD": round(p_fail, 4),
            "EXPOSURE_MEAN": round(float(sims.mean()), 0),
            "EXPOSURE_P50": round(float(np.percentile(sims, 50)), 0),
            "EXPOSURE_P90": round(float(np.percentile(sims, 90)), 0),
            "EXPOSURE_CVAR95": round(float(sims[sims >= np.percentile(sims, 95)].mean()), 0),
            "COPULA": "GAUSSIAN", "RHO": RHO, "N_SIMS": N_SIMS,
        })
    exp_df = pd.DataFrame(rows)
    session.write_pandas(exp_df, "EXPOSURE_SIMULATION", database="SF_SOLUTIONS", schema="CQC_ML",
                         auto_create_table=True, overwrite=True, quote_identifiers=False, use_logical_type=True)
    print(f"EXPOSURE_SIMULATION rows: {len(exp_df)}")
    a = exp_df[(exp_df.MODEL == "LX-950") & (exp_df.FAILURE_MODE_CD == "POWER_LOSS")]
    print("\n=== VALIDATION: anchor exposure (LX-950 POWER_LOSS) ===")
    if len(a):
        r = a.iloc[0]
        print(f"  exposed={r.EXPOSED_FLEET} p_fail={r.P_FAIL_FORWARD} "
              f"P50=${r.EXPOSURE_P50:,.0f} P90=${r.EXPOSURE_P90:,.0f} CVaR95=${r.EXPOSURE_CVAR95:,.0f}")

    # register EXPOSURE_SIMULATOR as a custom model (non-fatal if it fails)
    try:
        from snowflake.ml.model import custom_model
        class ExposureSim(custom_model.CustomModel):
            @custom_model.inference_api
            def predict(self, X: pd.DataFrame) -> pd.DataFrame:
                out = []
                for row in X.itertuples():
                    s = simulate(int(row.exposed_fleet), float(row.p_fail),
                                 float(row.cost_mu), float(row.cost_sigma))
                    out.append([float(np.percentile(s, 50)), float(np.percentile(s, 90)),
                                float(s[s >= np.percentile(s, 95)].mean())])
                return pd.DataFrame(out, columns=["p50", "p90", "cvar95"])
        from snowflake.ml.registry import Registry
        reg = Registry(session, database_name="SF_SOLUTIONS", schema_name="CQC_ML")
        sample = pd.DataFrame({"exposed_fleet": [63], "p_fail": [0.2], "cost_mu": [8.4], "cost_sigma": [0.5]})
        mv = reg.log_model(ExposureSim(custom_model.ModelContext()), model_name="EXPOSURE_SIMULATOR",
                           version_name="V1", sample_input_data=sample,
                           conda_dependencies=["scipy", "numpy", "pandas"], target_platforms=["WAREHOUSE"],
                           comment="Gaussian-copula fleet exposure Monte Carlo")
        print(f"Registered EXPOSURE_SIMULATOR {mv.version_name}")
    except Exception as e:
        print(f"[registry] EXPOSURE_SIMULATOR skipped (non-fatal): {str(e)[:160]}")

def run(session):
    """Stored-procedure handler: run the module and return its validation output."""
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        main(session)
    return buf.getvalue()[-16000:]
$$;

SELECT 'CQC setup complete. Next: run scripts/data.sql' AS STATUS;
