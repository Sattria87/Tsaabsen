import subprocess
import threading
import sys
import os
import time

# Pastikan output konsol mendukung karakter UTF-8
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

# Lokasi direktori root project
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Kode warna ANSI untuk konsol
COLOR_CYAN = "\033[96m"
COLOR_GREEN = "\033[92m"
COLOR_YELLOW = "\033[93m"
COLOR_RED = "\033[91m"
COLOR_RESET = "\033[0m"
COLOR_BOLD = "\033[1m"

# Daftar 3 layanan yang akan dijalankan
SERVICES = [
    {
        "name": "BACKEND",
        "color": COLOR_CYAN,
        "cwd": os.path.join(BASE_DIR, "backend"),
        "cmd": ["node", "server.js"],
        "port": 3000,
        "url": "http://localhost:3000"
    },
    {
        "name": "WEBSITE",
        "color": COLOR_GREEN,
        "cwd": BASE_DIR,
        "cmd": [sys.executable, "admin_app.py"],
        "port": 8085,
        "url": "http://localhost:8085/login"
    },
    {
        "name": "AI_SERVICE",
        "color": COLOR_YELLOW,
        "cwd": os.path.join(BASE_DIR, "ai_service"),
        "cmd": [sys.executable, "app.py"],
        "port": 5001,
        "url": "http://localhost:5001/health"
    }
]

processes = []

def free_port(port):
    """Mematikan proses lama yang masih tersangkut di port tertentu untuk mencegah EADDRINUSE."""
    try:
        cmd = f'netstat -ano | findstr :{port}'
        output = subprocess.check_output(cmd, shell=True, text=True, errors="replace")
        current_pid = os.getpid()
        killed = set()
        for line in output.strip().splitlines():
            parts = line.split()
            if len(parts) >= 5 and f":{port}" in parts[1] and parts[3].upper() == "LISTENING":
                pid = int(parts[4])
                if pid != current_pid and pid not in killed and pid > 0:
                    subprocess.run(f"taskkill /F /PID {pid}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    killed.add(pid)
                    print(f"  [Auto-Clean] Membebaskan port {port} (menghentikan PID lama: {pid})")
    except Exception:
        pass

def stream_logs(pipe, prefix, color):
    """Membaca output dari tiap proses secara realtime dan menambahkan tag warna."""
    try:
        for line in iter(pipe.readline, ''):
            if not line:
                break
            text = line.rstrip()
            print(f"{color}[{prefix}]{COLOR_RESET} {text}", flush=True)
    except Exception:
        pass

def main():
    # Aktifkan warna ANSI di Windows Command Prompt
    os.system("")

    print("=" * 68)
    print(f"{COLOR_BOLD}>>> MEMULAI SELURUH LAYANAN PROJECTWG (BACKEND + WEB + AI)<<<{COLOR_RESET}")
    print("=" * 68)

    # Siapkan environment variabel UTF-8 untuk child process Python
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"

    for s in SERVICES:
        # 1. Bersihkan port terlebih dahulu jika ada proses lama yang tersangkut
        free_port(s["port"])

        # 2. Jalankan service
        print(f"[*] Menjalankan {s['color']}{s['name']}{COLOR_RESET} di port {s['port']} ({s['url']})...")
        try:
            proc = subprocess.Popen(
                s["cmd"],
                cwd=s["cwd"],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1
            )
            processes.append((s["name"], proc))
            
            # Thread pembaca log
            t = threading.Thread(target=stream_logs, args=(proc.stdout, s["name"], s["color"]), daemon=True)
            t.start()
            time.sleep(1.2)
        except Exception as e:
            print(f"{COLOR_RED}[!] Gagal memulai {s['name']}: {e}{COLOR_RESET}")

    print("=" * 68)
    print(f"{COLOR_BOLD}[OK] Semua layanan aktif! Tekan Ctrl + C untuk mematikan semua.{COLOR_RESET}")
    print("=" * 68)

    # Monitor proses sampai dihentikan dengan Ctrl+C
    try:
        while True:
            time.sleep(1)
            for name, p in processes:
                if p.poll() is not None:
                    pass
    except KeyboardInterrupt:
        print(f"\n{COLOR_YELLOW}[!] Menghentikan seluruh layanan...{COLOR_RESET}")
        for name, p in processes:
            try:
                p.terminate()
            except Exception:
                pass
        print(f"{COLOR_GREEN}[OK] Seluruh layanan telah berhasil dimatikan dengan aman.{COLOR_RESET}")

if __name__ == '__main__':
    main()
