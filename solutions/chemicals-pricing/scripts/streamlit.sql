-- =============================================================================
-- Solution: Chemicals Pricing & Margin Intelligence - streamlit
-- Database: SF_SOLUTIONS
-- Schemas:  CHP_RAW, CHP_ATOMIC, CHP_OPS
-- Creates the Streamlit app from files uploaded to CHP_OPS.STREAMLIT_STAGE.
-- Run order: setup.sql -> data.sql -> pipeline.sql -> (upload app files) -> streamlit.sql
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed by the terms in
-- LICENSE, unless expressly agreed to in writing. You use this application at your own
-- risk, and Snowflake has no obligation to support your use of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;


-- =============================================================================
-- Streamlit app
-- =============================================================================

CREATE OR REPLACE STREAMLIT SF_SOLUTIONS.CHP_OPS.CHEMICALS_PRICING_APP
    FROM '@SF_SOLUTIONS.CHP_OPS.STREAMLIT_STAGE'
    MAIN_FILE = 'streamlit_app.py'
    QUERY_WAREHOUSE = SF_SOLUTIONS_WH
    TITLE = 'Chemicals Pricing & Margin Intelligence';
ALTER STREAMLIT SF_SOLUTIONS.CHP_OPS.CHEMICALS_PRICING_APP ADD LIVE VERSION FROM LAST;
