# ProjectWG Backend (Express.js)

Backend REST API untuk aplikasi absensi mobile Flutter ProjectWG. Menghubungkan aplikasi Flutter dengan database MySQL secara terpisah dan aman melalui protokol HTTP.

## 🚀 Fitur & Endpoint API

| Method | Endpoint | Deskripsi |
|---|---|---|
| `GET` | `/api/health` | Cek status server dan koneksi database MySQL |
| `POST` | `/api/login` | Autentikasi user (body: `username`, `password`) |
| `GET` | `/api/user/face/:username` | Ambil path foto acuan wajah user |
| `GET` | `/api/branches` | Ambil daftar semua kantor cabang (lat, lng, radius) |
| `POST` | `/api/attendance` | Simpan absensi (body: `username`, `type`, `reason`) |
| `GET` | `/api/attendance/status/:username` | Cek status absensi hari ini (siklus harian 23:55) |
| `GET` | `/assets/*` | Akses foto statis (misal foto karyawan) |

---

## 🛠️ Cara Menjalankan

1. **Pastikan MySQL (XAMPP) sudah aktif.**
2. Buka terminal di folder `backend/`:
   ```bash
   cd backend
   npm install
   npm start
   ```
   Atau untuk mode auto-reload saat koding:
   ```bash
   npm run dev
   ```
3. Server akan berjalan di:
   - **Localhost**: `http://localhost:3000`
   - **Jaringan HP (Wi-Fi)**: `http://<IP_KOMPUTER>:3000` (contoh: `http://192.168.1.11:3000`)
