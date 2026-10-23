# FieldIQ voice service (optional, SPCS GPU)

An open-source voice front end for `FIELDIQ_AGENT`: a field rep holds a multi-turn spoken
conversation and hears answers grounded in the same Snowflake data. The pipeline is Silero VAD
(end of turn, barge-in), faster-whisper large-v3 (speech to text), a session engine with
conversation history, and Piper (text to speech). Audio stays inside Snowpark Container Services.

> **Not re-tested in this release.** The voice code was renamed for this release but the voice
> image has not been rebuilt and run end to end. The logic-layer unit tests (`tests/`) pass. Treat
> this add-on as a starting point.

**Not available on trial accounts:** it needs a GPU compute pool (`GPU_NV_S`, one NVIDIA A10G).
A GPU node is billed while the pool is running; suspend it when you're done.

## Module layout

```
voice/
  conversation/   logic layer (no GPU): prompts, formatter (markdown -> speakable text),
                  session (turns, history, barge-in), agent_bridge (calls FIELDIQ_AGENT)
  audio/          vad.py (Silero), stt.py (faster-whisper), tts.py (Piper)
  server/         config.py (env), ws_service.py (FastAPI WebSocket, serves a test page at /)
  client/         ws_test_client.html (push to talk), cli_client.py (scripted text turns)
  tests/          unit tests for the logic layer
  deploy/         Dockerfile (CUDA 12.4 base), models/ (downloaded weights, not committed)
```

## Run the logic tests locally (no GPU)

```bash
cd app
pip install pytest
PYTHONPATH=. python -m pytest -q voice/tests
```

## Deploy

1. Install the web-app add-on first (`app/setup_app.sql`): the voice image goes in the same
   image repository. Then create the GPU pool:

   ```bash
   snow sql -f app/setup_voice.sql --enable-templating NONE
   ```

2. Download the model weights (about 3 GB) into `app/voice/deploy/models/`. They are baked into
   the image because SPCS has no outbound internet by default:

   ```bash
   python - <<'PY'
   from huggingface_hub import snapshot_download
   snapshot_download("Systran/faster-whisper-large-v3",
                     local_dir="app/voice/deploy/models/whisper/large-v3")
   PY
   mkdir -p app/voice/deploy/models/piper
   curl -L -o app/voice/deploy/models/piper/en_US-lessac-medium.onnx \
     https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx
   curl -L -o app/voice/deploy/models/piper/en_US-lessac-medium.onnx.json \
     https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json
   ```

   Check each model's license before using it.

3. Build and push the image from the **solution root** (the Dockerfile copies `app/voice` and
   `app/backend`). The image is about 12 GB; make sure Docker has the disk space:

   ```bash
   snow spcs image-registry login
   docker build --platform linux/amd64 --provenance=false \
     -f app/voice/deploy/Dockerfile -t <repository_url>/fieldiq-voice:latest .
   docker push <repository_url>/fieldiq-voice:latest
   ```

4. Create the service and get the URL:

   ```bash
   snow sql -f app/create_voice_service.sql --enable-templating NONE
   ```

   Open the endpoint in Chrome or Safari, sign in with Snowflake, click **Connect**, hold
   **Hold to Talk**, ask a question and release.

## Stop GPU cost

```sql
ALTER SERVICE SF_SOLUTIONS.FIQ_CORTEX.FIQ_VOICE_SERVICE SUSPEND;
ALTER COMPUTE POOL SF_SOLUTIONS_FIQ_VOICE_POOL SUSPEND;
```

`scripts/teardown.sql` drops the voice service and its compute pool.
