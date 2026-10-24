# init_db.py
import sqlite3

DB_NAME = 'absensi_wg.db'

def create_employee_table():
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    
    # Buat tabel employees jika belum ada
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        team TEXT NOT NULL,
        branch TEXT NOT NULL,
        status TEXT NOT NULL,
        tag1 TEXT,
        tag2 TEXT,
        tag3 TEXT
    )
    ''')
    
    # Masukkan data contoh (dummy) agar tabel tidak kosong
    cursor.execute("INSERT OR IGNORE INTO employees (employee_id, name, team, branch, status, tag1, tag2) VALUES ('278.291.85', 'Bambang Pamungkas', 'HR', 'Surabaya', 'Aktif', 'Full Time', 'On Site')")
    cursor.execute("INSERT OR IGNORE INTO employees (employee_id, name, team, branch, status, tag1, tag2, tag3) VALUES ('174.901.21', 'Rina Sari', 'HG', 'Jakarta', 'Cuti', 'Part Time', 'Remote', 'Contract')")
    
    conn.commit()
    conn.close()
    print("Tabel 'employees' berhasil dibuat dan data contoh ditambahkan.")

if __name__ == '__main__':
    create_employee_table()