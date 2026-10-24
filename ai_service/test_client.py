"""
Skrip pengujian cepat untuk memverifikasi endpoint AI Service ProjectWG.
Jalankan setelah app.py aktif:
python test_client.py
"""

import json

BASE_URL = "http://localhost:5001"

def test_health():
    print("\n--- 1. Testing Health Check Endpoint ---")
    try:
        # Coba menggunakan library requests jika terpasang
        try:
            import requests
            res = requests.get(f"{BASE_URL}/health")
            status_code = res.status_code
            data = res.json()
        except ImportError:
            # Fallback menggunakan library standar bawaan Python (urllib)
            import urllib.request
            req = urllib.request.Request(f"{BASE_URL}/health")
            with urllib.request.urlopen(req) as response:
                status_code = response.getcode()
                data = json.loads(response.read().decode('utf-8'))

        print(f"Status Code: {status_code}")
        print("Response JSON:")
        print(json.dumps(data, indent=2))
    except Exception as e:
        print(f"Gagal koneksi ke {BASE_URL}: {e}")
        print("Pastikan 'python app.py' sudah aktif di terminal.")

if __name__ == "__main__":
    test_health()

