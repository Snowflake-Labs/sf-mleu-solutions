-- =============================================================================
-- Solution: FieldIQ - optional voice add-on (SPCS GPU)
-- Run after app/setup_voice.sql and after pushing the voice image (see app/voice/README.md).
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

CREATE SERVICE IF NOT EXISTS SF_SOLUTIONS.FIQ_CORTEX.FIQ_VOICE_SERVICE
  IN COMPUTE POOL SF_SOLUTIONS_FIQ_VOICE_POOL
  FROM SPECIFICATION $$
spec:
  containers:
    - name: voice
      image: /sf_solutions/fiq_cortex/fiq_images/fieldiq-voice:latest
      env:
        VOICE_PORT: "8080"
        WHISPER_MODEL: "/app/models/whisper/large-v3"
        TTS_MODE: "fast"
        VOICE_DEVICE: "cuda"
        AGENT_DATABASE: "SF_SOLUTIONS"
        AGENT_SCHEMA: "FIQ_CORTEX"
        AGENT_NAME: "FIELDIQ_AGENT"
      resources:
        requests:
          nvidia.com/gpu: 1
        limits:
          nvidia.com/gpu: 1
  endpoints:
    - name: voice
      port: 8080
      public: true
$$
  MIN_INSTANCES = 1
  MAX_INSTANCES = 1;

-- Voice endpoint (open it in a browser and sign in with Snowflake)
SHOW ENDPOINTS IN SERVICE SF_SOLUTIONS.FIQ_CORTEX.FIQ_VOICE_SERVICE;

-- Stop GPU cost when done:
--   ALTER SERVICE SF_SOLUTIONS.FIQ_CORTEX.FIQ_VOICE_SERVICE SUSPEND;
--   ALTER COMPUTE POOL SF_SOLUTIONS_FIQ_VOICE_POOL SUSPEND;
