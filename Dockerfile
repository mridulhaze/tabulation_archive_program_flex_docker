# ─────────────────────────────────────────────────
#  NU Tabulation Archive  –  Docker Image
#  Python 3.11 slim  |  oracledb thin mode (no IC)
# ─────────────────────────────────────────────────
FROM python:3.11-slim

# System deps for Pillow (JPEG support)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-turbo-progs \
    libpng-dev \
    libfreetype6-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Working directory inside container
WORKDIR /app

# Copy requirements first for layer caching
COPY requirements.txt .

# Install all Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire project (excluding venv via .dockerignore)
COPY . .

# Create temp_cache directory
RUN mkdir -p /app/temp_cache

# Expose Flask port
EXPOSE 5000

# Run with Gunicorn for production (threaded)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--threads", "4", "--timeout", "120", "tabulation_web:app"]