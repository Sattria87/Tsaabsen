import os
from pathlib import Path
# Muat file .env jika ada (dengan fallback jika python-dotenv belum terpasang)
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    # Fallback sederhana membaca file .env manual tanpa library dotenv
    env_file = Path(__file__).resolve().parent / ".env"
    if env_file.exists():
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    os.environ.setdefault(key.strip(), val.strip())

BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent

# Server Config
HOST = os.getenv("AI_HOST", "0.0.0.0")
PORT = int(os.getenv("AI_PORT", 5001))
DEBUG = os.getenv("AI_DEBUG", "True").lower() == "true"

# Asset Paths
_assets_env = os.getenv("ASSETS_DIR")
if _assets_env and Path(_assets_env).exists():
    ASSETS_DIR = Path(_assets_env)
elif (PROJECT_ROOT / "assets").exists():
    ASSETS_DIR = PROJECT_ROOT / "assets"
elif (BASE_DIR / "assets").exists():
    ASSETS_DIR = BASE_DIR / "assets"
elif Path("/app/assets").exists():
    ASSETS_DIR = Path("/app/assets")
else:
    ASSETS_DIR = PROJECT_ROOT / "assets"

FOTO_KARYAWAN_DIR = ASSETS_DIR / "foto_karyawan"
MODELS_DIR = BASE_DIR / "models"
EMBEDDINGS_DIR = BASE_DIR / "embeddings"

# MySQL Database Config (Sinkron dengan ProjectWG)
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_NAME = os.getenv("DB_NAME", "absensi_wg")
DB_PORT = int(os.getenv("DB_PORT", 3306))

# AI Model Settings
# Toleransi jarak face embedding (Semakin kecil semakin ketat/akurat, standar face_recognition: 0.60)
TOLERANCE = float(os.getenv("FACE_TOLERANCE", 0.55))

# Ambang batas persentase kemiripan minimum untuk lolos (contoh: 70.0%)
SIMILARITY_THRESHOLD = float(os.getenv("SIMILARITY_THRESHOLD", 79.0))
