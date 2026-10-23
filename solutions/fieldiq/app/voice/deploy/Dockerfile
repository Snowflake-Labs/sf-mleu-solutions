# Task 9 - SPCS GPU deployment for the FieldIQ Voice service.
#
# Runs on a GPU_NV_S (A10G 24GB) compute pool. CUDA base image so torch +
# faster-whisper (and later MOSS-TTSD) use the GPU. Piper runs on CPU.
# Build for linux/amd64 (SPCS nodes are amd64).

FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.11 python3-pip ffmpeg curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Torch (CUDA 12.4 wheels) first, then the rest.
RUN pip install --upgrade pip \
    && pip install torch --index-url https://download.pytorch.org/whl/cu124

COPY app/voice/requirements.txt /app/voice/requirements.txt
RUN pip install -r /app/voice/requirements.txt

# Bake models into the image (SPCS has no outbound internet by default, and the
# build host sits behind a TLS-inspecting proxy). Models are pre-downloaded on
# the host into app/voice/deploy/models/ and copied in here.
#   whisper: Systran/faster-whisper-large-v3 (ctranslate2 format)
#   piper:   en_US-lessac-medium
ENV WHISPER_MODEL=/app/models/whisper/large-v3 \
    PIPER_MODEL=/app/models/piper/en_US-lessac-medium.onnx \
    PIPER_CONFIG=/app/models/piper/en_US-lessac-medium.onnx.json
COPY app/voice/deploy/models /app/models

# App code (voice module + backend it bridges to).
COPY app/voice /app/voice
COPY app/backend /app/backend

EXPOSE 8080

# uvicorn serves the WebSocket voice service.
CMD ["python3", "-m", "uvicorn", "voice.server.ws_service:app", \
     "--host", "0.0.0.0", "--port", "8080", "--ws", "websockets"]
