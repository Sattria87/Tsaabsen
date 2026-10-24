import subprocess
import threading
import sys
import os
import time
import re

# Pastikan output konsol mendukung UTF-8
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CLOUDFLARED_EXE = os.path.join(BASE_DIR, "cloudflared.exe")
MYSQL_HELPER_PATH = os.path.join(BASE_DIR, "lib", "utils", "mysql_helper.dart")

# Kode warna konsol
COLOR_CYAN = "\033[96m"
COLOR_GREEN = "\033[92m"
COLOR_YELLOW = "\033[93m"
COLOR_RED = "\033[91m"
COLOR_RESET = "\033[0m"
COLOR_BOLD = "\033[1m"

processes = []

def extract_tunnel_url(proc, name):
    """Membaca output cloudflared sampai menemukan URL publik trycloudflare.com."""
    url = None
    start_time = time.time()
    while time.time() - start_time < 25:
        line = proc.stdout.readline()
        if not line:
            break
        # Cari pola https://xxxx.trycloudflare.com
        match = re.search(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com', line)
        if match:
            url = match.group(0)
            break
    return url

def update_flutter_mysql_helper(backend_url):
    """Otomatis mengupdate apiBaseUrl di lib/utils/mysql_helper.dart."""
    try:
        if os.path.exists(MYSQL_HELPER_PATH):
            with open(MYSQL_HELPER_PATH, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_api_url = f"{backend_url}/api"
            new_content = re.sub(
                r"const String apiBaseUrl = '[^']+';",
                f"const String apiBaseUrl = '{new_api_url}';",
                content
            )
            
            with open(MYSQL_HELPER_PATH, 'w', encoding='utf-8') as f:
                f.write(new_content)
            return True
    except Exception as e:
        print(f"  [Info] Tidak dapat auto-update mysql_helper.dart: {e}", flush=True)
    return False

def main():
    os.system("")
    print("=" * 72, flush=True)
    print(f"{COLOR_BOLD}>>> MEMULAI SISTEM PROJECTWG + CLOUDFLARE PUBLIC HTTPS TUNNEL <<<{COLOR_RESET}", flush=True)
    print("=" * 72, flush=True)

    # 1. Pastikan cloudflared.exe ada
    if not os.path.exists(CLOUDFLARED_EXE):
        print("[ERROR] File cloudflared.exe tidak ditemukan di folder root project!", flush=True)
        return

    # 2. Jalankan run_all.py lokal (Backend, Website, dan AI)
    print("\n[*] Menjalankan Backend (3000), Website (8085), dan AI Service (5001)...", flush=True)
    try:
        run_all_proc = subprocess.Popen(
            [sys.executable, "run_all.py"],
            cwd=BASE_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        processes.append(run_all_proc)
    except Exception as e:
        print(f"[ERROR] Gagal menjalankan run_all.py: {e}", flush=True)
        return

    # Tunggu beberapa detik agar port lokal sudah listening
    print("    Menunggu server lokal aktif...", flush=True)
    time.sleep(3)

    # 3. Jalankan Cloudflare Tunnel untuk Backend API (Port 3000)
    print("\n[*] Menghubungkan Backend ke Internet Publik (Port 3000)...", flush=True)
    backend_proc = subprocess.Popen(
        [CLOUDFLARED_EXE, "tunnel", "--url", "http://127.0.0.1:3000"],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace"
    )
    processes.append(backend_proc)

    backend_url = extract_tunnel_url(backend_proc, "Backend")
    if not backend_url:
        print("[WARNING] Gagal mendapatkan URL Cloudflare untuk Backend.", flush=True)
        backend_url = "http://192.168.1.9:3000"
    else:
        print(f"    [OK] URL Backend Berhasil: {COLOR_CYAN}{backend_url}{COLOR_RESET}", flush=True)

    # 4. Jalankan Cloudflare Tunnel untuk Website Admin (Port 8085)
    print("\n[*] Menghubungkan Website Admin ke Internet Publik (Port 8085)...", flush=True)
    web_proc = subprocess.Popen(
        [CLOUDFLARED_EXE, "tunnel", "--url", "http://127.0.0.1:8085"],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace"
    )
    processes.append(web_proc)

    web_url = extract_tunnel_url(web_proc, "Website")
    if not web_url:
        print("[WARNING] Gagal mendapatkan URL Cloudflare untuk Website Admin.", flush=True)
        web_url = "http://192.168.1.9:8085"
    else:
        print(f"    [OK] URL Website Berhasil: {COLOR_GREEN}{web_url}{COLOR_RESET}", flush=True)

    # 5. Otomatis pasang URL Backend ke Flutter lib/utils/mysql_helper.dart
    updated = False
    if backend_url.startswith("https://"):
        updated = update_flutter_mysql_helper(backend_url)

    # TAMPILKAN KESIMPULAN BERSIH & RAPI
    print("\n" + "=" * 72, flush=True)
    print(f"{COLOR_BOLD}{COLOR_GREEN}[OK] SELURUH LAYANAN ONLINE BERHASIL DIAKTIFKAN DI INTERNET!{COLOR_RESET}", flush=True)
    print("=" * 72, flush=True)
    print(f"""
{COLOR_BOLD}[1] APLIKASI FLUTTER DI HP (API BACKEND):{COLOR_RESET}
    URL: {COLOR_CYAN}{backend_url}/api{COLOR_RESET}
    {"[OK] (Sudah otomatis dipasang ke lib/utils/mysql_helper.dart!)" if updated else "=> Salin URL di atas ke lib/utils/mysql_helper.dart"}

{COLOR_BOLD}[2] WEBSITE ADMIN TSA (DAPAT DIBUKA DARI BROWSER HP/LAPTOP MANA SAJA):{COLOR_RESET}
    URL: {COLOR_GREEN}{web_url}/login{COLOR_RESET}
    Akun: Username: {COLOR_BOLD}admin{COLOR_RESET} | Password: {COLOR_BOLD}123{COLOR_RESET}
""", flush=True)
    print("=" * 72, flush=True)
    print(f"{COLOR_YELLOW}Tips: Biarkan jendela ini tetap terbuka selama Anda menguji aplikasi di HP.{COLOR_RESET}", flush=True)
    print(f"{COLOR_YELLOW}Tekan Ctrl + C untuk mematikan seluruh layanan sekaligus.{COLOR_RESET}", flush=True)
    print("=" * 72 + "\n", flush=True)

    # Jaga proses tetap berjalan
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print(f"\n{COLOR_YELLOW}[!] Menghentikan seluruh tunnel dan server lokal...{COLOR_RESET}", flush=True)
        for p in processes:
            try:
                p.terminate()
            except Exception:
                pass
        print(f"{COLOR_GREEN}[OK] Seluruh layanan telah dimatikan dengan aman.{COLOR_RESET}", flush=True)

if __name__ == '__main__':
    main()
