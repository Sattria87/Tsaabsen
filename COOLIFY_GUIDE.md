# 🚀 Panduan Deployment ProjectWG di VPS Menggunakan Coolify & Docker Compose

Panduan ini menjelaskan langkah demi langkah cara men-deploy seluruh ekosistem **ProjectWG** (Database MySQL, REST API Express.js, Website Admin TSA Flask, dan Python AI Face Recognition Service) ke VPS Anda menggunakan **Coolify** secara otomatis via **Docker Compose**.

---

## 🏗️ Arsitektur Layanan (Docker Compose)

File `docker-compose.yml` telah mengorkestrasi 4 service utama:

| Service | Deskripsi | Port Internal | Pengaturan Domain di Coolify |
| :--- | :--- | :--- | :--- |
| **`db`** | MySQL 8.0 Database + Inisialisasi Otomatis (`init.sql`) | `3306` | *Tidak perlu domain (Private Network)* |
| **`backend`** | Node.js Express.js REST API (Koneksi Flutter Mobile) | `3000` | Misal: `https://api.domainanda.com` |
| **`admin_web`** | Flask Web TSA Admin Dashboard | `8085` | Misal: `https://admin.domainanda.com` |
| **`ai_service`** | Python Face Recognition Engine (ArcFace 512D) | `5001` | *Diakses internal oleh backend via http://ai_service:5001* |

---

## 📋 Langkah-Langkah Deploy di Coolify

### Langkah 1: Push Perubahan ke Git Repository
Pastikan seluruh file baru (`docker-compose.yml`, `Dockerfile.web`, `backend/Dockerfile`, `docker/mysql/init.sql`, dll) sudah di-commit dan di-push ke repository GitHub / GitLab Anda:
```bash
git add .
git commit -m "feat: Add Docker Compose & Coolify deployment setup"
git push origin main
```

---

### Langkah 2: Buat Resource Baru di Coolify Dashboard
1. Buka dashboard **Coolify** Anda di browser (contoh: `http://IP_VPS:8000` atau domain Coolify Anda).
2. Pilih **Projects** -> Pilih Environment (misal: `Production`).
3. Klik tombol **+ New Resource** -> Pilih **Docker Compose**.
4. Pilih sumber kode: **GitHub App / Private Repository / Public Repository**.
5. Pilih repository `ProjectWG` Anda dan tentukan branch (misal: `main`).

---

### Langkah 3: Konfigurasi Environment Variables di Coolify
Coolify menyediakan tab **Environment Variables**. Anda bisa menyalin isi dari file [`.env.example`](file:///d:/Magang/APLIKASI%20WG/POROJECTTT/ProjectWG/ProjectWG/ProjectWG/.env.example) ke kolom Environment Variables Coolify:

```env
PORT_DB=3306
DB_HOST=db
DB_PORT=3306
DB_NAME=absensi_wg
DB_USER=root
DB_PASSWORD=ganti_dengan_password_aman_anda
DB_ROOT_PASSWORD=ganti_dengan_password_aman_anda

PORT_BACKEND=3000
AI_SERVICE_URL=http://ai_service:5001/api/verify

PORT_ADMIN=8085
FLASK_DEBUG=False
SECRET_KEY=kunci_rahasia_acak_panjang_anda

PORT_AI=5001
AI_HOST=0.0.0.0
AI_PORT=5001
AI_DEBUG=False
FACE_TOLERANCE=0.55
SIMILARITY_THRESHOLD=70.0
ASSETS_DIR=/app/assets
```

> [!TIP]
> Ganti `DB_PASSWORD` dan `DB_ROOT_PASSWORD` dengan password rahasia pilihan Anda sebelum menekan tombol Deploy.

---

### Langkah 4: Tentukan Domain untuk Masing-Masing Service
Di antarmuka Coolify untuk resource Docker Compose Anda:
1. **Untuk Website Admin (`admin_web`)**:
   - Masukkan domain yang Anda inginkan, misalnya: `https://admin.perusahaan.com`
   - Pastikan port diarahkan ke `8085`.
2. **Untuk Backend API Flutter (`backend`)**:
   - Masukkan domain yang Anda inginkan, misalnya: `https://api.perusahaan.com`
   - Pastikan port diarahkan ke `3000`.
3. Coolify akan otomatis mengonfigurasi **SSL/HTTPS gratis (Let's Encrypt)** dan routing reverse proxy (Traefik) ke container tersebut.

---

### Langkah 5: Klik "Deploy"
1. Klik tombol **Deploy** di pojok kanan atas Coolify.
2. Coolify akan:
   - Melakukan clone repository.
   - Mem-build image untuk `backend`, `admin_web`, dan `ai_service`.
   - Mengunduh image `mysql:8.0`.
   - Mengeksekusi script [`docker/mysql/init.sql`](file:///d:/Magang/APLIKASI%20WG/POROJECTTT/ProjectWG/ProjectWG/ProjectWG/docker/mysql/init.sql) saat database pertama kali menyala, sehingga seluruh tabel dan data default langsung tersedia!
3. Pantau log build di Coolify hingga status semua service berubah menjadi **Healthy / Running**.

---

## 📱 Menghubungkan Aplikasi Flutter Mobile ke VPS

Setelah `backend` aktif dan memiliki domain (misal `https://api.perusahaan.com`), perbarui file Flutter Anda:

Buka file [`lib/utils/mysql_helper.dart`](file:///d:/Magang/APLIKASI%20WG/POROJECTTT/ProjectWG/ProjectWG/ProjectWG/lib/utils/mysql_helper.dart) di baris 12:

```dart
// Ganti URL trycloudflare lama dengan domain publik VPS Coolify Anda:
const String apiBaseUrl = 'https://api.perusahaan.com/api';
```

Setelah itu, build APK Android untuk karyawan:
```bash
flutter build apk --release
```
Aplikasi Android kini dapat melakukan presensi kehadiran, verifikasi wajah AI, dan pengajuan izin secara online dari mana saja selama 24/7!

---

## 🔑 Akun & Kredensial Bawaan (Default Data)

Database sudah otomatis diinisialisasi dengan data awal:

### 1. Dashboard Website Admin TSA
- **URL**: `https://admin.domainanda.com/login`
- **Username**: `admin`
- **Password**: `123`

### 2. Akun Mobile Karyawan (Aplikasi Flutter)
| Username | Password | Nama Karyawan | Divisi | Cabang | Foto Wajah AI |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `satriya` | `123` | Satriya Putra | IT | Surabaya | Tersedia di `assets/foto_karyawan/` |
| `aan` | `123` | Aan Handoko | HR | Surabaya | Tersedia di `assets/foto_karyawan/` |
| `reva` | `123` | Reva Oktaviana | Operasional | Jakarta | Tersedia di `assets/foto_karyawan/` |
| `ridho` | `123` | Ridho Ramadhan | IT | Surabaya | Tersedia di `assets/foto_karyawan/` |
| `rifky` | `123` | Rifky Hidayat | Keuangan | Surabaya | Tersedia di `assets/foto_karyawan/` |
| `moh` | `123` | Mohammad Fajar | Marketing | Jakarta | Tersedia di `assets/foto_karyawan/` |

---

## 💾 Persistensi Data & File Upload

1. **Database**: Seluruh data MySQL disimpan secara permanen di Docker Volume `projectwg_db_data`, sehingga data absensi dan karyawan tidak akan hilang saat container di-restart atau di-update.
2. **Foto & Assets**: Folder `./assets` di-mount ke seluruh service (`backend`, `admin_web`, dan `ai_service`). Foto selfie karyawan baru atau bukti izin sakit yang di-upload dari aplikasi langsung tersimpan di disk VPS dan dapat diakses bersama secara realtime.
3. **AI Models**: Cache model InsightFace ArcFace disimpan di volume `projectwg_insightface_models` agar tidak perlu mengunduh ulang model setiap kali container dimulai.
