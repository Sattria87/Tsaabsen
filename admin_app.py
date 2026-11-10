from flask import Flask, render_template, request, redirect, url_for, flash, send_from_directory, send_file, session, jsonify
import os
import io
import base64
import pymysql
import random
import csv
from datetime import datetime, timedelta
import re
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from reportlab.lib.pagesizes import letter, landscape
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors

# Layanan Acuan Hari Libur Nasional & Hari Kerja Indonesia
try:
    import indonesia_holiday_service
except Exception as e:
    indonesia_holiday_service = None

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS_DIR = os.path.join(BASE_DIR, 'assets')

# Import fallback data logo TSA & script i18n jika file di disk tidak ditemukan / tertutup volume Docker
try:
    from logo_fallback import TSA_LOGO_BASE64, TSA_LOGO_DATA_URI
except Exception:
    TSA_LOGO_BASE64 = None
    TSA_LOGO_DATA_URI = None

try:
    from i18n_fallback import APP_I18N_JS
except Exception:
    APP_I18N_JS = None

# Sinkronisasi otomatis app_i18n.js ke folder assets lokal / volume host VPS
try:
    if not os.path.exists(ASSETS_DIR):
        os.makedirs(ASSETS_DIR, exist_ok=True)
    target_i18n_file = os.path.join(ASSETS_DIR, 'app_i18n.js')
    if APP_I18N_JS and (not os.path.exists(target_i18n_file) or os.path.getsize(target_i18n_file) < 1000):
        with open(target_i18n_file, 'w', encoding='utf-8') as f:
            f.write(APP_I18N_JS)
except Exception:
    pass

app = Flask(__name__, static_folder=ASSETS_DIR, static_url_path='/assets')
app.secret_key = 'projectwg_admin_secret_key_tsa_2026'
app.permanent_session_lifetime = timedelta(days=7)

# ==========================================
# KONFIGURASI DATABASE MYSQL (XAMPP / CLOUD)
# ==========================================
DB_HOST = os.environ.get('DB_HOST', '127.0.0.1')
DB_PORT = int(os.environ.get('DB_PORT', 3306))
DB_USER = os.environ.get('DB_USER', 'root')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')  # Kosongkan jika default XAMPP
DB_NAME = os.environ.get('DB_NAME', 'absensi_wg')
DB_SSL = os.environ.get('DB_SSL', 'false').lower() == 'true' or DB_PORT == 4000

def get_db_connection():
    ssl_config = {'ssl': {}} if DB_SSL else None
    try:
        return pymysql.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
            ssl=ssl_config,
            cursorclass=pymysql.cursors.DictCursor,
            connect_timeout=5
        )
    except Exception as e:
        # Fallback ke 127.0.0.1 / localhost jika koneksi utama gagal
        try:
            return pymysql.connect(
                host='localhost',
                port=3306,
                user='root',
                password='',
                database=DB_NAME,
                cursorclass=pymysql.cursors.DictCursor,
                connect_timeout=2
            )
        except Exception:
            raise e

def ensure_db_schema():
    """Memastikan database absensi_wg beserta seluruh tabel dan data default tersedia di MySQL."""
    ssl_config = {'ssl': {}} if DB_SSL else None
    
    # 1. Pastikan database absensi_wg dibuat terlebih dahulu (konek tanpa nama database)
    try:
        init_conn = pymysql.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            ssl=ssl_config,
            charset='utf8mb4',
            cursorclass=pymysql.cursors.DictCursor,
            connect_timeout=5
        )
        with init_conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{DB_NAME}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
        init_conn.commit()
        init_conn.close()
        print(f"[Schema Info] Database '{DB_NAME}' terverifikasi/berhasil dibuat.")
    except Exception as e:
        print(f"[Schema Notice] Create DB check: {e}")

    # 2. Hubungkan ke database dan pastikan semua tabel inti dibuat
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Tabel 1: Admins (Autentikasi Web Admin)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS admins (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(100) NOT NULL UNIQUE,
                password VARCHAR(255) NOT NULL,
                name VARCHAR(150) NOT NULL,
                email VARCHAR(150),
                role VARCHAR(50) DEFAULT 'Super Admin',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)

        # Pastikan kolom tabel admins bersih
        for col in ['avatar', 'last_login', 'updated_at']:
            cursor.execute("""
                SELECT COUNT(*) AS cnt FROM information_schema.COLUMNS 
                WHERE TABLE_SCHEMA = %s AND TABLE_NAME = 'admins' AND COLUMN_NAME = %s
            """, (DB_NAME, col))
            res_col = cursor.fetchone()
            if res_col and res_col.get('cnt', 0) > 0:
                cursor.execute(f"ALTER TABLE admins DROP COLUMN {col}")

        # Seed akun default admin (admin / 123)
        cursor.execute("SELECT COUNT(*) AS total FROM admins")
        if cursor.fetchone().get('total', 0) == 0:
            cursor.execute("""
                INSERT INTO admins (username, password, name, email, role)
                VALUES (%s, %s, %s, %s, %s)
            """, ('admin', '123', 'Administrator TSA', 'admin@tsa.co.id', 'Super Admin'))
            print("[Schema Info] Akun default admin (admin / 123) berhasil dibuat.")

        # Tabel 2: Branch Companies (Kantor Cabang)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS branch_companies (
                id INT AUTO_INCREMENT PRIMARY KEY,
                branch_name VARCHAR(150) NOT NULL,
                city VARCHAR(100) NOT NULL,
                latitude DECIMAL(10, 8) NOT NULL,
                longitude DECIMAL(11, 8) NOT NULL,
                radius INT DEFAULT 150,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)
        cursor.execute("SELECT COUNT(*) AS total FROM branch_companies")
        if cursor.fetchone().get('total', 0) == 0:
            cursor.execute("""
                INSERT INTO branch_companies (branch_name, city, latitude, longitude, radius) VALUES
                ('Kantor Pusat Surabaya', 'Surabaya', -7.25750000, 112.75210000, 200),
                ('Kantor Cabang Jakarta', 'Jakarta', -6.20880000, 106.84560000, 200)
            """)

        # Tabel 3: Users (Login Mobile & AI)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(100) NOT NULL UNIQUE,
                password VARCHAR(255) NOT NULL,
                name VARCHAR(150) NOT NULL,
                face_image VARCHAR(255) NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)

        # Tabel 4: Employees (Data Karyawan)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS employees (
                id INT AUTO_INCREMENT PRIMARY KEY,
                employee_id VARCHAR(50) NOT NULL UNIQUE,
                name VARCHAR(150) NOT NULL,
                team VARCHAR(100) NOT NULL,
                branch VARCHAR(100) NOT NULL,
                status VARCHAR(50) NOT NULL DEFAULT 'Aktif',
                tag1 VARCHAR(50) NULL,
                tag2 VARCHAR(50) NULL,
                tag3 VARCHAR(50) NULL,
                username VARCHAR(100) NOT NULL UNIQUE,
                password VARCHAR(255) NOT NULL,
                face_image VARCHAR(255) NULL,
                email VARCHAR(150) NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)

        # Tabel 5: Attendance (Presensi & Izin)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS attendance (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(100) NOT NULL,
                type VARCHAR(50) NOT NULL,
                timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                clock_out DATETIME NULL,
                image_path VARCHAR(255) NULL,
                evidence_path VARCHAR(255) NULL,
                reason TEXT NULL,
                status VARCHAR(20) DEFAULT 'Pending',
                INDEX idx_att_user_time (username, timestamp)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)

        # Pastikan kolom reason bertipe TEXT agar GPS dan alasan tidak terpotong
        try:
            cursor.execute("ALTER TABLE attendance MODIFY COLUMN reason TEXT NULL")
        except Exception as r_col_err:
            print(f"[Init DB Reason Column Info]: {r_col_err}")

        # Pastikan kolom evidence_path ada pada tabel attendance
        try:
            cursor.execute("""
                SELECT COUNT(*) AS cnt 
                FROM information_schema.COLUMNS 
                WHERE TABLE_SCHEMA = %s 
                  AND TABLE_NAME = 'attendance' 
                  AND COLUMN_NAME = 'evidence_path'
            """, (DB_NAME,))
            if cursor.fetchone()['cnt'] == 0:
                cursor.execute("ALTER TABLE attendance ADD COLUMN evidence_path VARCHAR(255) NULL AFTER image_path")
        except Exception as ev_col_err:
            print(f"[Init DB Evidence Column Info]: {ev_col_err}")

        # Tabel 6: Vacancies (Lowongan)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS vacancies (
                id INT AUTO_INCREMENT PRIMARY KEY,
                title VARCHAR(150) NOT NULL,
                division VARCHAR(100) NOT NULL,
                branch VARCHAR(100) NOT NULL,
                description TEXT,
                requirements TEXT,
                posted_date DATE NOT NULL,
                status VARCHAR(50) DEFAULT 'Open',
                image VARCHAR(255) DEFAULT 'assets/avatar_mascot_centered.png',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)

        # Tabel 7: App Settings (Kontak HRD & Konfigurasi)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS app_settings (
                setting_key VARCHAR(100) PRIMARY KEY,
                setting_value TEXT NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)
        cursor.execute("SELECT COUNT(*) AS cnt FROM app_settings WHERE setting_key = 'hrd_whatsapp'")
        if cursor.fetchone()['cnt'] == 0:
            cursor.execute("INSERT INTO app_settings (setting_key, setting_value) VALUES ('hrd_whatsapp', '+62 851-9616-7691')")
            cursor.execute("INSERT INTO app_settings (setting_key, setting_value) VALUES ('hrd_name', 'HRD PT TSA')")

        # Tabel 8: Announcements (Broadcast Info/Libur/Acara HRD)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS announcements (
                id INT AUTO_INCREMENT PRIMARY KEY,
                title VARCHAR(150) NOT NULL,
                content TEXT NOT NULL,
                type VARCHAR(50) DEFAULT 'info',
                is_active TINYINT DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)
        cursor.execute("SELECT COUNT(*) AS cnt FROM announcements")
        if cursor.fetchone()['cnt'] == 0:
            cursor.execute("""
                INSERT INTO announcements (title, content, type, is_active)
                VALUES ('Pemberitahuan Sistem Absensi Online', 'Pastikan selalu melakukan Clock In dan Clock Out tepat waktu setiap hari kerja.', 'info', 1)
            """)

        # Seed Data Contoh Pengajuan Cuti (jika belum ada di tabel attendance)
        cursor.execute("""
            SELECT COUNT(*) AS total 
            FROM attendance 
            WHERE type IN ('cuti', 'izin_cuti') OR type LIKE '%cuti%'
        """)
        cuti_check = cursor.fetchone()
        if not cuti_check or cuti_check.get('total', 0) == 0:
            cursor.execute("SELECT username FROM employees ORDER BY id ASC")
            available_emps = [row['username'] for row in cursor.fetchall()]
            
            u_c1 = 'aan' if 'aan' in available_emps else (available_emps[0] if available_emps else 'satriya')
            u_c2 = 'ridho' if 'ridho' in available_emps else (available_emps[1] if len(available_emps) > 1 else 'satriya')
            u_c3 = 'rifky' if 'rifky' in available_emps else (available_emps[2] if len(available_emps) > 2 else 'satriya')
            u_c4 = 'moh' if 'moh' in available_emps else (available_emps[3] if len(available_emps) > 3 else 'satriya')

            cursor.execute("""
                INSERT INTO attendance (username, type, timestamp, reason, status) VALUES
                (%s, 'cuti', NOW(), 'Jenis Cuti: Cuti Tahunan | Periode: 2026-11-10 s/d 2026-11-14 (5 Hari) | Alasan: Cuti tahunan agenda keluarga luar kota', 'Pending'),
                (%s, 'izin_cuti', NOW() - INTERVAL 1 DAY, 'Jenis Cuti: Cuti Menikah | Periode: 2026-11-09 s/d 2026-11-11 (3 Hari) | Alasan: Acara pernikahan saudara kandung', 'Approved'),
                (%s, 'cuti', NOW() - INTERVAL 2 DAY, 'Jenis Cuti: Cuti Khusus / Alasan Penting | Periode: 2026-11-08 s/d 2026-11-09 (2 Hari) | Alasan: Keperluan renovasi dan pindahan rumah', 'Approved'),
                (%s, 'cuti', NOW() - INTERVAL 3 DAY, 'Jenis Cuti: Cuti Melahirkan / Bersalin | Periode: 2026-11-07 s/d 2026-12-07 (30 Hari) | Alasan: Cuti melahirkan dan pemulihan kesehatan', 'Approved')
            """, (u_c1, u_c2, u_c3, u_c4))
            print(f"[Schema Info] Berhasil menambahkan contoh data pengajuan cuti ke database.")

        conn.commit()
        conn.close()
        print("[Schema Info] Seluruh tabel database absensi_wg berhasil diverifikasi.")
    except Exception as e:
        print(f"[Schema Warning] ensure_db_schema: {e}")

# Inisialisasi pengecekan skema saat app dimuat
ensure_db_schema()

def generate_random_employee_id():
    part1 = random.randint(100, 999)
    part2 = random.randint(100, 999)
    part3 = random.randint(10, 99)
    return f"{part1}.{part2}.{part3}"

# ==========================================
# MIDDLEWARE & AUTENTIKASI LOGIN ADMIN
# ==========================================
@app.context_processor
def inject_admin_context():
    """Menyediakan data profil admin dan waktu realtime ke seluruh template Jinja2."""
    now = datetime.now()
    hour = now.hour
    if 5 <= hour < 12:
        greeting = "Good Morning,"
    elif 12 <= hour < 17:
        greeting = "Good Afternoon,"
    elif 17 <= hour < 21:
        greeting = "Good Evening,"
    else:
        greeting = "Good Night,"

    current_day = now.strftime('%A')
    current_date_formatted = now.strftime('%B %d, %Y')
    current_date_display = now.strftime('%A %B %d, %Y')

    # Dapatkan status Hari Kerja / Tanggal Merah / Cuti Bersama
    if indonesia_holiday_service:
        try:
            workday_info = indonesia_holiday_service.get_workday_status(now)
        except Exception:
            workday_info = None
    else:
        workday_info = None

    if not workday_info:
        is_wknd = now.weekday() >= 5
        workday_info = {
            'date_iso': now.strftime('%Y-%m-%d'),
            'time_str': now.strftime('%H:%M:%S'),
            'day_id': ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'][now.weekday()],
            'day_en': current_day,
            'date_id': current_date_formatted,
            'date_en': current_date_formatted,
            'display_id': f"{current_day}, {current_date_formatted}",
            'display_en': f"{current_day}, {current_date_formatted}",
            'is_working_day': not is_wknd,
            'is_weekend': is_wknd,
            'is_holiday': False,
            'is_cuti_bersama': False,
            'status_type': 'weekend' if is_wknd else 'workday',
            'status_label_id': 'Akhir Pekan' if is_wknd else 'Hari Kerja',
            'status_label_en': 'Weekend' if is_wknd else 'Working Day',
            'event_name_id': 'Libur Akhir Pekan' if is_wknd else 'Hari Kerja Aktif',
            'event_name_en': 'Weekend Off' if is_wknd else 'Active Working Day',
            'badge_color': '#64748b' if is_wknd else '#16a34a',
            'badge_class': 'pill-weekend' if is_wknd else 'pill-workday',
            'icon': 'bi-cup-hot-fill' if is_wknd else 'bi-briefcase-fill',
            'upcoming_holidays': []
        }

    return {
        'current_admin': {
            'logged_in': session.get('admin_logged_in', False),
            'id': session.get('admin_id'),
            'username': session.get('admin_username', 'admin'),
            'name': session.get('admin_name', 'Administrator TSA'),
            'role': session.get('admin_role', 'Super Admin'),
            'email': session.get('admin_email', 'admin@tsa.co.id'),
            'avatar': '/assets/tsa_logo.png'
        },
        'tsa_logo_data_uri': TSA_LOGO_DATA_URI,
        'current_day': workday_info['day_id'],
        'current_date_formatted': workday_info['date_id'],
        'current_date_display': workday_info['display_id'],
        'workday_info': workday_info,
        'greeting': greeting,
        'now': now,
    }

@app.route('/api/workday-status')
def api_workday_status():
    """API Realtime: Acuan Hari Kerja, Libur Nasional (Tanggal Merah), & Cuti Bersama Indonesia."""
    now = datetime.now()
    if indonesia_holiday_service:
        try:
            info = indonesia_holiday_service.get_workday_status(now)
        except Exception as e:
            info = {'error': str(e)}
    else:
        is_wknd = now.weekday() >= 5
        info = {
            'date_iso': now.strftime('%Y-%m-%d'),
            'time_str': now.strftime('%H:%M:%S'),
            'day_id': ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'][now.weekday()],
            'day_en': now.strftime('%A'),
            'date_id': now.strftime('%d-%m-%Y'),
            'date_en': now.strftime('%Y-%m-%d'),
            'is_working_day': not is_wknd,
            'is_weekend': is_wknd,
            'is_holiday': False,
            'is_cuti_bersama': False,
            'status_type': 'weekend' if is_wknd else 'workday',
            'status_label_id': 'Akhir Pekan' if is_wknd else 'Hari Kerja',
            'status_label_en': 'Weekend' if is_wknd else 'Working Day',
            'event_name_id': 'Libur Akhir Pekan' if is_wknd else 'Hari Kerja Aktif',
            'event_name_en': 'Weekend Off' if is_wknd else 'Active Working Day',
            'badge_class': 'pill-weekend' if is_wknd else 'pill-workday',
            'icon': 'bi-cup-hot-fill' if is_wknd else 'bi-briefcase-fill'
        }
    resp = jsonify(info)
    resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    return resp

@app.before_request
def require_admin_login():
    """Proteksi route Web Admin: redirect ke /login bila belum terautentikasi."""
    # Rute publik yang boleh diakses tanpa login
    allowed_endpoints = ['login', 'serve_assets', 'static', 'api_workday_status']
    if request.endpoint in allowed_endpoints:
        return
    if request.path.startswith('/assets') or request.path.startswith('/static') or request.path.startswith('/api/') or request.path == '/favicon.ico':
        return

    # Jika session admin belum ada, redirect ke /login
    if not session.get('admin_logged_in'):
        next_url = request.url if request.method == 'GET' and request.path != '/logout' else None
        return redirect(url_for('login', next=next_url))

# ==========================================
# RUTE LOGIN & LOGOUT WEB ADMIN
# ==========================================
@app.route('/login', methods=['GET', 'POST'])
def login():
    # Jika sudah login, langsung alihkan ke homepage
    if session.get('admin_logged_in'):
        return redirect(url_for('index'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '').strip()
        remember = request.form.get('remember')

        if not username or not password:
            flash('Username dan password wajib diisi!', 'danger')
            return render_template('login.html', username=username)

        admin = None
        is_valid = False
        try:
            conn = get_db_connection()
            cursor = conn.cursor()

            # 1. Cek dari tabel admins
            cursor.execute("SELECT * FROM admins WHERE username = %s LIMIT 1", (username,))
            admin = cursor.fetchone()

            # 2. Fallback cek dari tabel users jika belum terdaftar di admins
            if not admin:
                cursor.execute("SELECT * FROM users WHERE username = %s LIMIT 1", (username,))
                user_row = cursor.fetchone()
                if user_row and user_row['username'].lower() in ('admin', 'administrator'):
                    admin = {
                        'id': user_row['id'],
                        'username': user_row['username'],
                        'password': user_row['password'],
                        'name': user_row.get('name') or 'Administrator TSA',
                        'email': 'admin@tsa.co.id',
                        'role': 'Super Admin'
                    }

            # Validasi password
            if admin:
                db_pw = str(admin['password']).strip()
                # Validasi langsung
                if db_pw == password:
                    is_valid = True
                # Fleksibilitas default password admin (123 / admin123)
                elif (db_pw in ('123', 'admin123')) and (password in ('123', 'admin123')):
                    is_valid = True
                else:
                    try:
                        from werkzeug.security import check_password_hash
                        if check_password_hash(db_pw, password):
                            is_valid = True
                    except Exception:
                        pass

            conn.close()
        except Exception as db_err:
            print(f"[Login DB Error]: {db_err}")
            flash(f"Koneksi Database MySQL Gagal ({DB_HOST}:{DB_PORT}): {db_err}", 'danger')
            return render_template('login.html', username=username)

        if admin and is_valid:
            session.permanent = bool(remember)
            session['admin_logged_in'] = True
            session['admin_id'] = admin['id']
            session['admin_username'] = admin['username']
            session['admin_name'] = admin.get('name') or 'Administrator TSA'
            session['admin_role'] = admin.get('role', 'Super Admin')
            session['admin_email'] = admin.get('email', 'admin@tsa.co.id')

            flash(f"Selamat datang kembali, {session['admin_name']}!", 'success')
            next_url = request.args.get('next')
            return redirect(next_url if next_url and next_url.startswith('/') else url_for('index'))
        else:
            flash('Username atau password yang Anda masukkan salah!', 'danger')
            return render_template('login.html', username=username)

    return render_template('login.html')

# ==========================================
# RUTE HOMEPAGE (DASHBOARD UTAMA SESUAI DATABASE REAL)
# ==========================================
@app.route('/')
@app.route('/home')
def index():
    # 1. Waktu & Sapaan Realtime
    now = datetime.now()
    current_hour = now.hour
    if 5 <= current_hour < 12:
        greeting = "Good Morning,"
    elif 12 <= current_hour < 17:
        greeting = "Good Afternoon,"
    elif 17 <= current_hour < 21:
        greeting = "Good Evening,"
    else:
        greeting = "Good Night,"

    current_day = now.strftime('%A')
    current_date_formatted = now.strftime('%B %d, %Y')

    total_employees = 0
    presence_today = 0
    absence_today = 0
    request_obs = 0
    cuti_obs = 0
    daily_on_time = [0] * 30
    daily_late = [0] * 30
    daily_absent = [0] * 30
    labels_3m = ['September', 'Oktober', 'November']
    on_time_3m = [0] * 3
    late_3m = [0] * 3
    absent_3m = [0] * 3
    labels_6m = ['Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November']
    on_time_6m = [0] * 6
    late_6m = [0] * 6
    absent_6m = [0] * 6
    chart_labels = ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct']
    chart_presence = [0, 0, 0, 0, 0, 0]
    chart_absence = [0, 0, 0, 0, 0, 0]
    chart_employees = [0] * 6
    top_attendees = []
    other_attendees = []

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 2. Total Karyawan dari Database
        cursor.execute("SELECT COUNT(*) AS total FROM employees")
        emp_res = cursor.fetchone()
        total_employees = emp_res['total'] if emp_res else 0
        
        # 3. Total Presensi Hadir Hari Ini (clock_in hari ini)
        cursor.execute("""
            SELECT COUNT(DISTINCT username) AS total 
            FROM attendance 
            WHERE DATE(timestamp) = CURDATE() AND (type = 'clock_in' OR type = 'hadir')
        """)
        presence_res = cursor.fetchone()
        presence_today = presence_res['total'] if presence_res else 0
        
        # 4. Total Request Izin / Sakit Hari Ini (Eksklusif Izin & Sakit, cuti dipisah ke kartu khusus)
        cursor.execute("""
            SELECT COUNT(*) AS total 
            FROM attendance 
            WHERE DATE(timestamp) = CURDATE() 
              AND (
                  (reason IS NOT NULL AND reason != '') 
                  OR type IN ('izin', 'sakit', 'sick_leave', 'necessity_leave', 'izin_sakit', 'izin_keperluan') 
                  OR (type LIKE 'izin_%' AND type NOT LIKE '%cuti%')
              )
              AND type NOT IN ('clock_in', 'clock_out', 'hadir', 'cuti', 'izin_cuti')
              AND type NOT LIKE '%cuti%'
        """)
        obs_res = cursor.fetchone()
        request_obs = obs_res['total'] if obs_res else 0
        if request_obs == 0:
            # Fallback jika hari ini 0: tampilkan akumulasi izin/sakit aktif di database
            cursor.execute("""
                SELECT COUNT(*) AS total 
                FROM attendance 
                WHERE (
                    type IN ('izin', 'sakit', 'sick_leave', 'necessity_leave', 'izin_sakit', 'izin_keperluan') 
                    OR (type LIKE 'izin_%' AND type NOT LIKE '%cuti%')
                )
                AND type NOT IN ('clock_in', 'clock_out', 'hadir', 'cuti', 'izin_cuti')
                AND type NOT LIKE '%cuti%'
            """)
            fb_obs = cursor.fetchone()
            request_obs = fb_obs['total'] if fb_obs else 0

        # 4b. Total Request Cuti Hari Ini / Keseluruhan dari Database
        cursor.execute("""
            SELECT COUNT(*) AS total 
            FROM attendance 
            WHERE DATE(timestamp) = CURDATE() 
              AND (type IN ('cuti', 'izin_cuti') OR type LIKE '%cuti%')
        """)
        cuti_res = cursor.fetchone()
        cuti_obs = cuti_res['total'] if cuti_res else 0
        if cuti_obs == 0:
            # Fallback jika hari ini 0: tampilkan total data pengajuan cuti yang ada di database
            cursor.execute("""
                SELECT COUNT(*) AS total 
                FROM attendance 
                WHERE (type IN ('cuti', 'izin_cuti') OR type LIKE '%cuti%')
            """)
            fb_cuti = cursor.fetchone()
            cuti_obs = fb_cuti['total'] if fb_cuti else 0
        
        # 5. Ketidakhadiran Hari Ini (karyawan yang belum clock_in hari ini)
        absence_today = max(0, total_employees - presence_today)
        
        # 6a. Rekap Kehadiran 6 Bulan & 3 Bulan Real Database
        # Aturan User: Jika pada bulan tersebut belum ada yang hadir, maka TIDAK HADIR SEMUA!
        indo_month_names = {
            1: 'Januari', 2: 'Februari', 3: 'Maret', 4: 'April', 5: 'Mei', 6: 'Juni',
            7: 'Juli', 8: 'Agustus', 9: 'September', 10: 'Oktober', 11: 'November', 12: 'Desember'
        }
        monthly_att_map = {}
        try:
            cursor.execute("""
                SELECT 
                    YEAR(timestamp) AS yr,
                    MONTH(timestamp) AS mo,
                    SUM(CASE WHEN (type = 'clock_in' OR type = 'hadir') AND TIME(timestamp) <= '08:30:00' THEN 1 ELSE 0 END) AS on_time_cnt,
                    SUM(CASE WHEN (type = 'clock_in' OR type = 'hadir') AND TIME(timestamp) > '08:30:00' THEN 1 ELSE 0 END) AS late_cnt
                FROM attendance
                GROUP BY YEAR(timestamp), MONTH(timestamp)
            """)
            for row in cursor.fetchall():
                key = (int(row['yr']), int(row['mo']))
                monthly_att_map[key] = {
                    'on_time': int(row['on_time_cnt'] or 0),
                    'late': int(row['late_cnt'] or 0)
                }
        except Exception as e:
            print(f"[Monthly Att Query Info]: {e}")

        # Bangun array 6 bulan terakhir s/d bulan ini
        labels_6m = []
        on_time_6m = []
        late_6m = []
        absent_6m = []
        now_dt = datetime.datetime.now()
        for i in range(5, -1, -1):
            y = now_dt.year
            m = now_dt.month - i
            while m <= 0:
                m += 12
                y -= 1
            labels_6m.append(indo_month_names.get(m, str(m)))
            k = (y, m)
            if k in monthly_att_map and (monthly_att_map[k]['on_time'] > 0 or monthly_att_map[k]['late'] > 0):
                ot = monthly_att_map[k]['on_time']
                lt = monthly_att_map[k]['late']
                ab = max(0, total_employees - ot - lt)
                on_time_6m.append(ot)
                late_6m.append(lt)
                absent_6m.append(ab)
            else:
                # Belum ada yang hadir pada bulan ini -> Hadir: 0, Terlambat: 0, Tidak Hadir: Semua Karyawan!
                on_time_6m.append(0)
                late_6m.append(0)
                absent_6m.append(total_employees)

        # 3 Bulan adalah 3 bulan terakhir dari 6 bulan
        labels_3m = labels_6m[-3:]
        on_time_3m = on_time_6m[-3:]
        late_3m = late_6m[-3:]
        absent_3m = absent_6m[-3:]

        # 6b. Rekap Kehadiran Harian Bulan Berjalan (1-30) Real Database
        # Aturan User: Jika pada tanggal tersebut belum ada yang hadir, maka TIDAK HADIR SEMUA!
        daily_on_time = []
        daily_late = []
        daily_absent = []
        daily_att_map = {}
        try:
            cursor.execute("""
                SELECT 
                    DAY(timestamp) AS d,
                    SUM(CASE WHEN (type = 'clock_in' OR type = 'hadir') AND TIME(timestamp) <= '08:30:00' THEN 1 ELSE 0 END) AS on_time_cnt,
                    SUM(CASE WHEN (type = 'clock_in' OR type = 'hadir') AND TIME(timestamp) > '08:30:00' THEN 1 ELSE 0 END) AS late_cnt
                FROM attendance
                WHERE YEAR(timestamp) = YEAR(CURDATE()) AND MONTH(timestamp) = MONTH(CURDATE())
                GROUP BY DAY(timestamp)
            """)
            for row in cursor.fetchall():
                daily_att_map[int(row['d'])] = {
                    'on_time': int(row['on_time_cnt'] or 0),
                    'late': int(row['late_cnt'] or 0)
                }
        except Exception as e:
            print(f"[Daily Att Query Info]: {e}")

        for d in range(1, 31):
            if d in daily_att_map and (daily_att_map[d]['on_time'] > 0 or daily_att_map[d]['late'] > 0):
                ot = daily_att_map[d]['on_time']
                lt = daily_att_map[d]['late']
                ab = max(0, total_employees - ot - lt)
                daily_on_time.append(ot)
                daily_late.append(lt)
                daily_absent.append(ab)
            else:
                # Belum ada yang hadir pada tanggal ini -> Hadir Tepat Waktu: 0, Terlambat: 0, Tidak Hadir: Semua Karyawan!
                daily_on_time.append(0)
                daily_late.append(0)
                daily_absent.append(total_employees)

        # 7. Quick Attendance List Karyawan Real dari Database
        cursor.execute("""
            SELECT 
                e.id, e.employee_id, e.name, e.team, e.branch, e.status, e.username, e.face_image,
                a.type AS today_type, 
                TIME_FORMAT(a.max_ts, '%H:%i') AS today_clock_in,
                a.reason AS today_reason
            FROM employees e
            LEFT JOIN (
                SELECT username, 
                       SUBSTRING_INDEX(GROUP_CONCAT(type ORDER BY id DESC SEPARATOR '|||'), '|||', 1) AS type,
                       MAX(timestamp) AS max_ts,
                       SUBSTRING_INDEX(GROUP_CONCAT(COALESCE(reason, '') ORDER BY id DESC SEPARATOR '|||'), '|||', 1) AS reason
                FROM attendance
                WHERE DATE(timestamp) = CURDATE()
                  AND (type IN ('clock_in', 'hadir', 'clock_out') OR LOWER(COALESCE(status, '')) IN ('approved', 'disetujui'))
                GROUP BY username
            ) a ON e.username = a.username
            ORDER BY (CASE WHEN a.type = 'clock_in' THEN 1 WHEN a.type IS NOT NULL THEN 2 ELSE 3 END) ASC, e.id ASC
        """)
        attendance_employees = cursor.fetchall()
        for emp in attendance_employees:
            raw_type = (emp.get('today_type') or '').lower()
            if 'cuti' in raw_type:
                emp['today_type'] = 'cuti'
            elif 'sakit' in raw_type:
                emp['today_type'] = 'sakit'
            elif raw_type in ('izin', 'izin_sakit', 'izin_keperluan') or raw_type.startswith('izin'):
                emp['today_type'] = 'izin'

        top_attendees = attendance_employees[:3]
        other_attendees = attendance_employees[3:8]

        # Ambil pengaturan Kontak HRD
        hrd_whatsapp = '+62 851-9616-7691'
        hrd_name = 'HRD PT TSA'
        try:
            cursor.execute("SELECT setting_key, setting_value FROM app_settings WHERE setting_key IN ('hrd_whatsapp', 'hrd_name')")
            for row in cursor.fetchall():
                if row['setting_key'] == 'hrd_whatsapp':
                    hrd_whatsapp = row['setting_value']
                elif row['setting_key'] == 'hrd_name':
                    hrd_name = row['setting_value']
        except Exception:
            pass

        # 8. Data Pengumuman HRD (Aktif & Riwayat History Notifikasi)
        announcements = []
        announcement_history = []
        try:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS announcements (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    content TEXT NOT NULL,
                    type VARCHAR(50) DEFAULT 'info',
                    is_active TINYINT(1) DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_ann_active (is_active)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
            """)
            cursor.execute("""
                SELECT id, title, content, type, is_active,
                       DATE_FORMAT(created_at, '%d %b %Y %H:%i') AS formatted_date
                FROM announcements
                WHERE is_active = 1
                ORDER BY id DESC
            """)
            announcements = cursor.fetchall()

            cursor.execute("""
                SELECT id, title, content, type, is_active,
                       DATE_FORMAT(created_at, '%d %b %Y %H:%i') AS formatted_date
                FROM announcements
                ORDER BY id DESC
                LIMIT 50
            """)
            announcement_history = cursor.fetchall()
        except Exception as ann_err:
            print(f"[Announcements Fetch Error]: {ann_err}")
        finally:
            try:
                conn.close()
            except Exception:
                pass

    except Exception as dash_err:
        print(f"[Dashboard DB Error]: {dash_err}")
    
    return render_template(
        'homepage.html',
        greeting=greeting,
        current_day=current_day,
        current_date_formatted=current_date_formatted,
        total_employees=total_employees,
        presence_today=presence_today,
        absence_today=absence_today,
        request_obs=request_obs,
        cuti_obs=cuti_obs,
        chart_labels=chart_labels,
        chart_presence=chart_presence,
        chart_absence=chart_absence,
        chart_employees=chart_employees,
        daily_on_time=daily_on_time,
        daily_late=daily_late,
        daily_absent=daily_absent,
        labels_3m=labels_3m,
        on_time_3m=on_time_3m,
        late_3m=late_3m,
        absent_3m=absent_3m,
        labels_6m=labels_6m,
        on_time_6m=on_time_6m,
        late_6m=late_6m,
        absent_6m=absent_6m,
        top_attendees=top_attendees,
        other_attendees=other_attendees,
        hrd_whatsapp=hrd_whatsapp if 'hrd_whatsapp' in locals() else '+62 851-9616-7691',
        hrd_name=hrd_name if 'hrd_name' in locals() else 'HRD PT TSA',
        announcements=announcements if 'announcements' in locals() else [],
        announcement_history=announcement_history if 'announcement_history' in locals() else []
    )

# ==========================================
# RUTE MANAJEMEN KARYAWAN (EMPLOYEE)
# ==========================================
@app.route('/employee')
@app.route('/employees')
def employee_management():
    search_query = request.args.get('search', '').strip()
    conn = get_db_connection()
    cursor = conn.cursor()
    
    if search_query:
        cursor.execute("""
            SELECT * FROM employees 
            WHERE name LIKE %s OR employee_id LIKE %s OR username LIKE %s OR team LIKE %s OR branch LIKE %s
            ORDER BY name ASC
        """, (f"%{search_query}%", f"%{search_query}%", f"%{search_query}%", f"%{search_query}%", f"%{search_query}%"))
    else:
        cursor.execute("SELECT * FROM employees ORDER BY name ASC")
        
    employees = cursor.fetchall()
    
    cursor.execute("SELECT branch_name FROM branch_companies ORDER BY id ASC")
    branches = [r['branch_name'] for r in cursor.fetchall()]
    if not branches:
        branches = ['TUNGGAL SAHABAT ABADI', 'Decoy']
    conn.close()
    
    now = datetime.now()
    current_date_formatted = f"{now.strftime('%A')} {now.strftime('%B')} {now.day}, {now.year}"

    return render_template('admin_dashboard.html', employees=employees, search_query=search_query, branches=branches, current_date_formatted=current_date_formatted)

@app.route('/assets/<path:filename>')
def serve_assets(filename):
    # 1. Penanganan khusus & aman untuk app_i18n.js (Internationalization)
    if 'app_i18n' in filename.lower():
        resp = None
        for test_dir in [ASSETS_DIR, os.path.join(app.root_path, 'assets')]:
            test_path = os.path.join(test_dir, 'app_i18n.js')
            if os.path.isfile(test_path):
                resp = send_file(test_path, mimetype='application/javascript')
                break
        if not resp and APP_I18N_JS:
            resp = app.response_class(APP_I18N_JS, mimetype='application/javascript')
        if resp:
            resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
            resp.headers['Pragma'] = 'no-cache'
            resp.headers['Expires'] = '0'
            return resp

    # 2. Cek langsung di direktori ASSETS_DIR
    file_path = os.path.join(ASSETS_DIR, filename)
    if os.path.isfile(file_path):
        return send_from_directory(ASSETS_DIR, filename)

    # 3. Cek di app.root_path/assets jika berbeda
    root_assets = os.path.join(app.root_path, 'assets')
    if os.path.isfile(os.path.join(root_assets, filename)):
        return send_from_directory(root_assets, filename)

    # 4. Pencarian case-insensitive untuk kompatibilitas sistem Linux
    base_name = os.path.basename(filename).lower()
    sub_dir = os.path.dirname(filename)
    for s_dir in [ASSETS_DIR, root_assets]:
        dir_to_check = os.path.join(s_dir, sub_dir) if sub_dir else s_dir
        if os.path.isdir(dir_to_check):
            try:
                for existing_file in os.listdir(dir_to_check):
                    if existing_file.lower() == base_name:
                        return send_from_directory(dir_to_check, existing_file)
            except Exception:
                pass

    # 5. Fallback proteksi tinggi khusus logo TSA jika file fisik tidak ada di disk
    if 'tsa_logo' in filename.lower() and TSA_LOGO_BASE64:
        try:
            logo_bytes = base64.b64decode(TSA_LOGO_BASE64)
            return send_file(
                io.BytesIO(logo_bytes),
                mimetype='image/png',
                download_name='tsa_logo.png'
            )
        except Exception:
            pass

    return send_from_directory(ASSETS_DIR, filename)

@app.route('/add', methods=['POST'])
def add_employee():
    name = request.form.get('name')
    team = request.form.get('team')
    branch = request.form.get('branch')
    status = request.form.get('status')
    username = request.form.get('username')
    password = request.form.get('password')
    face_image = request.form.get('face_image')
    tags = request.form.get('tags', '').split(',')

    if not name or not team or not branch or not status or not username or not password:
        flash('Semua kolom data karyawan wajib diisi!', 'danger')
        return redirect(url_for('employee_management'))

    employee_id = generate_random_employee_id()
    db_image_path = None

    # Simpan file gambar jika admin mengunggah/mengambil foto saat pembuatan akun (Opsional)
    if face_image and face_image.strip():
        assets_dir = os.path.join(app.root_path, 'assets', 'foto_karyawan')
        os.makedirs(assets_dir, exist_ok=True)
        filename = f"{employee_id.replace('.', '_')}_{username}.jpg"
        filepath = os.path.join(assets_dir, filename)

        try:
            raw_b64 = face_image
            if ',' in face_image:
                raw_b64 = face_image.split(',', 1)[1]
            with open(filepath, 'wb') as f:
                f.write(base64.b64decode(raw_b64))
            db_image_path = f"assets/foto_karyawan/{filename}"
        except Exception as img_err:
            print(f"Peringatan: Gagal menyimpan file fisik gambar ke assets/foto_karyawan: {img_err}")

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # 1. Simpan ke tabel employees (Web Dashboard)
        cursor.execute(
            """INSERT INTO employees (employee_id, name, team, branch, status, tag1, tag2, tag3, username, password, face_image) 
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (employee_id, name, team, branch, status, 
             tags[0].strip() if len(tags)>0 and tags[0].strip() else None, 
             tags[1].strip() if len(tags)>1 and tags[1].strip() else None, 
             tags[2].strip() if len(tags)>2 and tags[2].strip() else None, 
             username, password, db_image_path)
        )
        
        # 2. Simpan ke tabel users (Agar bisa login di Aplikasi Flutter & Acuan AI Face Recognition)
        cursor.execute(
            "INSERT INTO users (username, password, name, face_image) VALUES (%s, %s, %s, %s)",
            (username, password, name, db_image_path)
        )
        
        conn.commit()
        if db_image_path:
            flash(f'Karyawan "{name}" berhasil ditambahkan beserta foto acuan AI!', 'success')
        else:
            flash(f'Karyawan "{name}" berhasil ditambahkan! Foto acuan AI akan direkam saat karyawan pertama kali login di HP.', 'success')
    except pymysql.err.IntegrityError:
        flash('Error: Username tersebut sudah terdaftar!', 'danger')
    except Exception as e:
        flash(f'Terjadi kesalahan: {e}', 'danger')
    finally:
        conn.close()

    return redirect(url_for('employee_management'))

# ==========================================
# BULK IMPORT & EXPORT KARYAWAN DARI EXCEL
# ==========================================
@app.route('/employee/template-excel')
@app.route('/employees/template-excel')
def download_employee_template():
    """Menghasilkan file template Excel (.xlsx) resmi untuk import data karyawan massal."""
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Template Karyawan"

    # Styling definitions
    title_font = Font(name="Calibri", size=13, bold=True, color="131B3E")
    subtitle_font = Font(name="Calibri", size=9, italic=True, color="4B5563")
    header_fill = PatternFill(start_color="131B3E", end_color="131B3E", fill_type="solid")
    header_font = Font(name="Calibri", size=10, bold=True, color="FFFFFF")
    sample_fill = PatternFill(start_color="F8FAFC", end_color="F8FAFC", fill_type="solid")
    border_thin = Side(border_style="thin", color="D1D5DB")
    cell_border = Border(left=border_thin, right=border_thin, top=border_thin, bottom=border_thin)
    center_align = Alignment(horizontal="center", vertical="center", wrap_text=True)
    left_align = Alignment(horizontal="left", vertical="center")

    # Baris Judul & Catatan Petunjuk
    ws.merge_cells("A1:I1")
    ws["A1"] = "TEMPLATE DATA KARYAWAN TSA - IMPORT MASSAL (BULKY)"
    ws["A1"].font = title_font
    ws["A1"].alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 24

    ws.merge_cells("A2:I2")
    ws["A2"] = "Petunjuk: Kolom bertanda (*) Wajib diisi. Kolom 'ID Karyawan' boleh dikosongkan (otomatis dibuatkan sistem). Status: Active / Inactive."
    ws["A2"].font = subtitle_font
    ws["A2"].alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[2].height = 18

    # Definisi Kolom Header (Baris 4)
    headers = [
        ("No", 8),
        ("ID Karyawan", 18),
        ("Nama Lengkap (*)", 26),
        ("Divisi / Tim (*)", 22),
        ("Kantor Cabang (*)", 26),
        ("Status", 14),
        ("Username (*)", 20),
        ("Password (*)", 18),
        ("Email", 26)
    ]

    ws.row_dimensions[4].height = 26
    for col_idx, (header_text, width) in enumerate(headers, start=1):
        cell = ws.cell(row=4, column=col_idx, value=header_text)
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = center_align
        cell.border = cell_border
        col_letter = openpyxl.utils.get_column_letter(col_idx)
        ws.column_dimensions[col_letter].width = width

    # Dapatkan contoh kantor cabang dari database jika tersedia
    sample_branch = "Kantor Pusat Surabaya"
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT branch_name FROM branch_companies ORDER BY id ASC LIMIT 1")
            b_row = cur.fetchone()
            if b_row and b_row.get('branch_name'):
                sample_branch = b_row['branch_name']
        conn.close()
    except Exception:
        pass

    # Contoh baris data untuk panduan pengguna
    sample_rows = [
        (1, "101.202.01", "Budi Santoso", "IT Support", sample_branch, "Active", "budi.santoso", "tsa123", "budi@tsa.co.id"),
        (2, "", "Siti Nurhaliza", "Human Resources", sample_branch, "Active", "siti.hr", "tsa123", "siti@tsa.co.id"),
        (3, "101.202.03", "Kevin Pratama", "Marketing", sample_branch, "Active", "kevin.sales", "tsa123", "kevin@tsa.co.id")
    ]

    for offset, row_data in enumerate(sample_rows, start=5):
        ws.row_dimensions[offset].height = 22
        for col_idx, val in enumerate(row_data, start=1):
            cell = ws.cell(row=offset, column=col_idx, value=val)
            cell.font = Font(name="Calibri", size=10)
            cell.fill = sample_fill
            cell.border = cell_border
            if col_idx in [1, 2, 6]:
                cell.alignment = center_align
            else:
                cell.alignment = left_align

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return send_file(
        buf,
        as_attachment=True,
        download_name="Template_Import_Karyawan_TSA.xlsx",
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

@app.route('/employee/import-excel', methods=['POST'])
@app.route('/employees/import-excel', methods=['POST'])
def import_employees_excel():
    """Memproses unggahan file Excel dan mengimpor data karyawan secara bulky."""
    if 'file' not in request.files:
        flash('Tidak ada file Excel yang dipilih untuk diunggah!', 'danger')
        return redirect(url_for('employee_management'))

    file = request.files['file']
    if not file or file.filename == '':
        flash('Silakan pilih file Excel (.xlsx atau .xls) terlebih dahulu!', 'danger')
        return redirect(url_for('employee_management'))

    filename = file.filename.lower()
    if not (filename.endswith('.xlsx') or filename.endswith('.xls')):
        flash('Format file tidak didukung! Harap unggah file spreadsheet Excel dengan ekstensi .xlsx atau .xls.', 'danger')
        return redirect(url_for('employee_management'))

    on_duplicate = request.form.get('on_duplicate', 'skip').strip().lower()

    try:
        wb = openpyxl.load_workbook(file, data_only=True)
        ws = wb.active
    except Exception as e:
        flash(f'Gagal membaca file Excel: {e}', 'danger')
        return redirect(url_for('employee_management'))

    # Deteksi otomatis baris header pada rentang 1-15 baris pertama
    header_row_idx = None
    col_mapping = {}

    for r in range(1, 15):
        row_vals = [str(ws.cell(row=r, column=c).value or '').strip().lower() for c in range(1, 25)]
        has_name = any('nama' in v or 'name' in v for v in row_vals)
        has_other = any(k in ' '.join(row_vals) for k in ['user', 'divisi', 'team', 'cabang', 'branch', 'id', 'nip', 'password'])
        if has_name and has_other:
            header_row_idx = r
            for c in range(1, len(row_vals) + 1):
                val = str(ws.cell(row=r, column=c).value or '').strip().lower()
                if not val:
                    continue
                if 'nama' in val or val == 'name' or 'full name' in val:
                    col_mapping.setdefault('name', c)
                elif 'user' in val:
                    col_mapping.setdefault('username', c)
                elif 'pass' in val or 'sandi' in val:
                    col_mapping.setdefault('password', c)
                elif 'divisi' in val or 'team' in val or 'tim' in val or 'dept' in val:
                    col_mapping.setdefault('team', c)
                elif 'cabang' in val or 'branch' in val or 'kantor' in val or 'lokasi' in val:
                    col_mapping.setdefault('branch', c)
                elif 'status' in val:
                    col_mapping.setdefault('status', c)
                elif 'nip' in val or 'id karyawan' in val or 'nik' in val or (val.startswith('id') and 'karyawan' in val):
                    col_mapping.setdefault('employee_id', c)
                elif 'email' in val or 'surel' in val:
                    col_mapping.setdefault('email', c)
            break

    if not header_row_idx or 'name' not in col_mapping:
        flash('Format kolom Excel tidak dikenali! Pastikan terdapat kolom "Nama Lengkap" dan "Username" sesuai Template Resmi.', 'danger')
        return redirect(url_for('employee_management'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Ambil daftar kantor cabang yang valid di database
        cursor.execute("SELECT branch_name FROM branch_companies ORDER BY id ASC")
        db_branches = [r['branch_name'] for r in cursor.fetchall()]
        default_branch = db_branches[0] if db_branches else 'Kantor Pusat Surabaya'

        # Load seluruh karyawan yang sudah ada untuk pengecekan cepat duplikasi
        cursor.execute("SELECT LOWER(username) AS u, employee_id FROM employees")
        existing_emp_map = {r['u']: r['employee_id'] for r in cursor.fetchall()}
        
        cursor.execute("SELECT employee_id FROM employees")
        all_emp_ids = set(r['employee_id'] for r in cursor.fetchall())

        success_count = 0
        updated_count = 0
        skipped_count = 0
        row_errors = []

        def get_cell_str(row_idx, col_key, default_val=''):
            c_idx = col_mapping.get(col_key)
            if not c_idx:
                return default_val
            val = ws.cell(row=row_idx, column=c_idx).value
            if val is None:
                return default_val
            return str(val).strip()

        max_row = ws.max_row
        for r in range(header_row_idx + 1, max_row + 1):
            name = get_cell_str(r, 'name')
            username = get_cell_str(r, 'username')
            password = get_cell_str(r, 'password')
            team = get_cell_str(r, 'team')
            branch = get_cell_str(r, 'branch')
            status = get_cell_str(r, 'status')
            emp_id = get_cell_str(r, 'employee_id')
            email = get_cell_str(r, 'email')

            # Lewati baris yang kosong total
            if not name and not username and not team:
                continue

            if not name:
                row_errors.append(f"Baris {r}: Nama Lengkap kosong")
                continue

            # Jika username kosong di Excel, buat otomatis dari nama
            if not username:
                clean_name = ''.join(ch for ch in name.lower() if ch.isalnum())
                username = clean_name if clean_name else f"user{r}"
                base_u = username
                counter = 1
                while username.lower() in existing_emp_map:
                    username = f"{base_u}{counter}"
                    counter += 1

            if not password:
                password = '123'  # Password default standar

            if not team:
                team = 'Operasional'

            if not branch:
                branch = default_branch
            else:
                # Cocokkan case-insensitive dengan kantor cabang di DB jika ada
                matched_b = next((b for b in db_branches if b.lower() == branch.lower()), branch)
                branch = matched_b

            # Normalisasi status (Active / Inactive)
            if status.lower() in ['active', 'aktif', '1', 'true', 'ya', 'a']:
                status = 'Active'
            elif status.lower() in ['inactive', 'nonaktif', 'tidak aktif', '0', 'false', 'i']:
                status = 'Inactive'
            else:
                status = 'Active'

            email_val = email if email else None
            u_key = username.lower()

            if u_key in existing_emp_map:
                if on_duplicate == 'update':
                    try:
                        cursor.execute("""
                            UPDATE employees 
                            SET name = %s, team = %s, branch = %s, status = %s, password = %s, email = COALESCE(%s, email)
                            WHERE LOWER(username) = %s
                        """, (name, team, branch, status, password, email_val, u_key))

                        cursor.execute("""
                            UPDATE users 
                            SET name = %s, password = %s
                            WHERE LOWER(username) = %s
                        """, (name, password, u_key))
                        updated_count += 1
                    except Exception as err:
                        row_errors.append(f"Baris {r} (@{username}): Gagal update ({err})")
                else:
                    skipped_count += 1
            else:
                # Siapkan ID karyawan unik
                if not emp_id or emp_id in all_emp_ids:
                    emp_id = generate_random_employee_id()
                    while emp_id in all_emp_ids:
                        emp_id = generate_random_employee_id()

                try:
                    cursor.execute("""
                        INSERT INTO employees (employee_id, name, team, branch, status, username, password, email)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """, (emp_id, name, team, branch, status, username, password, email_val))

                    cursor.execute("""
                        INSERT INTO users (username, password, name)
                        VALUES (%s, %s, %s)
                        ON DUPLICATE KEY UPDATE name = VALUES(name), password = VALUES(password)
                    """, (username, password, name))

                    existing_emp_map[u_key] = emp_id
                    all_emp_ids.add(emp_id)
                    success_count += 1
                except Exception as err:
                    row_errors.append(f"Baris {r} (@{username}): Gagal insert ({err})")

        conn.commit()
        conn.close()

        # Bentuk pesan notifikasi flash
        if success_count > 0 or updated_count > 0:
            msg = f"Bulk Import Berhasil: <b>{success_count}</b> karyawan baru ditambahkan"
            if updated_count > 0:
                msg += f", <b>{updated_count}</b> diperbarui"
            if skipped_count > 0:
                msg += f", <b>{skipped_count}</b> dilewati (sudah terdaftar)"
            msg += "."
            if row_errors:
                msg += f" Catatan ({len(row_errors)}): {'; '.join(row_errors[:3])}"
            flash(msg, 'success')
        elif skipped_count > 0:
            flash(f"Semua data ({skipped_count} karyawan) dilewati karena username sudah terdaftar. Gunakan opsi 'Perbarui data jika username sudah ada' jika ingin menimpa data.", 'warning')
        else:
            err_msg = f": {'; '.join(row_errors[:3])}" if row_errors else "."
            flash(f"Tidak ada data karyawan yang berhasil diimpor{err_msg}", 'danger')

    except Exception as e:
        flash(f'Terjadi kendala saat memproses database: {e}', 'danger')

    return redirect(url_for('employee_management'))

@app.route('/employee/export-excel')
@app.route('/employees/export-excel')
def export_employees_excel():
    """Mengekspor seluruh data karyawan aktif & nonaktif ke dalam file Excel (.xlsx)."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM employees ORDER BY name ASC")
        employees = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f'Gagal mengambil data karyawan: {e}', 'danger')
        return redirect(url_for('employee_management'))

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Data Karyawan TSA"

    # Styling definitions
    title_font = Font(name="Calibri", size=13, bold=True, color="131B3E")
    header_fill = PatternFill(start_color="131B3E", end_color="131B3E", fill_type="solid")
    header_font = Font(name="Calibri", size=10, bold=True, color="FFFFFF")
    border_thin = Side(border_style="thin", color="D1D5DB")
    cell_border = Border(left=border_thin, right=border_thin, top=border_thin, bottom=border_thin)
    center_align = Alignment(horizontal="center", vertical="center")
    left_align = Alignment(horizontal="left", vertical="center")

    # Baris Judul
    ws.merge_cells("A1:J1")
    ws["A1"] = f"DAFTAR DATA KARYAWAN TSA - DIEKSPOR PADA {datetime.now().strftime('%d/%m/%Y %H:%M')}"
    ws["A1"].font = title_font
    ws["A1"].alignment = left_align
    ws.row_dimensions[1].height = 24

    headers = [
        ("No", 8),
        ("ID Karyawan", 18),
        ("Nama Lengkap", 26),
        ("Divisi / Tim", 22),
        ("Kantor Cabang", 26),
        ("Status", 14),
        ("Username", 20),
        ("Password", 18),
        ("Email", 26),
        ("Acuan AI", 16)
    ]

    ws.row_dimensions[3].height = 26
    for col_idx, (header_text, width) in enumerate(headers, start=1):
        cell = ws.cell(row=3, column=col_idx, value=header_text)
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = center_align
        cell.border = cell_border
        col_letter = openpyxl.utils.get_column_letter(col_idx)
        ws.column_dimensions[col_letter].width = width

    for row_idx, emp in enumerate(employees, start=4):
        ws.row_dimensions[row_idx].height = 22
        ai_status = "Terdaftar" if emp.get('face_image') else "Belum Ada"
        row_data = [
            row_idx - 3,
            emp.get('employee_id', ''),
            emp.get('name', ''),
            emp.get('team', ''),
            emp.get('branch', ''),
            emp.get('status', 'Active'),
            emp.get('username', ''),
            emp.get('password', ''),
            emp.get('email', '') or '',
            ai_status
        ]
        for col_idx, val in enumerate(row_data, start=1):
            cell = ws.cell(row=row_idx, column=col_idx, value=val)
            cell.font = Font(name="Calibri", size=10)
            cell.border = cell_border
            if col_idx in [1, 2, 6, 10]:
                cell.alignment = center_align
            else:
                cell.alignment = left_align

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return send_file(
        buf,
        as_attachment=True,
        download_name=f"Data_Karyawan_TSA_{datetime.now().strftime('%Y%m%d')}.xlsx",
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

@app.route('/detail/<int:id>')
def detail_employee(id):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT * FROM employees WHERE id = %s", (id,))
    employee = cursor.fetchone()
    
    if not employee:
        conn.close()
        flash('Data karyawan tidak ditemukan!', 'danger')
        return redirect(url_for('employee_management'))
    
    username = employee.get('username') or ''
    
    # Kueri HANYA aktivitas milik karyawan tersebut (tidak tergabung dengan karyawan lain)
    cursor.execute("""
        SELECT 
            id, username, type, timestamp, clock_out, image_path, evidence_path, reason,
            COALESCE(status, 'Approved') AS status,
            DATE_FORMAT(timestamp, '%%d %%b %%Y') AS formatted_date,
            TIME_FORMAT(timestamp, '%%H:%%i') AS formatted_time,
            TIME_FORMAT(clock_out, '%%H:%%i') AS formatted_clock_out
        FROM attendance 
        WHERE username = %s 
        ORDER BY timestamp DESC, id DESC
    """, (username,))
    all_attendance = cursor.fetchall()
    conn.close()
    
    # Pisahkan aktivitas agar tidak tergabung: Clock In, Clock Out, dan Izin
    clock_in_list = []
    clock_out_list = []
    permission_list = []
    
    for att in all_attendance:
        att_type = (att['type'] or '').lower()
        if att_type == 'clock_in':
            clock_in_list.append(att)
        elif att_type == 'clock_out':
            clock_out_list.append(att)
        elif 'izin' in att_type or 'sakit' in att_type or 'cuti' in att_type or (att['reason'] and att_type not in ('clock_in', 'clock_out', 'hadir')):
            if 'sakit' in att_type:
                att['display_type'] = 'Sakit'
            elif 'keperluan' in att_type:
                att['display_type'] = 'Izin Keperluan'
            elif 'cuti' in att_type:
                att['display_type'] = 'Cuti'
            else:
                att['display_type'] = 'Izin'
            permission_list.append(att)

    return render_template(
        'employee_detail.html',
        employee=employee,
        all_attendance=all_attendance,
        clock_in_list=clock_in_list,
        clock_out_list=clock_out_list,
        permission_list=permission_list,
        total_clock_in=len(clock_in_list),
        total_clock_out=len(clock_out_list),
        total_permission=len(permission_list)
    )

@app.route('/delete/<int:id>', methods=['POST'])
def delete_employee(id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Cari data karyawan sebelum dihapus
        cursor.execute("SELECT employee_id, username, face_image FROM employees WHERE id = %s", (id,))
        emp = cursor.fetchone()
        
        if emp:
            if emp.get('username'):
                cursor.execute("DELETE FROM users WHERE username = %s", (emp['username'],))
                cursor.execute("DELETE FROM attendance WHERE username = %s", (emp['username'],))
            
            # Hapus file foto dari folder assets/foto_karyawan jika ada
            if emp.get('face_image'):
                fpath = os.path.join(app.root_path, emp['face_image'].replace('/', os.sep))
                if os.path.exists(fpath):
                    try:
                        os.remove(fpath)
                    except Exception:
                        pass
            
        cursor.execute("DELETE FROM employees WHERE id = %s", (id,))
        
        conn.commit()
        conn.close()
        flash('Data karyawan, akun login, dan foto di assets/foto_karyawan berhasil dihapus!', 'success')
    except Exception as e:
        flash(f'Gagal menghapus data: {e}', 'danger')
        
    return redirect(url_for('employee_management'))

# ==========================================
# RUTE KANTOR CABANG (BRANCH COMPANY & LONG/LAT)
# ==========================================
@app.route('/branch-company')
def branch_company():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM branch_companies ORDER BY id DESC")
    branches = cursor.fetchall()
    conn.close()
    return render_template('branch_company.html', branches=branches)

@app.route('/add-branch', methods=['POST'])
def add_branch():
    branch_name = request.form.get('branch_name')
    city = request.form.get('city')
    latitude = request.form.get('latitude')
    longitude = request.form.get('longitude')
    radius = request.form.get('radius', 100)

    if not branch_name or not city or not latitude or not longitude:
        flash('Semua kolom wajib diisi termasuk koordinat!', 'danger')
        return redirect(url_for('branch_company'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO branch_companies (branch_name, city, latitude, longitude, radius) 
               VALUES (%s, %s, %s, %s, %s)""",
            (branch_name, city, latitude, longitude, radius)
        )
        conn.commit()
        conn.close()
        flash('Kantor cabang dan koordinat berhasil ditambahkan!', 'success')
    except Exception as e:
        flash(f'Gagal menambah cabang: {e}', 'danger')

    return redirect(url_for('branch_company'))

@app.route('/edit-branch/<int:id>', methods=['POST'])
def edit_branch(id):
    branch_name = request.form.get('branch_name')
    city = request.form.get('city')
    latitude = request.form.get('latitude')
    longitude = request.form.get('longitude')
    radius = request.form.get('radius', 100)

    if not branch_name or not city or not latitude or not longitude:
        flash('Semua kolom wajib diisi termasuk koordinat!', 'danger')
        return redirect(url_for('branch_company'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """UPDATE branch_companies 
               SET branch_name=%s, city=%s, latitude=%s, longitude=%s, radius=%s 
               WHERE id=%s""",
            (branch_name, city, latitude, longitude, radius, id)
        )
        conn.commit()
        conn.close()
        flash(f'Kantor cabang "{branch_name}" berhasil diperbarui!', 'success')
    except Exception as e:
        flash(f'Gagal mengupdate cabang: {e}', 'danger')

    return redirect(url_for('branch_company'))

@app.route('/delete-branch/<int:id>', methods=['POST'])
def delete_branch(id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT branch_name FROM branch_companies WHERE id = %s", (id,))
        branch = cursor.fetchone()
        
        if branch and 'kantor pusat surabaya' in branch.get('branch_name', '').strip().lower():
            conn.close()
            flash('Kantor Pusat Surabaya adalah kantor pusat utama dan tidak dapat dihapus!', 'warning')
            return redirect(url_for('branch_company'))

        cursor.execute("DELETE FROM branch_companies WHERE id = %s", (id,))
        conn.commit()
        conn.close()
        name = branch['branch_name'] if branch else f'ID {id}'
        flash(f'Kantor cabang "{name}" berhasil dihapus!', 'success')
    except Exception as e:
        flash(f'Gagal menghapus cabang: {e}', 'danger')

    return redirect(url_for('branch_company'))

# ==========================================
# RUTE LOWONGAN KERJA (VACANCY - SUDAH DIHAPUS)
# ==========================================
@app.route('/vacancy')
def vacancy():
    return redirect(url_for('index'))

@app.route('/add-vacancy', methods=['POST'])
def add_vacancy():
    title = request.form.get('title', 'Staff IT')
    division = request.form.get('division', 'IT')
    branch = request.form.get('branch', 'Surabaya')
    description = request.form.get('description', '')
    requirements = request.form.get('requirements', '')
    posted_date = request.form.get('posted_date') or datetime.now().strftime('%Y-%m-%d')
    status = request.form.get('status', 'Open')
    image = 'assets/avatar_mascot_centered.png'

    if not title:
        flash('Judul lowongan wajib diisi!', 'danger')
        return redirect(url_for('vacancy'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO vacancies (title, division, branch, description, requirements, posted_date, status, image)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (title, division, branch, description, requirements, posted_date, status, image))
        conn.commit()
        conn.close()
        flash(f'Lowongan "{title}" berhasil ditambahkan!', 'success')
    except Exception as e:
        flash(f'Gagal menambahkan lowongan: {e}', 'danger')

    return redirect(url_for('vacancy'))

@app.route('/edit-vacancy/<int:id>', methods=['POST'])
def edit_vacancy(id):
    title = request.form.get('title')
    division = request.form.get('division')
    branch = request.form.get('branch')
    description = request.form.get('description')
    requirements = request.form.get('requirements')
    status = request.form.get('status', 'Open')

    if not title:
        flash('Judul lowongan wajib diisi!', 'danger')
        return redirect(url_for('vacancy'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE vacancies
            SET title=%s, division=%s, branch=%s, description=%s, requirements=%s, status=%s
            WHERE id=%s
        """, (title, division, branch, description, requirements, status, id))
        conn.commit()
        conn.close()
        flash(f'Lowongan "{title}" berhasil diperbarui!', 'success')
    except Exception as e:
        flash(f'Gagal memperbarui lowongan: {e}', 'danger')

    return redirect(url_for('vacancy'))

@app.route('/delete-vacancy/<int:id>', methods=['POST'])
def delete_vacancy(id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT title FROM vacancies WHERE id = %s", (id,))
        vac = cursor.fetchone()
        cursor.execute("DELETE FROM vacancies WHERE id = %s", (id,))
        conn.commit()
        conn.close()
        title_str = vac['title'] if vac else f'ID {id}'
        flash(f'Lowongan "{title_str}" berhasil dihapus!', 'success')
    except Exception as e:
        flash(f'Gagal menghapus lowongan: {e}', 'danger')

    return redirect(url_for('vacancy'))

# ==========================================
# RUTE DATA KEHADIRAN (PRESENCE)
# ==========================================
@app.route('/presence')
def presence():
    now = datetime.now()
    current_day = now.strftime('%A')
    current_date_formatted = f"{now.strftime('%B')} {now.day}, {now.year}"
    
    search_query = request.args.get('search', '').strip()
    selected_branch = request.args.get('branch', '').strip()
    selected_team = request.args.get('team', '').strip()
    selected_status = request.args.get('status', '').strip()
    selected_tag = request.args.get('tag', '').strip()
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Ordering matching the Figma presence mockup
    order_clause = """
        ORDER BY 
            CASE 
                WHEN LEFT(e.employee_id, 3) = '278' THEN 1
                WHEN LEFT(e.employee_id, 3) = '174' THEN 2
                WHEN LEFT(e.employee_id, 3) = '793' THEN 3
                WHEN LEFT(e.employee_id, 3) = '554' THEN 4
                WHEN LEFT(e.employee_id, 3) = '650' THEN 5
                WHEN LEFT(e.employee_id, 3) = '445' THEN 6
                WHEN LEFT(e.employee_id, 3) = '496' THEN 7
                WHEN LEFT(e.employee_id, 3) = '954' THEN 8
                WHEN LEFT(e.employee_id, 3) = '675' THEN 9
                WHEN LEFT(e.employee_id, 3) = '769' THEN 10
                ELSE 100
            END ASC,
            e.id ASC
    """
    
    # Bangun kondisi WHERE dinamis
    where_conditions = []
    params = []
    
    if search_query:
        where_conditions.append("(e.branch LIKE %s OR e.name LIKE %s OR e.team LIKE %s OR e.employee_id LIKE %s)")
        q = f"%{search_query}%"
        params.extend([q, q, q, q])
        
    if selected_branch:
        where_conditions.append("e.branch = %s")
        params.append(selected_branch)
        
    if selected_team:
        where_conditions.append("e.team = %s")
        params.append(selected_team)
        
    if selected_status:
        if selected_status == 'hadir':
            where_conditions.append("(a.type = 'clock_in' OR a.type = 'hadir')")
        elif selected_status == 'pulang':
            where_conditions.append("a.type = 'clock_out'")
        elif selected_status == 'izin':
            where_conditions.append("(a.type IN ('izin', 'izin_sakit', 'izin_keperluan', 'cuti', 'sakit') OR a.type LIKE 'izin%%')")
        elif selected_status == 'sakit':
            where_conditions.append("(a.type IN ('sakit', 'izin_sakit') OR a.type LIKE '%%sakit%%')")
        elif selected_status == 'belum_hadir':
            where_conditions.append(
                "(a.type IS NULL OR a.type = '')")
            
    if selected_tag:
        where_conditions.append("(e.tag1 = %s OR e.tag2 = %s OR e.tag3 = %s)")
        params.extend([selected_tag, selected_tag, selected_tag])
        
    where_sql = ("WHERE " + " AND ".join(where_conditions)) if where_conditions else ""
    
    query = f"""
        SELECT 
            e.id, e.employee_id, e.name, e.team, e.branch, e.status, e.tag1, e.tag2, e.tag3, e.username, e.face_image,
            a.type AS today_type,
            SUBSTRING(TIME(COALESCE(a.clock_in_time, a.max_ts)), 1, 5) AS today_clock_in,
            SUBSTRING(TIME(a.clock_out), 1, 5) AS today_clock_out,
            a.image_path AS today_image,
            a.evidence_path AS today_evidence,
            a.reason AS today_reason
        FROM employees e
        LEFT JOIN (
            SELECT username,
                   SUBSTRING_INDEX(GROUP_CONCAT(type ORDER BY id DESC SEPARATOR '|||'), '|||', 1) AS type,
                   MAX(CASE WHEN type IN ('clock_in', 'hadir') THEN timestamp END) AS clock_in_time,
                   MAX(timestamp) AS max_ts,
                   MAX(clock_out) AS clock_out,
                   -- Ambil foto saat absen hari ini yang tidak kosong (prioritas foto clock_in / kehadiran)
                   COALESCE(
                       MAX(CASE WHEN type IN ('clock_in', 'hadir') AND image_path IS NOT NULL AND image_path != '' THEN image_path END),
                       MAX(CASE WHEN image_path IS NOT NULL AND image_path != '' THEN image_path END)
                   ) AS image_path,
                   MAX(CASE WHEN evidence_path IS NOT NULL AND evidence_path != '' THEN evidence_path END) AS evidence_path,
                   SUBSTRING_INDEX(GROUP_CONCAT(COALESCE(reason, '') ORDER BY id DESC SEPARATOR '|||'), '|||', 1) AS reason
            FROM attendance
            WHERE DATE(timestamp) = CURDATE()
              AND (type IN ('clock_in', 'hadir', 'clock_out') OR LOWER(COALESCE(status, '')) IN ('approved', 'disetujui'))
            GROUP BY username
        ) a ON e.username = a.username
        {where_sql}
        {order_clause}
    """
    
    if params:
        cursor.execute(query, tuple(params))
    else:
        cursor.execute(query)
        
    presence_list = cursor.fetchall()

    # Hitung keterangan kedatangan (Sangat Baik / Baik / Kurang Baik)
    # - dibawah jam 08:50 (530 menit): Sangat Baik
    # - 08:50 s/d 09:00 (530 - 540 menit): Baik
    # - diatas 09:00 (> 540 menit): Kurang Baik
    for emp in presence_list:
        # Jika belum absen hari itu atau tidak ada foto absensi hari ini, pastikan today_image bernilai None
        raw_today_img = emp.get('today_image')
        if not raw_today_img or not str(raw_today_img).strip() or not emp.get('today_type'):
            emp['today_image'] = None
        else:
            emp['today_image'] = str(raw_today_img).strip()

        # Jika hari ini memiliki permohonan izin/sakit yang approved, tampilkan sebagai 'izin'
        raw_type = (emp.get('today_type') or '').lower()
        if raw_type in ('izin', 'izin_sakit', 'izin_keperluan', 'cuti', 'sakit') or raw_type.startswith('izin'):
            emp['today_type'] = 'izin'

        clock_in = emp.get('today_clock_in')
        if clock_in and clock_in != '--:--':
            try:
                parts = str(clock_in).split(':')
                h, m = int(parts[0]), int(parts[1])
                tot = h * 60 + m
                if tot < 530:
                    emp['today_keterangan'] = 'Sangat Baik'
                    emp['keterangan_class'] = 'success'
                elif tot <= 540:
                    emp['today_keterangan'] = 'Baik'
                    emp['keterangan_class'] = 'primary'
                else:
                    emp['today_keterangan'] = 'Kurang Baik'
                    emp['keterangan_class'] = 'danger'
            except Exception:
                emp['today_keterangan'] = None
        else:
            emp['today_keterangan'] = None
    cursor.execute("""
        SELECT COUNT(DISTINCT username) as total_hadir
        FROM attendance
        WHERE DATE(timestamp) = CURDATE() AND (type = 'clock_in' OR type = 'hadir')
    """)
    hadir_count = cursor.fetchone()['total_hadir'] or 0
    
    # Ambil opsi filter kantor cabang dari tabel branch_companies
    cursor.execute("SELECT branch_name FROM branch_companies ORDER BY id ASC")
    branches = [r['branch_name'] for r in cursor.fetchall()]
    if not branches:
        branches = ['TUNGGAL SAHABAT ABADI', 'Decoy']
    
    cursor.execute("SELECT DISTINCT team FROM employees WHERE team IS NOT NULL AND team != '' ORDER BY team")
    teams = [r['team'] for r in cursor.fetchall()]
    
    conn.close()
    
    active_filter_count = sum(1 for val in [selected_branch, selected_team, selected_status, selected_tag] if val)
    
    return render_template(
        'presence.html',
        presence_list=presence_list,
        search_query=search_query,
        selected_branch=selected_branch,
        selected_team=selected_team,
        selected_status=selected_status,
        selected_tag=selected_tag,
        active_filter_count=active_filter_count,
        branches=branches,
        teams=teams,
        hadir_count=hadir_count,
        current_day=current_day,
        current_date_formatted=current_date_formatted
    )

# ==========================================
# RUTE PENGAJUAN IZIN / SAKIT / CUTI (REQUEST)
# ==========================================
@app.route('/request')
@app.route('/requests')
def request_page():
    now = datetime.now()
    current_day = now.strftime('%A')
    current_date_formatted = f"{now.strftime('%B')} {now.day}, {now.year}"
    type_filter = request.args.get('type', '').strip().lower()
    
    requests_list = []
    employees_list = []
    count_total_all = 0
    count_total_cuti = 0
    count_total_izin = 0
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Query seluruh pengajuan izin / sakit / cuti langsung dari tabel attendance JOIN employees
        cursor.execute("""
            SELECT 
                a.id,
                a.username,
                a.type,
                a.timestamp,
                a.clock_out,
                a.image_path,
                a.evidence_path,
                a.reason,
                COALESCE(a.status, 'Pending') AS status,
                DATE_FORMAT(a.timestamp, '%b %e, %Y') AS formatted_date,
                e.id AS employee_db_id,
                e.employee_id,
                COALESCE(e.name, a.username) AS name,
                COALESCE(e.team, 'Staff') AS role,
                e.team,
                e.branch,
                e.face_image,
                e.status AS emp_status,
                e.tag1, e.tag2
            FROM attendance a
            LEFT JOIN employees e ON a.username = e.username
            WHERE a.type IN ('izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti', 'izin_cuti')
               OR a.type LIKE 'izin_%'
               OR a.type LIKE '%cuti%'
               OR (a.reason IS NOT NULL AND a.reason != '' AND a.type NOT IN ('clock_in', 'clock_out', 'hadir'))
            ORDER BY 
                CASE 
                    WHEN COALESCE(a.status, 'Pending') = 'Pending' THEN 1
                    ELSE 2
                END ASC,
                a.id DESC
        """)
        raw_requests = cursor.fetchall()
        
        all_requests_parsed = []
        for r in raw_requests:
            r_type = r['type'].lower() if r['type'] else ''
            if 'cuti' in r_type:
                display_type = 'Cuti'
            elif 'sakit' in r_type:
                display_type = 'Sakit'
            elif 'keperluan' in r_type:
                display_type = 'Izin Keperluan'
            elif 'izin' in r_type:
                display_type = 'Izin'
            else:
                display_type = 'Izin'
                
            r['display_type'] = display_type
            all_requests_parsed.append(r)
            
        count_total_all = len(all_requests_parsed)
        count_total_cuti = len([r for r in all_requests_parsed if r['display_type'] == 'Cuti'])
        count_total_izin = len([r for r in all_requests_parsed if r['display_type'] != 'Cuti'])

        if type_filter == 'cuti':
            requests_list = [r for r in all_requests_parsed if r['display_type'] == 'Cuti']
        elif type_filter in ('izin', 'sakit'):
            requests_list = [r for r in all_requests_parsed if r['display_type'] != 'Cuti']
        else:
            requests_list = all_requests_parsed
            
        # 2. Ambil daftar karyawan untuk modal tambah pengajuan
        cursor.execute("SELECT employee_id, username, name, team, branch FROM employees ORDER BY name ASC")
        employees_list = cursor.fetchall()
        
        conn.close()
    except Exception as e:
        flash(f'Gagal memuat data pengajuan: {e}', 'danger')
        print(f"[Request Error] {e}")
    
    # Filter berdasarkan status untuk tabs (Pending, Disetujui, Ditolak)
    pending_list  = [r for r in requests_list if (r.get('status') or 'Pending').lower() == 'pending']
    approved_list = [r for r in requests_list if (r.get('status') or '').lower() == 'approved']
    rejected_list = [r for r in requests_list if (r.get('status') or '').lower() == 'rejected']
    
    return render_template(
        'request.html',
        requests_list=requests_list,
        pending_list=pending_list,
        approved_list=approved_list,
        rejected_list=rejected_list,
        count_pending=len(pending_list),
        count_approved=len(approved_list),
        count_rejected=len(rejected_list),
        count_total_all=count_total_all,
        count_total_cuti=count_total_cuti,
        count_total_izin=count_total_izin,
        active_type_filter=type_filter,
        employees_list=employees_list,
        current_day=current_day,
        current_date_formatted=current_date_formatted
    )

@app.route('/add-request', methods=['POST'])
def add_request():
    username = request.form.get('username')
    req_type = request.form.get('type', 'sakit').lower()
    reason = request.form.get('reason', '')
    req_date = request.form.get('date') or datetime.now().strftime('%Y-%m-%d')
    timestamp_str = f"{req_date} 08:00:00"

    if not username or not reason:
        flash('Karyawan dan Alasan izin/cuti wajib diisi!', 'danger')
        return redirect(url_for('request_page'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Jika karyawan pengajuan lagi setelah ditolak, hapus pengajuan yang ditolak sebelumnya
        cursor.execute("""
            DELETE FROM attendance 
            WHERE username = %s AND status = 'Rejected' 
              AND (type IN ('izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti', 'izin_cuti') OR type LIKE 'izin_%%' OR type LIKE '%%cuti%%')
        """, (username,))

        cursor.execute("""
            INSERT INTO attendance (username, type, timestamp, reason, status)
            VALUES (%s, %s, %s, %s, 'Pending')
        """, (username, req_type, timestamp_str, reason))
        conn.commit()
        conn.close()
        label = 'Cuti' if 'cuti' in req_type else ('Sakit' if 'sakit' in req_type else 'Izin')
        flash(f'Pengajuan {label} untuk @{username} berhasil disimpan dan langsung masuk ke database!', 'success')
    except Exception as e:
        flash(f'Gagal menambahkan pengajuan: {e}', 'danger')

    return redirect(url_for('request_page', type='cuti' if 'cuti' in req_type else ''))

@app.route('/update-request-status/<int:id>', methods=['POST'])
def update_request_status(id):
    new_status = request.form.get('status', 'Approved')
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE attendance SET status = %s WHERE id = %s", (new_status, id))
        conn.commit()
        conn.close()
        flash(f'Status pengajuan berhasil diperbarui menjadi "{new_status}"!', 'success')
    except Exception as e:
        flash(f'Gagal memperbarui status: {e}', 'danger')
    return redirect(url_for('request_page'))

@app.route('/delete-request/<int:id>', methods=['POST'])
def delete_request(id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM attendance WHERE id = %s", (id,))
        conn.commit()
        conn.close()
        flash('Data pengajuan berhasil dihapus!', 'success')
    except Exception as e:
        flash(f'Gagal menghapus pengajuan: {e}', 'danger')
    return redirect(url_for('request_page'))

# ==========================================
# ==========================================
# RUTE LAPORAN KEHADIRAN (REPORT)
# FORMAT REKAPITULASI (TANPA NIP)
# ==========================================
def parse_record_dates(record_timestamp, reason_str, start_dt, end_dt):
    """
    Mengembalikan set tanggal (date objects) hari kerja (Senin-Jumat)
    yang jatuh dalam rentang filter [start_dt.date(), end_dt.date()].
    Mendukung penguraian multi-hari seperti: 'Periode: YYYY-MM-DD s/d YYYY-MM-DD'.
    """
    filter_start = start_dt.date() if isinstance(start_dt, datetime) else start_dt
    filter_end = end_dt.date() if isinstance(end_dt, datetime) else end_dt
    if filter_start > filter_end:
        filter_start, filter_end = filter_end, filter_start

    matched_dates = set()
    reason = str(reason_str or '')

    # Deteksi pola rentang tanggal pada alasan: YYYY-MM-DD s/d YYYY-MM-DD
    period_match = re.search(r'(\d{4}-\d{2}-\d{2})\s*(?:s/d|to|-)\s*(\d{4}-\d{2}-\d{2})', reason)
    if period_match:
        try:
            p_start = datetime.strptime(period_match.group(1), '%Y-%m-%d').date()
            p_end = datetime.strptime(period_match.group(2), '%Y-%m-%d').date()
            if p_start > p_end:
                p_start, p_end = p_end, p_start
            
            cur = p_start
            while cur <= p_end:
                # Hanya hari kerja (Senin-Jumat) dan berada di dalam rentang filter yang dipilih
                if cur.weekday() < 5 and filter_start <= cur <= filter_end:
                    matched_dates.add(cur)
                cur += timedelta(days=1)
        except Exception:
            pass

    # Jika bukan rentang tanggal multi-hari, gunakan tanggal dari record_timestamp
    if not matched_dates and record_timestamp:
        try:
            if isinstance(record_timestamp, str):
                ts_dt = datetime.strptime(record_timestamp[:10], '%Y-%m-%d').date()
            elif isinstance(record_timestamp, datetime):
                ts_dt = record_timestamp.date()
            else:
                ts_dt = record_timestamp
            
            if ts_dt.weekday() < 5 and filter_start <= ts_dt <= filter_end:
                matched_dates.add(ts_dt)
        except Exception:
            pass

    return matched_dates

def get_rekap_report_data(start_date, end_date, branch='all'):
    try:
        dt_start = datetime.strptime(start_date, '%Y-%m-%d')
        dt_end = datetime.strptime(end_date, '%Y-%m-%d')
        if dt_start > dt_end:
            dt_start, dt_end = dt_end, dt_start
        total_days = (dt_end - dt_start).days + 1
        
        # Hitung hari kerja asli sesuai tanggal kalender (Senin s/d Jumat, Sabtu & Minggu libur)
        working_days = sum(
            1 for i in range(total_days)
            if (dt_start + timedelta(days=i)).weekday() < 5
        )
        total_hari_kerja = max(1, working_days)
    except Exception:
        total_hari_kerja = 22
        dt_start = datetime.now().replace(day=1)
        dt_end = datetime.now()

    conn = get_db_connection()
    cursor = conn.cursor()

    # Filter kantor cabang yang fleksibel dan akurat
    where_sql = ""
    params = []
    if branch and branch != 'all':
        where_sql = """
            WHERE (
                e.branch = %s 
                OR e.branch LIKE %s 
                OR %s LIKE CONCAT('%%', COALESCE(e.branch, ''), '%%')
                OR (%s IN ('TUNGGAL SAHABAT ABADI', 'Kantor Pusat Surabaya') AND (e.branch IN ('Surabaya', 'Kantor Pusat Surabaya', 'TUNGGAL SAHABAT ABADI') OR e.branch IS NULL))
            )
        """
        params = [branch, f"%{branch}%", branch, branch]

    # Ambil seluruh karyawan sesuai filter cabang
    cursor.execute(f"""
        SELECT 
            e.id,
            e.name,
            e.username,
            COALESCE(e.team, 'Operasional') AS divisi,
            COALESCE(e.branch, 'TUNGGAL SAHABAT ABADI') AS branch
        FROM employees e
        {where_sql}
        ORDER BY e.id ASC
    """, tuple(params))
    employees = cursor.fetchall()

    # Ambil daftar kantor cabang untuk dropdown
    cursor.execute("SELECT branch_name FROM branch_companies ORDER BY id ASC")
    branches = [b['branch_name'] for b in cursor.fetchall()]
    if not branches:
        branches = ['TUNGGAL SAHABAT ABADI', 'Decoy']

    # Ambil seluruh rekaman kehadiran yang relevan dari database (Approved maupun Pending, abaikan yang Rejected)
    # Rentang query mencakup toleransi 60 hari sebelum dan 5 hari sesudah untuk menangkap pengajuan cuti berperiode
    min_date_str = (dt_start - timedelta(days=60)).strftime('%Y-%m-%d 00:00:00')
    max_date_str = (dt_end + timedelta(days=5)).strftime('%Y-%m-%d 23:59:59')
    
    cursor.execute("""
        SELECT 
            id,
            username,
            type,
            timestamp,
            reason,
            status
        FROM attendance
        WHERE LOWER(COALESCE(status, '')) NOT IN ('rejected', 'ditolak')
          AND timestamp >= %s AND timestamp <= %s
    """, (min_date_str, max_date_str))
    attendance_rows = cursor.fetchall()
    conn.close()

    # Petakan kehadiran per username
    emp_records = {}
    for att in attendance_rows:
        uname = (att.get('username') or '').strip().lower()
        if uname:
            emp_records.setdefault(uname, []).append(att)

    processed_data = []
    tot_hadir = 0
    tot_izin_keperluan = 0
    tot_izin_sakit = 0
    tot_cuti = 0
    tot_alpha = 0

    for idx, e in enumerate(employees, 1):
        uname = (e.get('username') or '').strip().lower()
        records = emp_records.get(uname, [])

        hadir_dates = set()
        cuti_dates = set()
        sakit_dates = set()
        izin_dates = set()

        for rec in records:
            r_type = (rec.get('type') or '').lower().strip()
            r_reason = rec.get('reason') or ''
            r_ts = rec.get('timestamp')

            # Ambil tanggal-tanggal hari kerja yang valid dalam rentang filter
            matched = parse_record_dates(r_ts, r_reason, dt_start, dt_end)
            if not matched:
                continue

            # Klasifikasi jenis absensi
            if r_type in ('clock_in', 'hadir', 'present'):
                hadir_dates.update(matched)
            elif 'cuti' in r_type or 'cuti' in r_reason.lower():
                cuti_dates.update(matched)
            elif 'sakit' in r_type or 'sakit' in r_reason.lower() or r_type == 'sick_leave':
                sakit_dates.update(matched)
            elif (r_type in ('izin', 'izin_keperluan', 'necessity_leave') 
                  or (r_type.startswith('izin') and 'sakit' not in r_type and 'cuti' not in r_type) 
                  or ('keperluan' in r_reason.lower()) 
                  or (r_reason and r_type not in ('clock_in', 'clock_out', 'hadir', 'cuti', 'izin_cuti', 'sakit', 'izin_sakit'))):
                izin_dates.update(matched)

        # Resolusi prioritas status jika tanggal bertabrakan: Hadir > Cuti > Sakit > Izin
        cuti_dates -= hadir_dates
        sakit_dates -= (hadir_dates | cuti_dates)
        izin_dates -= (hadir_dates | cuti_dates | sakit_dates)

        hadir = len(hadir_dates)
        cuti = len(cuti_dates)
        izin_sakit = len(sakit_dates)
        izin_keperluan = len(izin_dates)

        # Jumlah Alpha: Hari kerja dikurangi hari hadir, cuti, izin sakit, dan izin keperluan
        alpha = max(0, total_hari_kerja - hadir - cuti - izin_sakit - izin_keperluan)
        pct = round((hadir / total_hari_kerja) * 100) if total_hari_kerja > 0 else 0

        username = e.get('username') or ''
        email = username if '@' in username else (f"{username.lower()}@gmail.com" if username else '-')
        branch_name = e.get('branch') or 'TUNGGAL SAHABAT ABADI'
        if branch_name == 'Surabaya':
            branch_name = 'TUNGGAL SAHABAT ABADI'

        tot_hadir += hadir
        tot_cuti += cuti
        tot_izin_sakit += izin_sakit
        tot_izin_keperluan += izin_keperluan
        tot_alpha += alpha

        processed_data.append({
            'no': idx,
            'name': e.get('name') or username or '-',
            'email': email,
            'divisi': e.get('divisi') or 'Operasional',
            'branch': branch_name,
            'total_hari_kerja': total_hari_kerja,
            'jumlah_hadir': hadir,
            'jumlah_izin_keperluan': izin_keperluan,
            'jumlah_izin_sakit': izin_sakit,
            'jumlah_cuti': cuti,
            'jumlah_alpha': alpha,
            'persentase': f"{pct}%",
            'persentase_num': pct
        })

    return {
        'data': processed_data,
        'branches': branches,
        'total_hari_kerja': total_hari_kerja,
        'tot_hadir': tot_hadir,
        'tot_izin_keperluan': tot_izin_keperluan,
        'tot_izin_sakit': tot_izin_sakit,
        'tot_cuti': tot_cuti,
        'tot_alpha': tot_alpha
    }

@app.route('/report')
def report_page():
    now = datetime.now()
    current_day = now.strftime('%A')
    current_date_formatted = f"{now.strftime('%B')} {now.day}, {now.year}"
    
    # Default dinamis: awal bulan berjalan hingga hari ini
    first_day_of_month = now.strftime('%Y-%m-01')
    today_str = now.strftime('%Y-%m-%d')
    start_date = request.args.get('start_date') or first_day_of_month
    end_date = request.args.get('end_date') or today_str
    selected_branch = request.args.get('branch', 'all')
    selected_format = request.args.get('format', 'xlsx')
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT branch_name FROM branch_companies ORDER BY id ASC")
    branches = [b['branch_name'] for b in cursor.fetchall()]
    if not branches:
        branches = ['TUNGGAL SAHABAT ABADI', 'Decoy']
    conn.close()

    return render_template(
        'report.html',
        start_date=start_date,
        end_date=end_date,
        selected_branch=selected_branch,
        selected_format=selected_format,
        branches=branches,
        current_day=current_day,
        current_date_formatted=current_date_formatted
    )

@app.route('/report/export', methods=['GET', 'POST'])
def export_report():
    now = datetime.now()
    first_day_of_month = now.strftime('%Y-%m-01')
    today_str = now.strftime('%Y-%m-%d')

    if request.method == 'POST':
        start_date = request.form.get('start_date') or first_day_of_month
        end_date = request.form.get('end_date') or today_str
        branch = request.form.get('branch', 'all')
        file_format = request.form.get('format', 'xlsx').lower()
    else:
        start_date = request.args.get('start_date') or first_day_of_month
        end_date = request.args.get('end_date') or today_str
        branch = request.args.get('branch', 'all')
        file_format = request.args.get('format', 'xlsx').lower()

    rekap = get_rekap_report_data(start_date, end_date, branch)
    processed_data = rekap['data']
    total_hari_kerja = rekap['total_hari_kerja']

    filename_base = f"Laporan_Kehadiran_Karyawan_{start_date}_sd_{end_date}"
    branch_str = "Semua Cabang" if branch == 'all' else branch

    # PDF GENERATION (.PDF)
    if file_format == 'pdf':
        buf = io.BytesIO()
        doc = SimpleDocTemplate(buf, pagesize=landscape(letter), rightMargin=24, leftMargin=24, topMargin=24, bottomMargin=24)
        elements = []

        styles = getSampleStyleSheet()
        title_style = ParagraphStyle('ReportTitle', parent=styles['Heading1'], fontSize=15, leading=19, textColor=colors.HexColor('#131B3E'))
        sub_style = ParagraphStyle('ReportSub', parent=styles['Normal'], fontSize=9, leading=13, textColor=colors.HexColor('#4A5568'))

        elements.append(Paragraph("<b>LAPORAN REKAPITULASI KEHADIRAN KARYAWAN</b>", title_style))
        elements.append(Paragraph(f"Rentang Tanggal: {start_date} s/d {end_date} | Kantor Cabang: {branch_str} | Dicetak: {datetime.now().strftime('%d/%m/%Y %H:%M')}", sub_style))
        elements.append(Spacer(1, 14))

        # 11 Kolom Sama Persis dengan Excel
        table_headers = [
            "No",
            "Nama Karyawan",
            "Email",
            "Divisi",
            "Total Hari Kerja",
            "Jumlah Hadir",
            "Izin Keperluan",
            "Izin Sakit",
            "Cuti",
            "Jumlah Alpha",
            "Persentase Kehadiran (%)"
        ]
        table_rows = [table_headers]

        for r in processed_data:
            table_rows.append([
                str(r['no']),
                str(r['name'])[:20],
                str(r['email'])[:22],
                str(r['divisi'])[:16],
                str(r['total_hari_kerja']),
                str(r['jumlah_hadir']),
                str(r['jumlah_izin_keperluan']),
                str(r['jumlah_izin_sakit']),
                str(r['jumlah_cuti']),
                str(r['jumlah_alpha']),
                r['persentase']
            ])

        col_widths = [24, 110, 116, 72, 65, 55, 60, 55, 45, 65, 75]
        pdf_table = Table(table_rows, colWidths=col_widths, repeatRows=1)
        pdf_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#131B3E')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('ALIGN', (1, 1), (3, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 8.5),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 6),
            ('TOPPADDING', (0, 0), (-1, 0), 6),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')]),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#E2E8F0')),
            ('FONTSIZE', (0, 1), (-1, -1), 8),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ]))
        elements.append(pdf_table)

        doc.build(elements)
        buf.seek(0)
        return send_file(
            buf,
            as_attachment=True,
            download_name=f"{filename_base}.pdf",
            mimetype="application/pdf"
        )

    # EXCEL GENERATION (.XLSX) - Default template
    else:
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "Rekap Kehadiran"

        # Judul & Metadata Laporan (Sama dengan PDF)
        ws['A1'] = "LAPORAN REKAPITULASI KEHADIRAN KARYAWAN"
        ws['A1'].font = Font(name="Calibri", size=14, bold=True, color="131B3E")
        ws.merge_cells('A1:K1')
        ws['A1'].alignment = Alignment(horizontal="left", vertical="center")

        ws['A2'] = f"Rentang Tanggal: {start_date} s/d {end_date} | Kantor Cabang: {branch_str} | Dicetak: {datetime.now().strftime('%d/%m/%Y %H:%M')}"
        ws['A2'].font = Font(name="Calibri", size=10, italic=True, color="4B5563")
        ws.merge_cells('A2:K2')
        ws['A2'].alignment = Alignment(horizontal="left", vertical="center")

        headers = [
            "No",
            "Nama Karyawan",
            "Email",
            "Divisi",
            "Total Hari Kerja",
            "Jumlah Hadir",
            "Izin Keperluan",
            "Izin Sakit",
            "Cuti",
            "Jumlah Alpha",
            "Persentase Kehadiran (%)"
        ]

        ws.append([]) # Baris 3: Pemisah kosong
        ws.append(headers) # Baris 4: Header Tabel

        header_fill = PatternFill(start_color="131B3E", end_color="131B3E", fill_type="solid")
        header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
        thin_border = Border(
            left=Side(style='thin', color='CBD5E1'),
            right=Side(style='thin', color='CBD5E1'),
            top=Side(style='thin', color='CBD5E1'),
            bottom=Side(style='thin', color='CBD5E1')
        )

        # Style header row (Row 4)
        ws.row_dimensions[4].height = 24
        for col_num in range(1, len(headers) + 1):
            cell = ws.cell(row=4, column=col_num)
            cell.font = header_font
            cell.fill = header_fill
            cell.alignment = Alignment(horizontal="center" if col_num in [1, 5, 6, 7, 8, 9, 10, 11] else "left", vertical="center")
            cell.border = thin_border

        # Isi data baris demi baris (Row 5+)
        for r in processed_data:
            row_data = [
                r['no'],
                r['name'],
                r['email'],
                r['divisi'],
                r['total_hari_kerja'],
                r['jumlah_hadir'],
                r['jumlah_izin_keperluan'],
                r['jumlah_izin_sakit'],
                r['jumlah_cuti'],
                r['jumlah_alpha'],
                r['persentase']
            ]
            ws.append(row_data)
            current_row = ws.max_row
            ws.row_dimensions[current_row].height = 20
            for col_idx in range(1, len(row_data) + 1):
                c = ws.cell(row=current_row, column=col_idx)
                c.border = thin_border
                c.font = Font(name="Calibri", size=10)
                if col_idx in [1, 5, 6, 7, 8, 9, 10, 11]:
                    c.alignment = Alignment(horizontal="center", vertical="center")
                else:
                    c.alignment = Alignment(horizontal="left", vertical="center")

        # Auto lebar kolom (mengabaikan baris 1-3 agar tidak terpengaruh merge cells judul)
        for col in ws.columns:
            col_cells = [cell for cell in col if cell.row >= 4]
            if not col_cells:
                continue
            max_len = max(len(str(cell.value or '')) for cell in col_cells)
            col_letter = openpyxl.utils.get_column_letter(col_cells[0].column)
            ws.column_dimensions[col_letter].width = max(max_len + 4, 12)

        buf = io.BytesIO()
        wb.save(buf)
        buf.seek(0)
        return send_file(
            buf,
            as_attachment=True,
            download_name=f"{filename_base}.xlsx",
            mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )

@app.route('/logout')
def logout():
    session.clear()
    flash('Anda telah berhasil keluar dari akun!', 'info')
    return redirect(url_for('login'))

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8085))
    debug_mode = os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    app.run(host='0.0.0.0', port=port, debug=debug_mode)
# ==========================================
# RUTE HRD CONTACT & PENGUMUMAN (ANNOUNCEMENTS)
# ==========================================
@app.route('/admin/hrd-contact/update', methods=['POST'])
def update_hrd_contact():
    hrd_whatsapp = request.form.get('hrd_whatsapp', '').strip()
    hrd_name = request.form.get('hrd_name', '').strip()

    if not hrd_whatsapp:
        flash('Nomor WhatsApp HRD wajib diisi!', 'danger')
        return redirect(url_for('index'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO app_settings (setting_key, setting_value)
            VALUES ('hrd_whatsapp', %s)
            ON DUPLICATE KEY UPDATE setting_value = %s
        """, (hrd_whatsapp, hrd_whatsapp))

        if hrd_name:
            cursor.execute("""
                INSERT INTO app_settings (setting_key, setting_value)
                VALUES ('hrd_name', %s)
                ON DUPLICATE KEY UPDATE setting_value = %s
            """, (hrd_name, hrd_name))

        conn.commit()
        conn.close()
        flash('Kontak WhatsApp HRD berhasil diperbarui & otomatis sinkron ke HP karyawan!', 'success')
    except Exception as e:
        flash(f'Gagal memperbarui kontak HRD: {e}', 'danger')

    return redirect(url_for('index'))

@app.route('/admin/announcement/add', methods=['POST'])
def add_announcement():
    title = request.form.get('title', '').strip()
    content = request.form.get('content', '').strip()
    ann_type = request.form.get('type', 'info').strip()

    if not title or not content:
        flash('Judul dan isi pemberitahuan wajib diisi!', 'danger')
        return redirect(url_for('index'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS announcements (
                id INT AUTO_INCREMENT PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                content TEXT NOT NULL,
                type VARCHAR(50) DEFAULT 'info',
                is_active TINYINT(1) DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_ann_active (is_active)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)
        cursor.execute("""
            INSERT INTO announcements (title, content, type, is_active)
            VALUES (%s, %s, %s, 1)
        """, (title, content, ann_type))
        conn.commit()
        conn.close()
        flash(f'Pemberitahuan "{title}" berhasil dikirim ke HP seluruh karyawan & tersimpan di Riwayat!', 'success')
    except Exception as e:
        flash(f'Gagal membuat pemberitahuan: {e}', 'danger')

    return redirect(url_for('index'))

@app.route('/admin/announcement/edit/<int:id>', methods=['POST'])
def edit_announcement(id):
    title = request.form.get('title', '').strip()
    content = request.form.get('content', '').strip()
    ann_type = request.form.get('type', 'info').strip()
    is_active = int(request.form.get('is_active', 1))

    if not title or not content:
        flash('Judul dan isi pemberitahuan wajib diisi!', 'danger')
        return redirect(url_for('index'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE announcements 
            SET title = %s, content = %s, type = %s, is_active = %s
            WHERE id = %s
        """, (title, content, ann_type, is_active, id))
        conn.commit()
        conn.close()
        flash(f'Pemberitahuan "{title}" berhasil diperbarui!', 'success')
    except Exception as e:
        flash(f'Gagal memperbarui pemberitahuan: {e}', 'danger')

    return redirect(url_for('index'))

@app.route('/admin/announcement/toggle/<int:id>', methods=['POST', 'GET'])
def toggle_announcement(id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE announcements SET is_active = CASE WHEN is_active = 1 THEN 0 ELSE 1 END WHERE id = %s", (id,))
        conn.commit()
        conn.close()
        flash('Status aktif pemberitahuan berhasil diperbarui!', 'success')
    except Exception as e:
        flash(f'Gagal mengubah status: {e}', 'danger')

    return redirect(url_for('index'))

@app.route('/admin/announcement/delete/<int:id>', methods=['POST', 'GET'])
def delete_announcement(id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM announcements WHERE id = %s", (id,))
        conn.commit()
        conn.close()
        flash('Pemberitahuan berhasil dihapus dari riwayat sistem!', 'success')
    except Exception as e:
        flash(f'Gagal menghapus pemberitahuan: {e}', 'danger')

    return redirect(url_for('index'))

# ==========================================
# REST API PUBLIK UNTUK FLUTTER MOBILE APP
# ==========================================
@app.route('/api/user/register-face', methods=['POST'])
def api_register_face():
    data = request.get_json(silent=True) or request.form
    username = (data.get('username') or '').strip()
    face_image = (data.get('face_image') or '').strip()

    if not username or not face_image:
        return jsonify({'success': False, 'message': 'username dan face_image wajib diisi'}), 400

    try:
        assets_dir = os.path.join(app.root_path, 'assets', 'foto_karyawan')
        os.makedirs(assets_dir, exist_ok=True)
        import re
        clean_user = re.sub(r'[^a-zA-Z0-9_-]', '_', username)
        filename = f"ref_{clean_user}_{int(datetime.now().timestamp())}.jpg"
        filepath = os.path.join(assets_dir, filename)

        raw_b64 = face_image
        if ',' in face_image:
            raw_b64 = face_image.split(',', 1)[1]
        with open(filepath, 'wb') as f:
            f.write(base64.b64decode(raw_b64))

        db_image_path = f"assets/foto_karyawan/{filename}"

        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE users SET face_image = %s WHERE username = %s", (db_image_path, username))
        try:
            cursor.execute("UPDATE employees SET face_image = %s WHERE username = %s", (db_image_path, username))
        except Exception as emp_err:
            print(f"[RegisterFace Employee Update]: {emp_err}")
        conn.commit()
        conn.close()

        print(f"[API Register Face Success] Foto acuan wajah @{username} disimpan di {db_image_path}")
        return jsonify({
            'success': True,
            'message': 'Foto wajah acuan AI berhasil disimpan!',
            'face_image': db_image_path
        })
    except Exception as e:
        print(f"[API Register Face Error]: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/settings/hrd-contact', methods=['GET'])
def api_get_hrd_contact():
    hrd_whatsapp = '+62 851-9616-7691'
    hrd_name = 'HRD PT TSA'
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT setting_key, setting_value FROM app_settings WHERE setting_key IN ('hrd_whatsapp', 'hrd_name')")
        for row in cursor.fetchall():
            if row['setting_key'] == 'hrd_whatsapp':
                hrd_whatsapp = row['setting_value']
            elif row['setting_key'] == 'hrd_name':
                hrd_name = row['setting_value']
        conn.close()
    except Exception:
        pass

    clean_phone = ''.join([c for c in hrd_whatsapp if c.isdigit()])
    if clean_phone.startswith('0'):
        clean_phone = '62' + clean_phone[1:]

    return jsonify({
        'success': True,
        'hrd_whatsapp': hrd_whatsapp,
        'hrd_phone_clean': clean_phone,
        'hrd_name': hrd_name
    })

@app.route('/api/announcements', methods=['GET'])
def api_get_announcements():
    announcements = []
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS announcements (
                id INT AUTO_INCREMENT PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                content TEXT NOT NULL,
                type VARCHAR(50) DEFAULT 'info',
                is_active TINYINT(1) DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_ann_active (is_active)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)
        cursor.execute("""
            SELECT id, title, content, type, is_active,
                   DATE_FORMAT(created_at, '%d %b %Y %H:%i') AS formatted_date
            FROM announcements
            WHERE is_active = 1
            ORDER BY id DESC
            LIMIT 15
        """)
        announcements = cursor.fetchall()
        conn.close()
    except Exception as e:
        return jsonify({'success': False, 'message': str(e), 'data': []})

    return jsonify({
        'success': True,
        'data': announcements
    })

# ==========================================
# REST API ATTENDANCE & PENGAJUAN IZIN / CUTI (UNTUK APLIKASI FLUTTER MOBILE)
# ==========================================
@app.route('/api/attendance', methods=['POST'])
def api_save_attendance():
    """Menyimpan absensi dan pengajuan cuti/izin langsung ke MySQL dari Flutter mobile."""
    data = request.get_json(silent=True) or request.form
    username = (data.get('username') or '').strip()
    req_type = (data.get('type') or '').strip().lower()
    reason = (data.get('reason') or '').strip()
    image = data.get('image') or ''
    evidence_image = data.get('evidence_image') or ''

    if not username or not req_type:
        return jsonify({'success': False, 'message': 'username dan type wajib diisi'}), 400

    saved_img_path = None
    if image and len(image) > 50:
        try:
            upload_dir = os.path.join(app.root_path, 'assets', 'foto_izin')
            os.makedirs(upload_dir, exist_ok=True)
            clean_b64 = image.split(',')[-1] if ',' in image else image
            img_data = base64.b64decode(clean_b64)
            filename = f"izin_{username}_{int(time.time())}.jpg"
            file_path = os.path.join(upload_dir, filename)
            with open(file_path, 'wb') as f:
                f.write(img_data)
            saved_img_path = f"assets/foto_izin/{filename}"
        except Exception as img_err:
            print(f"[API Attendance Image Error]: {img_err}")

    saved_ev_path = None
    if evidence_image and len(evidence_image) > 50:
        try:
            upload_dir = os.path.join(app.root_path, 'assets', 'foto_izin')
            os.makedirs(upload_dir, exist_ok=True)
            clean_b64 = evidence_image.split(',')[-1] if ',' in evidence_image else evidence_image
            img_data = base64.b64decode(clean_b64)
            filename = f"ev_{username}_{int(time.time())}.jpg"
            file_path = os.path.join(upload_dir, filename)
            with open(file_path, 'wb') as f:
                f.write(img_data)
            saved_ev_path = f"assets/foto_izin/{filename}"
        except Exception as ev_err:
            print(f"[API Attendance Evidence Error]: {ev_err}")

    is_permission = req_type in ('izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti', 'izin_cuti') or req_type.startswith('izin_')
    status = 'Pending' if is_permission else 'Approved'

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        if is_permission:
            # Hapus pengajuan lama yang berstatus Rejected untuk digantikan pengajuan baru
            cursor.execute("""
                DELETE FROM attendance 
                WHERE username = %s AND status = 'Rejected' 
                  AND (type IN ('izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti', 'izin_cuti') OR type LIKE 'izin_%%' OR type LIKE '%%cuti%%')
            """, (username,))

        cursor.execute("""
            INSERT INTO attendance (username, type, timestamp, image_path, evidence_path, reason, status)
            VALUES (%s, %s, NOW(), %s, %s, %s, %s)
        """, (username, req_type, saved_img_path, saved_ev_path, reason, status))
        conn.commit()
        conn.close()

        msg = 'Pengajuan cuti/izin berhasil disimpan dan menunggu verifikasi Admin!' if is_permission else 'Presensi berhasil disimpan!'
        return jsonify({'success': True, 'message': msg})
    except Exception as e:
        print(f"[API Attendance Error]: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/attendance/status/<username>', methods=['GET'])
def api_get_attendance_status(username):
    """Mengembalikan status presensi dan pengajuan cuti/izin hari ini untuk aplikasi mobile."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT id, type, timestamp, clock_out, reason, status
            FROM attendance
            WHERE username = %s AND DATE(timestamp) = CURDATE()
            ORDER BY id ASC
        """, (username,))
        rows = cursor.fetchall()
        conn.close()

        has_clocked_in = False
        has_clocked_out = False
        clock_in_time = '--:--'
        clock_out_time = '--:--'
        clock_in_location = 'Kantor Pusat'
        has_permission = False
        permission_type = None
        permission_status = None
        permission_reason = None
        permission_time = None
        permission_id = None

        for r in rows:
            t = (r.get('type') or '').lower()
            ts = r.get('timestamp')
            time_str = ts.strftime('%H:%M') if ts else '--:--'
            r_status = r.get('status') or 'Pending'

            if t in ('izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti', 'izin_cuti') or t.startswith('izin_') or 'cuti' in t:
                has_permission = True
                permission_id = r.get('id')
                permission_type = t
                permission_status = r_status
                permission_reason = r.get('reason') or ''
                permission_time = time_str
            elif t == 'clock_in':
                has_clocked_in = True
                has_clocked_out = False
                clock_in_time = time_str
                if r.get('reason'):
                    clock_in_location = r.get('reason')
                if r.get('clock_out'):
                    has_clocked_out = True
                    clock_out_time = r.get('clock_out').strftime('%H:%M')
            elif t == 'clock_out':
                has_clocked_out = True
                clock_out_time = time_str

        return jsonify({
            'success': True,
            'hasClockedIn': has_clocked_in,
            'hasClockedOut': has_clocked_out,
            'clockInTime': clock_in_time,
            'clockInLocation': clock_in_location,
            'clockOutTime': clock_out_time,
            'hasPermission': has_permission,
            'permissionType': permission_type,
            'permissionStatus': permission_status,
            'permissionReason': permission_reason,
            'permissionTime': permission_time,
            'permissionId': permission_id
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT_ADMIN', 8085))
    debug = os.environ.get('FLASK_DEBUG', 'False').lower() in ('true', '1', 't')
    app.run(host='0.0.0.0', port=port, debug=debug)

