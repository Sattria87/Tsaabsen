// ============================================================
//  server.js — ProjectWG Express Backend API
//  Backend REST API untuk Aplikasi Flutter Absensi
// ============================================================

const express = require('express');
const mysql   = require('mysql2/promise');
const cors    = require('cors');
const path    = require('path');
const fs      = require('fs');

const app  = express();
const PORT = process.env.PORT || 3000;

// ============================================================
// KONFIGURASI DATABASE MYSQL (CONNECTION POOL)
// ============================================================
const isSslNeeded = process.env.DB_SSL === 'true' || Number(process.env.DB_PORT) === 4000;
const DB_CONFIG = {
  host              : process.env.DB_HOST || 'localhost',
  port              : Number(process.env.DB_PORT) || 3306,
  user              : process.env.DB_USER || 'root',
  password          : process.env.DB_PASSWORD !== undefined ? process.env.DB_PASSWORD : '',
  database          : process.env.DB_NAME || 'absensi_wg',
  timezone          : '+07:00', // WIB
  waitForConnections: true,
  connectionLimit   : 10,
  queueLimit        : 0,
  ssl               : isSslNeeded ? { minVersion: 'TLSv1.2', rejectUnauthorized: true } : undefined,
};

const pool = mysql.createPool(DB_CONFIG);

// ============================================================
// MIDDLEWARE
// ============================================================
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Logging setiap request yang masuk
app.use((req, res, next) => {
  console.log(`[REQ] ${req.method} ${req.url}`);
  next();
});

// ============================================================
// RESOLVE DIREKTORI ASSETS (DOCKER / LOCAL)
// ============================================================
function resolveAssetsDir() {
  const possiblePaths = [
    process.env.ASSETS_DIR,
    path.join(__dirname, 'assets'),            // Di dalam container: /app/assets
    path.join('/app/assets'),                  // Path absolut default container
    path.join(__dirname, '..', 'assets'),      // Local development: ProjectWG/assets
  ].filter(Boolean);

  for (const p of possiblePaths) {
    if (fs.existsSync(p)) {
      return p;
    }
  }
  return path.join(__dirname, '..', 'assets');
}

const assetsDir = resolveAssetsDir();
console.log(`[ASSETS] Direktori aset aktif: ${assetsDir}`);

// Sajikan folder assets (foto karyawan dsb) secara statis
app.use('/assets', express.static(assetsDir));

// ============================================================
// UTILITY: Siklus absensi harian (reset setiap pukul 23:55)
// ============================================================
function getAttendanceCycleStart(referenceTime) {
  const now = referenceTime || new Date();
  const resetToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 55, 0);

  if (now < resetToday) {
    const prev = new Date(resetToday);
    prev.setDate(prev.getDate() - 1);
    return prev;
  }
  return resetToday;
}

function getAttendanceCycleEnd(referenceTime) {
  const start = getAttendanceCycleStart(referenceTime);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return end;
}

function formatDatetimeForSql(dt) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())} ` +
         `${pad(dt.getHours())}:${pad(dt.getMinutes())}:${pad(dt.getSeconds())}`;
}

function formatTime(dt) {
  if (!dt) return '--:--';
  const d = dt instanceof Date ? dt : new Date(dt);
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// ============================================================
// HEALTH CHECK
// GET /api/health
// ============================================================
app.get('/api/health', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT 1 AS alive');
    res.json({
      status: 'ok',
      dbConnected: rows && rows.length > 0,
      message: 'ProjectWG Backend Express berjalan dengan baik!',
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    res.status(500).json({
      status: 'error',
      dbConnected: false,
      message: 'Koneksi database gagal: ' + err.message,
    });
  }
});

// ============================================================
// WORKDAY & INDONESIAN HOLIDAY STATUS
// GET /api/workday-status
// ============================================================
app.get('/api/workday-status', (req, res) => {
  const now = new Date();
  const dayOfWeek = now.getDay(); // 0: Minggu, 6: Sabtu
  const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

  // Format YYYY-MM-DD
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const dateKey = `${yyyy}-${mm}-${dd}`;
  const monthDay = `${mm}-${dd}`;

  const fixedHolidays = {
    '01-01': { name: 'Tahun Baru Masehi', is_cuti: false },
    '05-01': { name: 'Hari Buruh Internasional', is_cuti: false },
    '06-01': { name: 'Hari Lahir Pancasila', is_cuti: false },
    '08-17': { name: 'Hari Kemerdekaan RI (HUT RI)', is_cuti: false },
    '12-25': { name: 'Hari Raya Natal', is_cuti: false },
    '12-26': { name: 'Cuti Bersama Hari Raya Natal', is_cuti: true },
  };

  const curatedHolidays = {
    '2026-01-01': { name: 'Tahun Baru 2026 Masehi', is_cuti: false },
    '2026-01-16': { name: 'Isra Mikraj Nabi Muhammad SAW', is_cuti: false },
    '2026-02-16': { name: 'Cuti Bersama Tahun Baru Imlek 2577', is_cuti: true },
    '2026-02-17': { name: 'Tahun Baru Imlek 2577 Kongzili', is_cuti: false },
    '2026-03-19': { name: 'Cuti Bersama Hari Suci Nyepi', is_cuti: true },
    '2026-03-20': { name: 'Hari Suci Nyepi Tahun Baru Saka 1948', is_cuti: false },
    '2026-03-21': { name: 'Hari Raya Idul Fitri 1447 H', is_cuti: false },
    '2026-03-22': { name: 'Hari Raya Idul Fitri 1447 H', is_cuti: false },
    '2026-03-23': { name: 'Cuti Bersama Idul Fitri 1447 H', is_cuti: true },
    '2026-03-24': { name: 'Cuti Bersama Idul Fitri 1447 H', is_cuti: true },
    '2026-04-03': { name: 'Wafat Yesus Kristus (Jumat Agung)', is_cuti: false },
    '2026-05-01': { name: 'Hari Buruh Internasional', is_cuti: false },
    '2026-05-14': { name: 'Kenaikan Yesus Kristus', is_cuti: false },
    '2026-05-15': { name: 'Cuti Bersama Kenaikan Yesus Kristus', is_cuti: true },
    '2026-05-27': { name: 'Hari Raya Idul Adha 1447 H', is_cuti: false },
    '2026-05-31': { name: 'Hari Raya Waisak 2570 BE', is_cuti: false },
    '2026-06-01': { name: 'Hari Lahir Pancasila', is_cuti: false },
    '2026-06-16': { name: '1 Muharram Tahun Baru Islam 1448 H', is_cuti: false },
    '2026-08-17': { name: 'Proklamasi Kemerdekaan RI Ke-81', is_cuti: false },
    '2026-08-25': { name: 'Maulid Nabi Muhammad SAW', is_cuti: false },
    '2026-12-25': { name: 'Hari Raya Natal', is_cuti: false },
    '2026-12-26': { name: 'Cuti Bersama Hari Raya Natal', is_cuti: true },
  };

  const hol = curatedHolidays[dateKey] || fixedHolidays[monthDay];
  let statusType = 'workday';
  let isHoliday = false;
  let isCuti = false;
  let eventName = 'Hari Kerja Aktif';
  let statusLabel = 'Hari Kerja';

  if (hol) {
    isCuti = hol.is_cuti === true;
    isHoliday = !isCuti;
    statusType = isCuti ? 'cuti_bersama' : 'national_holiday';
    statusLabel = isCuti ? 'Cuti Bersama' : 'Libur Nasional (Tanggal Merah)';
    eventName = hol.name;
  } else if (isWeekend) {
    statusType = 'weekend';
    statusLabel = 'Akhir Pekan (Libur)';
    eventName = dayOfWeek === 6 ? 'Hari Sabtu (Libur Mingguan)' : 'Hari Minggu (Libur Mingguan)';
  }

  res.json({
    date_iso: dateKey,
    time_str: now.toTimeString().split(' ')[0],
    is_working_day: statusType === 'workday',
    is_weekend: isWeekend,
    is_holiday: isHoliday,
    is_cuti_bersama: isCuti,
    status_type: statusType,
    status_label_id: statusLabel,
    event_name_id: eventName,
    badge_class: statusType === 'workday' ? 'pill-workday' : (isCuti ? 'pill-cuti' : (isHoliday ? 'pill-holiday' : 'pill-weekend'))
  });
});

// ============================================================
// AUTH: Login
// POST /api/login
// Body: { username, password }
// ============================================================
app.post('/api/login', async (req, res) => {
  const { username, password } = req.body;
  console.log(`[LOGIN ATTEMPT] Username: "${username}"`);

  if (!username || !password) {
    return res.status(400).json({
      success: false,
      message: 'Username dan password wajib diisi',
    });
  }

  try {
    const [rows] = await pool.execute(
      'SELECT username, name, face_image FROM users WHERE username = ? AND password = ?',
      [username, password]
    );

    if (rows.length === 0) {
      console.log(`[LOGIN GAGAL] Username atau password salah: "${username}"`);
      return res.status(401).json({
        success: false,
        message: 'Username atau password salah',
      });
    }

    const user = rows[0];

    // Ambil info kantor cabang karyawan dari tabel employees (jika ada)
    let userBranch = null;
    try {
      const [empRows] = await pool.execute(
        'SELECT branch FROM employees WHERE username = ? LIMIT 1',
        [username]
      );
      if (empRows.length > 0 && empRows[0].branch) {
        userBranch = empRows[0].branch;
      }
    } catch (empErr) {
      console.log('[Login Employee Branch Query Info]', empErr.message);
    }

    console.log(`[LOGIN BERHASIL] Selamat datang, ${user.name} (${user.username}) - Cabang: ${userBranch || 'Default'}`);
    return res.json({
      success   : true,
      username  : user.username,
      name      : user.name,
      face_image: user.face_image ?? null,
      branch    : userBranch,
    });
  } catch (err) {
    console.error('[Login Error]', err.message);
    return res.status(500).json({
      success: false,
      message: 'Kesalahan server: ' + err.message,
    });
  }
});

// ============================================================
// USER: Ambil foto acuan wajah
// GET /api/user/face/:username
// ============================================================
app.get('/api/user/face/:username', async (req, res) => {
  const { username } = req.params;
  try {
    const [rows] = await pool.execute(
      'SELECT face_image FROM users WHERE username = ?',
      [username]
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User tidak ditemukan' });
    }
    return res.json({
      success   : true,
      face_image: rows[0].face_image ?? null,
    });
  } catch (err) {
    console.error('[FaceRef Error]', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================
// USER: Ambil stream file foto karyawan acuan
// GET /api/user/photo/:username
// ============================================================
app.get('/api/user/photo/:username', async (req, res) => {
  const { username } = req.params;
  try {
    const [rows] = await pool.execute(
      'SELECT face_image FROM users WHERE username = ?',
      [username]
    );
    if (rows.length === 0 || !rows[0].face_image) {
      return res.status(404).send('Foto tidak ditemukan');
    }

    const faceImage = rows[0].face_image.trim();

    // 1. Jika tersimpan sebagai Base64
    if (faceImage.startsWith('data:image') || (!faceImage.startsWith('http') && !faceImage.includes('/') && !faceImage.includes('\\') && faceImage.length > 150)) {
      let raw = faceImage;
      if (raw.includes(',')) raw = raw.split(',')[1];
      const imgBuf = Buffer.from(raw, 'base64');
      res.setHeader('Content-Type', 'image/jpeg');
      return res.send(imgBuf);
    }

    // 2. Jika path file
    let cleanPath = faceImage.replace(/\\/g, '/');
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
    if (cleanPath.startsWith('assets/')) cleanPath = cleanPath.substring(7);

    const candidates = [
      path.join(assetsDir, cleanPath),
      path.join(assetsDir, 'foto_karyawan', path.basename(cleanPath)),
      path.join(__dirname, '..', 'assets', cleanPath),
      path.join('/app/assets', cleanPath),
    ];

    for (const c of candidates) {
      if (fs.existsSync(c) && fs.statSync(c).isFile()) {
        return res.sendFile(path.resolve(c));
      }
    }

    return res.status(404).send('File foto fisik tidak ditemukan: ' + cleanPath);
  } catch (err) {
    console.error('[User Photo Error]', err.message);
    return res.status(500).send(err.message);
  }
});

// ============================================================
// AI: Verifikasi Wajah AI (Forward ke Python AI Service)
// POST /api/verify
// Body: { username, image }
// ============================================================
app.post('/api/verify', async (req, res) => {
  const { username, image, live_image } = req.body;
  const selfieImage = image || live_image;

  if (!username || !selfieImage) {
    return res.status(400).json({
      success: false,
      matched: false,
      message: 'username dan image (foto selfie) wajib dikirimkan',
    });
  }

  try {
    const aiUrl = process.env.AI_SERVICE_URL || 'http://127.0.0.1:5001/api/verify';
    console.log(`[AI PROXY] Mengirim foto @${username} ke AI Service (${aiUrl}) ...`);

    const aiRes = await fetch(aiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, image: selfieImage }),
    });

    const aiData = await aiRes.json();
    console.log(`[AI PROXY RESULT] @${username} -> Matched: ${aiData.matched}, Similarity: ${aiData.similarity_score}%`);
    return res.status(aiRes.status).json(aiData);
  } catch (err) {
    console.error('[AI Proxy Error]', err.message);
    return res.status(503).json({
      success: false,
      matched: false,
      similarity_score: 0.0,
      message: 'Gagal terhubung ke AI Service (Port 5001). Pastikan Python AI Service aktif: ' + err.message,
    });
  }
});

// ============================================================
// BRANCH: Ambil semua kantor cabang
// GET /api/branches
// ============================================================
app.get('/api/branches', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM branch_companies ORDER BY id ASC');
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error('[Branches Error]', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================
// ATTENDANCE: Simpan absensi (clock_in / clock_out / izin)
// POST /api/attendance
// Body: { username, type, reason }
// ============================================================
app.post('/api/attendance', async (req, res) => {
  const { username, type, reason, image } = req.body;

  if (!username || !type) {
    return res.status(400).json({
      success: false,
      message: 'username dan type wajib diisi',
    });
  }

  // Simpan foto lampiran jika ada (base64)
  let savedImagePath = null;
  if (image && typeof image === 'string' && image.trim().length > 0) {
    try {
      const uploadDir = path.join(assetsDir, 'foto_izin');
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }

      const base64Data = image.replace(/^data:image\/\w+;base64,/, '');
      const filename = `izin_${username}_${Date.now()}.jpg`;
      const filePath = path.join(uploadDir, filename);
      fs.writeFileSync(filePath, Buffer.from(base64Data, 'base64'));
      savedImagePath = `assets/foto_izin/${filename}`;
      console.log(`[Foto Izin Tersimpan] ${savedImagePath}`);
    } catch (imgErr) {
      console.error('[Error Simpan Foto Izin]', imgErr.message);
    }
  }

  try {
    if (type === 'clock_out') {
      const cycleStart    = getAttendanceCycleStart();
      const cycleEnd      = getAttendanceCycleEnd();
      const cycleStartStr = formatDatetimeForSql(cycleStart);
      const cycleEndStr   = formatDatetimeForSql(cycleEnd);

      // 1. Update clock_out pada baris clock_in aktif dalam siklus ini
      try {
        await pool.execute(
          `UPDATE attendance SET clock_out = NOW()
           WHERE username = ? AND timestamp >= ? AND timestamp < ? AND type = 'clock_in'
           ORDER BY id DESC LIMIT 1`,
          [username, cycleStartStr, cycleEndStr]
        );
      } catch (updateErr) {
        console.log('[ClockOut Update Info]', updateErr.message);
      }

      // 2. Insert baris clock_out baru
      await pool.execute(
        'INSERT INTO attendance (username, type, timestamp, clock_out, image_path, reason, status) VALUES (?, ?, NOW(), NOW(), ?, ?, ?)',
        [username, type, savedImagePath, reason ?? '', 'Approved']
      );
    } else {
      // clock_in atau izin (izin_sakit, izin_keperluan, dll)
      const isPermission = ['izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti'].includes(type) ||
                           type.startsWith('izin_');

      if (type === 'clock_in') {
        const cycleStart    = getAttendanceCycleStart();
        const cycleEnd      = getAttendanceCycleEnd();
        const cycleStartStr = formatDatetimeForSql(cycleStart);
        const cycleEndStr   = formatDatetimeForSql(cycleEnd);

        const [rejectedRows] = await pool.execute(
          `SELECT id FROM attendance 
           WHERE username = ? AND timestamp >= ? AND timestamp < ? AND status = 'Rejected'`,
          [username, cycleStartStr, cycleEndStr]
        );

        if (rejectedRows.length > 0) {
          return res.status(400).json({
            success: false,
            message: 'Pengajuan izin Anda hari ini telah ditolak (Alpha). Anda tidak dapat melakukan Clock In Hadir.',
          });
        }
      }

      if (isPermission) {
        // Hapus pengajuan izin sebelumnya yang berstatus 'Rejected' agar digantikan pengajuan baru
        try {
          await pool.execute(
            `DELETE FROM attendance 
             WHERE username = ? AND status = 'Rejected' 
               AND (type IN ('izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti') OR type LIKE 'izin_%')`,
            [username]
          );
          console.log(`[Permission Cleanup] Pengajuan izin yang ditolak untuk @${username} berhasil dihapus.`);
        } catch (delErr) {
          console.error('[Permission Cleanup Error]', delErr.message);
        }
      }

      const initialStatus = isPermission ? 'Pending' : 'Approved';

      await pool.execute(
        'INSERT INTO attendance (username, type, timestamp, image_path, reason, status) VALUES (?, ?, NOW(), ?, ?, ?)',
        [username, type, savedImagePath, reason ?? '', initialStatus]
      );
    }

    return res.json({ success: true, message: 'Absensi berhasil disimpan' });
  } catch (err) {
    console.error('[Attendance Error]', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================
// ATTENDANCE: Status absensi hari ini (siklus aktif)
// GET /api/attendance/status/:username
// ============================================================
app.get('/api/attendance/status/:username', async (req, res) => {
  const { username } = req.params;
  try {
    const cycleStart    = getAttendanceCycleStart();
    const cycleEnd      = getAttendanceCycleEnd();
    const cycleStartStr = formatDatetimeForSql(cycleStart);
    const cycleEndStr   = formatDatetimeForSql(cycleEnd);

    const [rows] = await pool.execute(
      'SELECT * FROM attendance WHERE username = ? AND timestamp >= ? AND timestamp < ? ORDER BY id ASC',
      [username, cycleStartStr, cycleEndStr]
    );

    let hasClockedIn       = false;
    let hasClockedOut      = false;
    let clockInTime        = '--:--';
    let clockInLocation    = 'Kantor Pusat';
    let clockOutTime       = '--:--';

    let hasPermission      = false;
    let permissionType     = null;
    let permissionStatus   = null; // 'Pending' | 'Approved' | 'Rejected'
    let permissionReason   = null;
    let permissionTime     = null;
    let permissionId       = null;

    for (const row of rows) {
      const type = row.type ?? '';
      const ts   = row.timestamp ? new Date(row.timestamp) : null;
      const status = row.status ?? 'Pending';

      // Deteksi pengajuan izin/sakit
      if (['izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti'].includes(type) ||
          type.startsWith('izin_')) {
        hasPermission    = true;
        permissionId      = row.id;
        permissionType   = type;
        permissionStatus = status; // 'Pending', 'Approved', 'Rejected'
        permissionReason = row.reason ?? '';
        permissionTime   = formatTime(ts);
      } else if (type === 'clock_in') {
        hasClockedIn  = true;
        hasClockedOut = false;
        clockInTime   = formatTime(ts);

        if (row.reason) clockInLocation = row.reason;

        if (row.clock_out) {
          hasClockedOut = true;
          clockOutTime  = formatTime(new Date(row.clock_out));
        }
      } else if (type === 'clock_out') {
        hasClockedOut = true;
        clockOutTime  = row.clock_out
          ? formatTime(new Date(row.clock_out))
          : formatTime(ts);
      }
    }

    // Hitung keterangan kedatangan clock in:
    // < 08:50 => 'Sangat Baik'
    // 08:50 s/d 09:00 => 'Baik'
    // > 09:00 => 'Kurang Baik'
    let clockInKeterangan = null;
    if (hasClockedIn && clockInTime && clockInTime !== '--:--') {
      const parts = clockInTime.split(':');
      const h = parseInt(parts[0], 10);
      const m = parseInt(parts[1], 10);
      const totalMinutes = h * 60 + m;
      if (totalMinutes < 530) {
        clockInKeterangan = 'Sangat Baik';
      } else if (totalMinutes <= 540) {
        clockInKeterangan = 'Baik';
      } else {
        clockInKeterangan = 'Kurang Baik';
      }
    }

    return res.json({
      success           : true,
      hasClockedIn      ,
      hasClockedOut     ,
      clockInTime       ,
      clockInLocation   ,
      clockInKeterangan ,
      clockOutTime      ,
      hasPermission     ,
      permissionId      ,
      permissionType    ,
      permissionStatus  ,
      permissionReason  ,
      permissionTime    ,
      cycleStart        : cycleStart.toISOString(),
      cycleEnd          : cycleEnd.toISOString(),
    });
  } catch (err) {
    console.error('[Status Error]', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================
// START SERVER (BIND 0.0.0.0 agar bisa diakses device lain / HP)
// ============================================================
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n======================================================`);
  console.log(`✅  ProjectWG Express Backend berjalan!`);
  console.log(`🌐  Local:   http://localhost:${PORT}`);
  console.log(`📱  Network: http://0.0.0.0:${PORT} (gunakan IP Komputer di HP)`);
  console.log(`📋  Daftar Endpoint:`);
  console.log(`    - GET  /api/health`);
  console.log(`    - POST /api/login`);
  console.log(`    - GET  /api/user/face/:username`);
  console.log(`    - GET  /api/branches`);
  console.log(`    - POST /api/attendance`);
  console.log(`    - GET  /api/attendance/status/:username`);
  console.log(`======================================================\n`);
});
