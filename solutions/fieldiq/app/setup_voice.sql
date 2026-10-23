-- =============================================================================
-- Solution: FieldIQ - optional voice add-on (SPCS GPU)
-- Not available on trial accounts (GPU compute pools). Not re-tested in this release.
-- Run after app/setup_app.sql (shares its image repository). Then build and push the
-- voice image (see app/voice/README.md) and run app/create_voice_service.sql.
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- GPU compute pool (one NVIDIA A10G node). Suspend it when not in use.
CREATE COMPUTE POOL IF NOT EXISTS SF_SOLUTIONS_FIQ_VOICE_POOL
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = GPU_NV_S
  AUTO_RESUME = TRUE
  AUTO_SUSPEND_SECS = 600
  COMMENT = 'FieldIQ voice service (VAD + Whisper + TTS)';
