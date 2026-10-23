# FieldIQ - SPCS container
# Multi-stage build: React frontend + FastAPI backend

# =============================================================================
# Stage 1: Build React Frontend
# =============================================================================
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

# Copy package files
COPY frontend/package*.json ./

# Install dependencies
RUN npm ci --silent

# Copy source code
COPY frontend/ ./

# Build production bundle
RUN npm run build

# =============================================================================
# Stage 2: Production Runtime
# =============================================================================
FROM python:3.11-slim

# Install nginx and supervisor
RUN apt-get update && apt-get install -y \
    nginx \
    supervisor \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Python requirements and install
COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend code
COPY backend/ ./backend/

# Copy built frontend from stage 1
COPY --from=frontend-builder /app/frontend/dist /usr/share/nginx/html

# Copy nginx configuration
COPY deploy/nginx.conf /etc/nginx/nginx.conf

# Copy supervisor configuration
COPY deploy/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create log directories
RUN mkdir -p /var/log/supervisor /var/log/nginx

# Create startup script that shows logs
RUN echo '#!/bin/bash\n\
set -e\n\
echo "=== FIELDIQ STARTUP ===" \n\
echo "Python version: $(python --version)" \n\
echo "Working directory: $(pwd)" \n\
echo "SNOWFLAKE_HOST: ${SNOWFLAKE_HOST:-NOT_SET}" \n\
echo "Token file exists: $(test -f /snowflake/session/token && echo YES || echo NO)" \n\
echo "Starting nginx..." \n\
nginx \n\
echo "Starting uvicorn..." \n\
exec python -m uvicorn backend.api.main:app --host 0.0.0.0 --port 8000 --log-level info \n\
' > /app/start.sh && chmod +x /app/start.sh

# Expose port (nginx will handle both frontend and API proxy)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start with script that shows logs
CMD ["/bin/bash", "/app/start.sh"]
