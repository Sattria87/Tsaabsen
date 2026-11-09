# Base image Python 3.11 Slim via AWS ECR Public (100% IPv4, bebas error IPv6 unreachable & limit Docker Hub)
FROM public.ecr.aws/docker/library/python:3.11-slim

# Set working directory
WORKDIR /app

# Hindari output buffering python
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install dependensi sistem Linux yang dibutuhkan oleh OpenCV & InsightFace
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3-dev \
    cmake \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip & install build tools (wheel, setuptools, Cython)
RUN pip install --no-cache-dir --upgrade pip setuptools wheel Cython

# Pre-install numpy < 2.0.0 agar ekstensi C InsightFace kompatibel dan tidak crash
RUN pip install --no-cache-dir "numpy>=1.24.0,<2.0.0"

# Copy requirements dan install packages python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy seluruh source code ai_service
COPY . .

# Expose port service
EXPOSE 5001

# Jalankan service menggunakan Gunicorn production server (atau python app.py)
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "2", "--timeout", "120", "app:app"]
