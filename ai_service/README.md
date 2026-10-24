# ProjectWG — AI Face Recognition Service

Layanan Microservice AI Backend (Python) untuk sistem absensi ProjectWG. Layanan ini bertugas mendeteksi wajah dan mencocokkan foto selfie saat absensi karyawan dengan foto acuan yang tersimpan di sistem.

---

## 📁 Struktur Direktori

```text
ProjectWG/
├── ai_service/                 # Folder Microservice AI
│   ├── app.py                  # Server REST API (Flask)
│   ├── config.py               # Konfigurasi Port, DB, dan Threshold AI
│   ├── face_engine.py          # Logika Inti Deteksi & Pencocokan Wajah
│   ├── test_client.py          # Skrip uji coba cepat endpoint API
│   ├── requirements.txt        # Daftar dependensi library Python
│   ├── .env.example            # Template file environment
│   ├── Dockerfile              # Setup container untuk VPS Linux
│   ├── docker-compose.yml      # Deployment VPS 1-klik dengan Docker
│   ├── models/                 # Tempat file bobot model (.pt / .onnx / .h5)
│   └── embeddings/             # Cache vektor fitur wajah karyawan
├── assets/
│   └── foto_karyawan/          # Foto acuan karyawan dari admin dashboard
├── backend/                    # Express.js REST API
└── lib/                        # Flutter Mobile App
```

---

## 🚀 Panduan Menjalankan Secara Lokal (Windows)

### 1. Buka Terminal ke folder `ai_service`
```powershell
cd "c:\Users\MSI GF63\Downloads\ProjectWG\ProjectWG\ai_service"
```

### 2. (Opsional tapi disarankan) Buat Virtual Environment
```powershell
python -m venv venv
.\venv\Scripts\activate
```

### 3. Install Dependensi (InsightFace & ONNX Runtime)
```powershell
pip install -r requirements.txt
```
> **Catatan Windows:** Model utama kini menggunakan **InsightFace (ArcFace 512D ONNX)** yang tidak memerlukan compile C++ dlib di Windows! Paket `onnxruntime` dan `insightface` langsung berjalan secara plug-and-play di CPU maupun GPU.

### 4. Salin File Environment
```powershell
copy .env.example .env
```

### 5. Jalankan Service
```powershell
python app.py
```
Service akan aktif di: **`http://localhost:5001`** (atau `http://<IP_KOMPUTER>:5001` untuk akses dari HP).

---

## 📡 Daftar Endpoint API

### 1. Health Check
- **URL**: `GET /health`
- **Output**:
```json
{
  "status": "online",
  "engine": "InsightFace (ArcFace 512D - buffalo_s)",
  "engine_type": "insightface",
  "similarity_threshold": "65.0%"
}
```

### 2. Verifikasi Wajah Absensi (Utama)
- **URL**: `POST /api/verify`
- **Headers**: `Content-Type: application/json`
- **Body**:
```json
{
  "username": "aan",
  "image": "<base64_string_foto_selfie_kamera_hp>"
}
```
- **Response Sukses (Cocok)**:
```json
{
  "success": true,
  "username": "aan",
  "matched": true,
  "similarity_score": 88.45,
  "distance": 0.32,
  "message": "Wajah cocok!"
}
```
- **Response Wajah Tidak Cocok**:
```json
{
  "success": true,
  "username": "aan",
  "matched": false,
  "similarity_score": 42.10,
  "distance": 0.78,
  "message": "Wajah tidak cocok (Kemiripan: 42.1%, minimal: 65.0%)"
}
```

### 3. Deteksi Wajah
- **URL**: `POST /api/detect`
- Mengecek apakah ada wajah terdeteksi pada gambar sebelum dikirim.

---

## 🌐 Panduan Deployment ke VPS (Linux)

Saat Anda siap memindahkan layanan ini ke VPS, ada 2 cara mudah:

### Cara 1: Menggunakan Docker (Direkomendasikan)
Di VPS Linux (Ubuntu/Debian), seluruh dependensi C++, CMake, dan Python terpasang otomatis:
```bash
cd ai_service
docker compose up -d --build
```
Untuk melihat log:
```bash
docker compose logs -f
```

### Cara 2: Menjalankan Langsung dengan Systemd + Gunicorn
1. Install dependensi sistem di VPS:
   ```bash
   sudo apt update
   sudo apt install -y python3-pip python3-venv cmake build-essential libgl1 libglib2.0-0
   ```
2. Setup environment & install packages:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```
3. Jalankan via Gunicorn:
   ```bash
   gunicorn --bind 0.0.0.0:5001 --workers 2 --timeout 120 app:app
   ```
4. Hubungkan ke domain/subdomain VPS menggunakan Nginx Reverse Proxy (misal: `https://ai.domainanda.com`).
