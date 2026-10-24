import os
import sys
import glob
from pathlib import Path
from flask import Flask, request, jsonify
from flask_cors import CORS
import pymysql

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

import config
from face_engine import face_engine

app = Flask(__name__)
CORS(app)  # Izinkan request dari Flutter mobile & backend Express

def get_db_connection():
    """Koneksi ke database absensi_wg jika diperlukan untuk mengambil path foto acuan."""
    ssl_config = {'ssl': {}} if (getattr(config, 'DB_SSL', False) or config.DB_PORT == 4000) else None
    try:
        return pymysql.connect(
            host=config.DB_HOST,
            port=config.DB_PORT,
            user=config.DB_USER,
            password=config.DB_PASSWORD,
            database=config.DB_NAME,
            ssl=ssl_config,
            cursorclass=pymysql.cursors.DictCursor
        )
    except Exception as e:
        print(f"[DB Warning] Tidak dapat terhubung ke MySQL: {e}")
        return None

def find_employee_reference_photo(username):
    """
    Mencari path foto acuan karyawan:
    1. Cek query database MySQL pada tabel users/employees
    2. Fallback cek pencocokan nama file di assets/foto_karyawan/*_<username>.jpg
    """
    # 1. Coba dari Database (tabel users dan employees)
    conn = get_db_connection()
    if conn:
        try:
            with conn.cursor() as cursor:
                cursor.execute("SELECT face_image FROM users WHERE username = %s LIMIT 1", (username,))
                row = cursor.fetchone()
                if not row or not row.get('face_image'):
                    cursor.execute("SELECT face_image FROM employees WHERE username = %s LIMIT 1", (username,))
                    row = cursor.fetchone()

                if row and row.get('face_image'):
                    db_path = str(row['face_image']).strip()
                    # Jika berupa data base64 langsung
                    if db_path.startswith('data:image') or len(db_path) > 300:
                        return db_path
                    # Jika berupa path file
                    clean_path = config.PROJECT_ROOT / db_path.replace('/', os.sep)
                    if clean_path.exists():
                        return str(clean_path)
                    alt_path = config.ASSETS_DIR / db_path.replace('assets/', '').replace('assets\\', '').replace('/', os.sep)
                    if alt_path.exists():
                        return str(alt_path)
        except Exception as e:
            print(f"[DB Query Error]: {e}")
        finally:
            conn.close()

    # 2. Cek langsung di folder fisik assets/foto_karyawan/
    foto_dir = config.FOTO_KARYAWAN_DIR
    if foto_dir.exists():
        # Cari file dengan akhiran _{username}.jpg atau {username}.*
        patterns = [
            str(foto_dir / f"*_{username}.jpg"),
            str(foto_dir / f"*_{username}.png"),
            str(foto_dir / f"{username}.jpg"),
            str(foto_dir / f"{username}.png"),
        ]
        for pat in patterns:
            matches = glob.glob(pat)
            if matches:
                return matches[0]

    return None


# ============================================================
# ENDPOINTS
# ============================================================

@app.route('/', methods=['GET'])
@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "status": "online",
        "service": "ProjectWG AI Face Recognition Service",
        "engine": face_engine.engine_name,
        "engine_type": face_engine.engine_type,
        "arcface_threshold": getattr(config, "ARCFACE_THRESHOLD", 0.40),
        "tolerance": config.TOLERANCE,
        "similarity_threshold": f"{config.SIMILARITY_THRESHOLD}%",
        "assets_connected": config.FOTO_KARYAWAN_DIR.exists()
    })


@app.route('/api/verify', methods=['POST'])
def verify_attendance_face():
    """
    Endpoint utama verifikasi absensi:
    Membandingkan foto selfie live dari kamera Flutter dengan foto acuan karyawan yang terdaftar.
    
    Payload (JSON atau Form-Data):
    - username (string) : Username karyawan
    - image (string/file) : Foto selfie (Base64 string atau file upload)
    - reference_image (optional) : Base64 foto acuan jika ingin dioper langsung
    """
    username = None
    live_image = None
    reference_image = None

    # Handle JSON input
    if request.is_json:
        data = request.get_json() or {}
        username = data.get('username')
        live_image = data.get('image') or data.get('live_image')
        reference_image = data.get('reference_image')

    # Handle Form-Data / Multipart input
    else:
        username = request.form.get('username')
        live_image = request.form.get('image')
        reference_image = request.form.get('reference_image')
        
        # Jika dikirim sebagai file binary
        if 'image' in request.files:
            live_image = request.files['image'].read()
        if 'reference_image' in request.files:
            reference_image = request.files['reference_image'].read()

    if not live_image:
        return jsonify({
            "success": False,
            "matched": False,
            "message": "Parameter 'image' (foto selfie) wajib dikirimkan!"
        }), 400

    # Jika foto acuan tidak dikirim langsung, cari berdasarkan username
    if not reference_image:
        if not username:
            return jsonify({
                "success": False,
                "matched": False,
                "message": "Parameter 'username' atau 'reference_image' wajib disertakan!"
            }), 400

        ref_path = find_employee_reference_photo(username)
        if not ref_path:
            return jsonify({
                "success": False,
                "matched": False,
                "message": f"Foto acuan wajah untuk karyawan '{username}' tidak ditemukan di sistem!"
            }), 404
        reference_image = ref_path

    # Jalankan pencocokan wajah dengan model AI
    result = face_engine.compare_faces(reference_image, live_image)

    return jsonify({
        "success": True,
        "username": username,
        "matched": result["matched"],
        "similarity_score": result["similarity_score"],
        "distance": result["distance"],
        "face_detected": result["face_detected"],
        "engine": result.get("engine", "default"),
        "message": result["message"]
    }), 200


@app.route('/api/compare', methods=['POST'])
def compare_two_images():
    """
    Endpoint pembanding 2 foto secara langsung (image1 vs image2).
    """
    data = request.get_json() if request.is_json else request.form
    img1 = data.get('image1')
    img2 = data.get('image2')

    if not img1 and 'image1' in request.files:
        img1 = request.files['image1'].read()
    if not img2 and 'image2' in request.files:
        img2 = request.files['image2'].read()

    if not img1 or not img2:
        return jsonify({
            "success": False,
            "message": "Dibutuhkan 2 gambar: 'image1' dan 'image2'!"
        }), 400

    result = face_engine.compare_faces(img1, img2)
    return jsonify({
        "success": True,
        "matched": result["matched"],
        "similarity_score": result["similarity_score"],
        "distance": result["distance"],
        "face_detected": result["face_detected"],
        "message": result["message"]
    })


@app.route('/api/detect', methods=['POST'])
def detect_face_presence():
    """
    Endpoint sederhana untuk memeriksa apakah terdapat wajah di foto selfie.
    """
    image_data = None
    if request.is_json:
        image_data = (request.get_json() or {}).get('image')
    else:
        image_data = request.form.get('image')
        if 'image' in request.files:
            image_data = request.files['image'].read()

    if not image_data:
        return jsonify({"success": False, "message": "Parameter 'image' wajib dikirimkan!"}), 400

    try:
        rgb_img = face_engine.decode_image(image_data)
        faces = face_engine.detect_faces(rgb_img)
        return jsonify({
            "success": True,
            "face_count": len(faces),
            "face_detected": len(faces) > 0,
            "bounding_boxes": faces
        })
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 400


if __name__ == '__main__':
    print("=" * 60)
    print(f"[AI SERVICE] ProjectWG AI Service berjalan di http://{config.HOST}:{config.PORT}")
    print(f"[AI SERVICE] Root Assets: {config.ASSETS_DIR}")
    print(f"[AI SERVICE] Engine Aktif: {face_engine.engine_name}")
    print("=" * 60)
    app.run(host=config.HOST, port=config.PORT, debug=config.DEBUG)
