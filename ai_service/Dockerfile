# Base image Python 3.11 Slim (ringan & cocok untuk VPS)
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Hindari output buffering python
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install dependensi sistem Linux yang dibutuhkan oleh OpenCV & dlib/face_recognition
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements dan install packages python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy seluruh source code ai_service
COPY . .

# Expose port service
EXPOSE 5001

# Jalankan service menggunakan Gunicorn production server (atau python app.py)
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "2", "--timeout", "120", "app:app"]
