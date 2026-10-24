import pymysql
import os

DB_HOST = os.environ.get('DB_HOST', '127.0.0.1')
DB_USER = 'root'
DB_PASSWORD = ''
DB_NAME = 'absensi_wg'

def migrate():
    conn = pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor
    )
    cursor = conn.cursor()

    # 1. Pastikan tabel vacancies ada
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)
    print("[1] Tabel 'vacancies' siap / sudah ada.")

    # Jika tabel vacancies masih kosong, tambahkan data contoh
    cursor.execute("SELECT COUNT(*) AS total FROM vacancies")
    count_vac = cursor.fetchone()['total']
    if count_vac == 0:
        sample_vacancies = [
            ("Staff IT & Network", "IT", "Surabaya", 
             "Bertanggung jawab atas troubleshooting jaringan, pemeliharaan server, dan dukungan teknis harian bagi seluruh staf operasional kantor.", 
             "- Pendidikan Min. D3/S1 Teknik Informatika / Sistem Informasi\n- Menguasai dasar routing, switching, dan Linux/Windows Server\n- Mampu bekerja dalam tim dan komunikasi baik\n- Bersedia on-site di Surabaya",
             "2026-10-10", "Open", "assets/avatar_mascot_centered.png"),
            ("Frontend Flutter Developer", "IT", "Jakarta", 
             "Mengembangkan dan merawat antarmuka aplikasi mobile absensi berbasis Flutter agar responsif, cepat, dan user friendly.", 
             "- Pengalaman minimal 1 tahun menggunakan Flutter/Dart\n- Memahami integrasi REST API dan state management\n- Memiliki portofolio aplikasi mobile yang sudah dipublish merupakan nilai plus",
             "2026-10-12", "Open", "assets/avatar_mascot_centered.png"),
            ("Human Resource Specialist", "HR", "Surabaya", 
             "Mengelola rekrutmen karyawan baru, proses onboarding, serta memonitoring administrasi kehadiran dan kepatuhan SOP perusahaan.", 
             "- Pendidikan S1 Psikologi / Manajemen SDM / Hukum\n- Pengalaman minimal 1 tahun di bidang HR / Rekrutmen\n- Memiliki kemampuan interpersonal yang tinggi",
             "2026-10-15", "Open", "assets/avatar_mascot_centered.png"),
        ]
        cursor.executemany("""
            INSERT INTO vacancies (title, division, branch, description, requirements, posted_date, status, image)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, sample_vacancies)
        print(f"[1b] Berhasil menambahkan {len(sample_vacancies)} contoh lowongan kerja.")

    # 2. Pastikan kolom status ada pada tabel attendance
    cursor.execute("""
    SELECT COUNT(*) AS cnt 
    FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = %s 
      AND TABLE_NAME = 'attendance' 
      AND COLUMN_NAME = 'status'
    """, (DB_NAME,))
    res_status = cursor.fetchone()
    if res_status['cnt'] == 0:
        cursor.execute("""
            ALTER TABLE attendance 
            ADD COLUMN status VARCHAR(20) DEFAULT 'Pending' AFTER reason
        """)
        print("[2] Kolom 'status' berhasil ditambahkan ke tabel 'attendance'.")
    else:
        print("[2] Kolom 'status' sudah ada di tabel 'attendance'.")

    # Update baris absensi yang lama agar statusnya valid
    cursor.execute("""
        UPDATE attendance 
        SET status = 'Approved' 
        WHERE (type IN ('clock_in', 'clock_out', 'hadir') OR type IS NULL) 
          AND (status IS NULL OR status = 'Pending')
    """)

    # Cek apakah ada pengajuan izin di database, jika belum ada buatkan contoh data izin
    cursor.execute("SELECT COUNT(*) AS total FROM attendance WHERE type IN ('izin', 'sakit', 'izin_sakit', 'izin_keperluan', 'cuti')")
    count_req = cursor.fetchone()['total']
    if count_req == 0:
        # Cek username karyawan yang ada
        cursor.execute("SELECT username FROM employees LIMIT 2")
        emps = cursor.fetchall()
        if emps:
            u1 = emps[0]['username']
            cursor.execute("""
                INSERT INTO attendance (username, type, timestamp, reason, status)
                VALUES (%s, 'sakit', NOW(), 'Demam tinggi dan flu, istirahat dokter selama 2 hari', 'Pending')
            """, (u1,))
            if len(emps) > 1:
                u2 = emps[1]['username']
                cursor.execute("""
                    INSERT INTO attendance (username, type, timestamp, reason, status)
                    VALUES (%s, 'izin', NOW(), 'Izin menghadiri urusan keluarga mendesak', 'Approved')
                """, (u2,))
            print("[3] Data contoh pengajuan izin/sakit berhasil ditambahkan.")

    # 4. Pastikan tabel admins ada untuk autentikasi Web Dashboard
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS admins (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(100) NOT NULL UNIQUE,
        password VARCHAR(255) NOT NULL,
        name VARCHAR(150) NOT NULL,
        email VARCHAR(150),
        role VARCHAR(50) DEFAULT 'Super Admin'
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)
    print("[4] Tabel 'admins' siap / sudah ada.")

    # Pastikan kolom avatar, created_at, updated_at, last_login dibersihkan jika masih ada
    for col in ['avatar', 'created_at', 'updated_at', 'last_login']:
        cursor.execute("""
            SELECT COUNT(*) AS cnt 
            FROM information_schema.COLUMNS 
            WHERE TABLE_SCHEMA = %s 
              AND TABLE_NAME = 'admins' 
              AND COLUMN_NAME = %s
        """, (DB_NAME, col))
        if cursor.fetchone()['cnt'] > 0:
            cursor.execute(f"ALTER TABLE admins DROP COLUMN {col}")
            print(f"[4a] Kolom '{col}' berhasil dihapus dari tabel 'admins'.")

    # Cek apakah tabel admins memiliki akun, jika kosong tambahkan akun default
    cursor.execute("SELECT COUNT(*) AS total FROM admins")
    count_adm = cursor.fetchone()['total']
    if count_adm == 0:
        cursor.execute("""
            INSERT INTO admins (username, password, name, email, role)
            VALUES (%s, %s, %s, %s, %s)
        """, ('admin', '123', 'Administrator TSA', 'admin@tsa.co.id', 'Super Admin'))
        print("[4b] Akun default admin ('admin' / '123') berhasil dibuat di tabel 'admins'.")
    else:
        print(f"[4b] Tabel 'admins' sudah memiliki {count_adm} akun.")

    conn.commit()
    conn.close()
    print("[MIGRASI SELESAI] Database absensi_wg kini sudah lengkap dan siap digunakan!")

if __name__ == '__main__':
    migrate()
