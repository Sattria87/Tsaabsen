import os
import sys
import io
import base64
import hashlib
import numpy as np
import cv2
from PIL import Image
from pathlib import Path
import config

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

# Cek ketersediaan model tingkat lanjut: InsightFace (ArcFace 512D ONNX)
HAVE_INSIGHTFACE = False
try:
    import insightface
    from insightface.app import FaceAnalysis
    HAVE_INSIGHTFACE = True
except ImportError:
    pass

# Cek ketersediaan face_recognition (dlib 128D)
HAVE_FACE_RECOGNITION = False
try:
    import face_recognition
    HAVE_FACE_RECOGNITION = True
except ImportError:
    pass


class FaceEngine:
    def __init__(self):
        self.insightface_app = None
        self.engine_type = "opencv"
        self.engine_name = "OpenCV Fallback"

        # 1. Prioritas Utama: InsightFace (ArcFace 512D)
        preferred_engine = getattr(config, "AI_ENGINE", "auto").lower()
        if preferred_engine in ("auto", "insightface") and HAVE_INSIGHTFACE:
            try:
                model_name = getattr(config, "INSIGHTFACE_MODEL", "buffalo_s")
                # providers: CPUExecutionProvider (default aman di semua OS)
                app = FaceAnalysis(name=model_name, providers=['CPUExecutionProvider'])
                # ctx_id=-1 untuk CPU, det_size=(640, 640) standar deteksi akurat
                app.prepare(ctx_id=-1, det_size=(640, 640))
                self.insightface_app = app
                self.engine_type = "insightface"
                self.engine_name = f"InsightFace (ArcFace 512D - {model_name})"
                print(f"[AI SERVICE] [OK] Model AI Modern Aktif: {self.engine_name}")
            except Exception as e:
                print(f"[AI SERVICE Warning] Gagal inisialisasi InsightFace: {e}")
                self.insightface_app = None

        # 2. Prioritas Kedua: face_recognition (dlib 128D)
        if self.engine_type == "opencv" and preferred_engine in ("auto", "face_recognition") and HAVE_FACE_RECOGNITION:
            self.engine_type = "face_recognition"
            self.engine_name = "face_recognition (dlib 128D)"
            print(f"[AI SERVICE] Menggunakan Engine Fallback: {self.engine_name}")

        # 3. Prioritas Ketiga: OpenCV Haar Cascade Fallback
        if self.engine_type == "opencv":
            print(f"[AI SERVICE] [PERINGATAN] Menggunakan {self.engine_name} (Saran: Install 'insightface' & 'onnxruntime' untuk akurasi terbaik)")

        # Load OpenCV Haar Cascade untuk deteksi dasar jika classifier dibutuhkan
        self.face_cascade = None
        try:
            if hasattr(cv2, 'CascadeClassifier') and hasattr(cv2, 'data') and hasattr(cv2.data, 'haarcascades'):
                cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
                self.face_cascade = cv2.CascadeClassifier(cascade_path)
            elif hasattr(cv2, 'CascadeClassifier'):
                self.face_cascade = cv2.CascadeClassifier()
        except Exception as e:
            print(f"[AI SERVICE Info] CascadeClassifier tidak tersedia: {e}")

        # In-memory cache untuk encoding foto acuan agar verifikasi berulang berlangsung kilat
        self.reference_cache = {}
        self.preload_reference_photos()

    def preload_reference_photos(self):
        """Pre-cache seluruh foto acuan karyawan ke memory RAM saat startup agar verifikasi kilat."""
        ref_dir = getattr(config, "FOTO_KARYAWAN_DIR", None)
        if not ref_dir or not os.path.exists(str(ref_dir)):
            return
        try:
            count = 0
            for ext in ('*.jpg', '*.jpeg', '*.png', '*.JPG', '*.JPEG', '*.PNG'):
                for p in Path(ref_dir).glob(ext):
                    self._get_cached_encoding(str(p))
                    count += 1
            if count > 0:
                print(f"[AI SERVICE] [OK] {count} foto acuan karyawan berhasil di-cache ke memory RAM!")
        except Exception as e:
            print(f"[AI SERVICE Info] Gagal pre-cache foto acuan: {e}")

    def decode_image(self, image_input):
        """
        Mengubah berbagai format input (base64, bytes, file path, numpy) menjadi RGB numpy array.
        """
        if isinstance(image_input, np.ndarray):
            if len(image_input.shape) == 2:
                return cv2.cvtColor(image_input, cv2.COLOR_GRAY2RGB) if hasattr(cv2, 'cvtColor') else np.stack([image_input]*3, axis=-1)
            elif image_input.shape[2] == 4:
                return cv2.cvtColor(image_input, cv2.COLOR_RGBA2RGB) if hasattr(cv2, 'cvtColor') else image_input[:, :, :3]
            return image_input

        def _process_pil(img):
            # Optimasi kecepatan: resize gambar jika > 640px dengan BILINEAR agar deteksi AI kilat
            if max(img.size) > 640:
                resample_filter = getattr(Image, 'Resampling', Image).BILINEAR
                img.thumbnail((640, 640), resample_filter)
            return np.array(img.convert('RGB'))

        # Jika input adalah path file
        if isinstance(image_input, (str, Path)) and os.path.exists(str(image_input)):
            image = Image.open(str(image_input))
            return _process_pil(image)

        # Jika input adalah base64 string
        if isinstance(image_input, str):
            if ',' in image_input:
                image_input = image_input.split(',', 1)[1]
            raw_bytes = base64.b64decode(image_input)
            image = Image.open(io.BytesIO(raw_bytes))
            return _process_pil(image)

        # Jika input adalah raw bytes
        if isinstance(image_input, (bytes, bytearray)):
            image = Image.open(io.BytesIO(image_input))
            return _process_pil(image)

        raise ValueError("Format gambar tidak dikenali (gunakan Base64, Bytes, atau File Path)")

    def _to_bgr(self, rgb_image):
        """Helper konversi RGB numpy array ke BGR (format OpenCV / InsightFace)."""
        if hasattr(cv2, 'cvtColor'):
            return cv2.cvtColor(rgb_image, cv2.COLOR_RGB2BGR)
        return rgb_image[:, :, ::-1]

    def detect_faces(self, rgb_image):
        """
        Mendeteksi koordinat wajah di dalam gambar.
        Mengembalikan list bounding box [(x, y, w, h), ...]
        """
        # 1. InsightFace SCRFD Detector (sangat akurat)
        if self.engine_type == "insightface" and self.insightface_app is not None:
            try:
                bgr_image = self._to_bgr(rgb_image)
                faces = self.insightface_app.get(bgr_image)
                boxes = []
                for f in faces:
                    x1, y1, x2, y2 = f.bbox.astype(int)
                    w = max(0, x2 - x1)
                    h = max(0, y2 - y1)
                    boxes.append((int(x1), int(y1), int(w), int(h)))
                return boxes
            except Exception as e:
                print(f"[Detect Error InsightFace]: {e}")

        # 2. face_recognition (HOG / CNN)
        if self.engine_type == "face_recognition" and HAVE_FACE_RECOGNITION:
            locations = face_recognition.face_locations(rgb_image)
            boxes = []
            for top, right, bottom, left in locations:
                boxes.append((left, top, right - left, bottom - top))
            return boxes

        # 3. OpenCV Haar Cascade Fallback
        if self.face_cascade is not None and not self.face_cascade.empty():
            gray = cv2.cvtColor(rgb_image, cv2.COLOR_RGB2GRAY) if hasattr(cv2, 'cvtColor') else np.mean(rgb_image, axis=2).astype(np.uint8)
            faces = self.face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
            return [tuple(f) for f in faces]

        # 4. Fallback jika tidak ada detector: asumsikan area tengah frame
        h, w = rgb_image.shape[:2]
        return [(int(w * 0.15), int(h * 0.15), int(w * 0.7), int(h * 0.7))]

    def get_face_encoding(self, rgb_image):
        """
        Ekstraksi representasi fitur vektor wajah.
        - InsightFace: 512-dimensi normalized embedding (ArcFace)
        - face_recognition: 128-dimensi embedding (dlib ResNet)
        - OpenCV fallback: 128-bin histogram
        """
        # 1. InsightFace ArcFace (512D)
        if self.engine_type == "insightface" and self.insightface_app is not None:
            try:
                bgr_image = self._to_bgr(rgb_image)
                faces = self.insightface_app.get(bgr_image)
                if not faces:
                    return None
                # Pilih wajah terbesar (karyawan utama di depan kamera)
                largest_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
                emb = largest_face.embedding.astype(np.float32)
                # L2 Normalization agar Cosine Similarity = dot product
                norm = np.linalg.norm(emb)
                if norm > 0:
                    emb = emb / norm
                return emb
            except Exception as e:
                print(f"[ArcFace Embedding Error]: {e}")
                return None

        # 2. face_recognition (128D)
        if self.engine_type == "face_recognition" and HAVE_FACE_RECOGNITION:
            locations = face_recognition.face_locations(rgb_image)
            if not locations:
                return None
            encodings = face_recognition.face_encodings(rgb_image, known_face_locations=locations)
            if encodings:
                return encodings[0]
            return None

        # 3. OpenCV Fallback Histogram
        faces = self.detect_faces(rgb_image)
        if len(faces) == 0:
            return None
        x, y, w, h = faces[0]
        roi = rgb_image[y:y+h, x:x+w]
        if roi.size == 0:
            return None

        if hasattr(cv2, 'calcHist') and hasattr(cv2, 'cvtColor'):
            gray = cv2.cvtColor(roi, cv2.COLOR_RGB2GRAY)
            face_resized = cv2.resize(gray, (128, 128))
            hist = cv2.calcHist([face_resized], [0], None, [128], [0, 256])
            cv2.normalize(hist, hist)
            return hist.flatten()
        else:
            img_pil = Image.fromarray(roi).convert('L').resize((128, 128))
            arr = np.array(img_pil, dtype=np.float32)
            hist, _ = np.histogram(arr, bins=128, range=(0, 256), density=True)
            return hist

    def _get_cached_encoding(self, image_input):
        """Helper untuk mengambil encoding dari cache jika input adalah file path atau hash."""
        cache_key = None
        if isinstance(image_input, (str, Path)):
            cache_key = os.path.abspath(str(image_input)).lower()
        elif isinstance(image_input, (bytes, bytearray)):
            cache_key = hashlib.md5(image_input[:1024]).hexdigest()

        if cache_key and cache_key in self.reference_cache:
            return self.reference_cache[cache_key]

        rgb = self.decode_image(image_input)
        encoding = self.get_face_encoding(rgb)
        if cache_key and encoding is not None:
            self.reference_cache[cache_key] = encoding
        return encoding

    def compare_faces(self, reference_image_input, live_image_input):
        """
        Membandingkan foto acuan karyawan dengan foto selfie live saat absensi.
        Mengembalikan struktur dict lengkap yang kompatibel dengan Flutter & Express.
        """
        try:
            live_rgb = self.decode_image(live_image_input)
        except Exception as e:
            return {
                "matched": False,
                "similarity_score": 0.0,
                "distance": 1.0,
                "face_detected": False,
                "engine": self.engine_name,
                "message": f"Gagal membaca foto selfie: {str(e)}"
            }

        # Ekstraksi fitur wajah foto selfie live (Optimasi kilat 1-pass untuk InsightFace)
        if self.engine_type == "insightface" and self.insightface_app is not None:
            try:
                bgr_image = self._to_bgr(live_rgb)
                faces = self.insightface_app.get(bgr_image)
                if not faces:
                    return {
                        "matched": False,
                        "similarity_score": 0.0,
                        "distance": 1.0,
                        "face_detected": False,
                        "engine": self.engine_name,
                        "message": "Wajah tidak terdeteksi pada foto selfie. Harap posisikan wajah Anda dengan jelas di depan kamera!"
                    }
                largest_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
                emb = largest_face.embedding.astype(np.float32)
                norm = np.linalg.norm(emb)
                live_encoding = (emb / norm) if norm > 0 else emb
            except Exception as e:
                return {
                    "matched": False,
                    "similarity_score": 0.0,
                    "distance": 1.0,
                    "face_detected": False,
                    "engine": self.engine_name,
                    "message": f"Gagal mengekstrak fitur wajah: {str(e)}"
                }
        else:
            # Fallback untuk engine dlib / opencv
            live_faces = self.detect_faces(live_rgb)
            if len(live_faces) == 0:
                return {
                    "matched": False,
                    "similarity_score": 0.0,
                    "distance": 1.0,
                    "face_detected": False,
                    "engine": self.engine_name,
                    "message": "Wajah tidak terdeteksi pada foto selfie. Harap posisikan wajah Anda dengan jelas di depan kamera!"
                }
            live_encoding = self.get_face_encoding(live_rgb)
            if live_encoding is None:
                return {
                    "matched": False,
                    "similarity_score": 0.0,
                    "distance": 1.0,
                    "face_detected": False,
                    "engine": self.engine_name,
                    "message": "Gagal mengekstrak fitur wajah pada foto selfie."
                }

        # Ekstraksi foto acuan (dengan cache)
        try:
            ref_encoding = self._get_cached_encoding(reference_image_input)
        except Exception as e:
            return {
                "matched": False,
                "similarity_score": 0.0,
                "distance": 1.0,
                "face_detected": True,
                "engine": self.engine_name,
                "message": f"Gagal memproses foto acuan karyawan: {str(e)}"
            }

        if ref_encoding is None:
            return {
                "matched": False,
                "similarity_score": 0.0,
                "distance": 1.0,
                "face_detected": True,
                "engine": self.engine_name,
                "message": "Wajah pada foto acuan karyawan tidak terdeteksi atau foto acuan belum terdaftar."
            }

        # =========================================================
        # 1. EVALUASI MODEL: INSIGHTFACE (ARCFACE 512D)
        # =========================================================
        if self.engine_type == "insightface":
            # Cosine Similarity antar 512D vector yang sudah di-normalisasi (-1.0 s/d 1.0)
            cosine_sim = float(np.dot(ref_encoding, live_encoding))
            cosine_sim = max(-1.0, min(1.0, cosine_sim))

            arcface_thresh = getattr(config, "ARCFACE_THRESHOLD", 0.40)
            sim_threshold = getattr(config, "SIMILARITY_THRESHOLD", 65.0)

            # Jarak Cosine Distance (0.0 = identik, 1.0+ = beda orang)
            distance = round(float(1.0 - cosine_sim), 4)

            # Konversi terkalibrasi ke persentase 0 - 100%
            if cosine_sim <= 0.0:
                similarity = 0.0
            elif cosine_sim < arcface_thresh:
                # Skala di bawah ambang batas (0 s/d arcface_thresh -> 0% s/d sim_threshold)
                similarity = (cosine_sim / arcface_thresh) * sim_threshold
            else:
                # Skala di atas ambang batas (arcface_thresh s/d 1.0 -> sim_threshold s/d 100%)
                remain = 1.0 - arcface_thresh
                similarity = sim_threshold + ((cosine_sim - arcface_thresh) / remain) * (100.0 - sim_threshold)

            similarity = round(max(0.0, min(100.0, float(similarity))), 2)
            matched = (cosine_sim >= arcface_thresh) and (similarity >= sim_threshold)

            msg = "Wajah cocok & terverifikasi (InsightFace ArcFace)!" if matched else f"Wajah tidak cocok (Kemiripan: {similarity}%, minimal: {sim_threshold}%)"

            return {
                "matched": bool(matched),
                "similarity_score": round(similarity, 2),
                "distance": round(distance, 4),
                "face_detected": True,
                "engine": "insightface_arcface",
                "message": msg
            }

        # =========================================================
        # 2. EVALUASI MODEL: FACE_RECOGNITION (DLIB 128D)
        # =========================================================
        elif self.engine_type == "face_recognition":
            distance = float(np.linalg.norm(ref_encoding - live_encoding))
            if distance > 1.0:
                similarity = max(0.0, 100.0 - (distance * 50.0))
            else:
                similarity = round((1.0 - (distance / 1.0)) * 100.0, 2)

            tolerance = getattr(config, "TOLERANCE", 0.55)
            sim_threshold = getattr(config, "SIMILARITY_THRESHOLD", 65.0)

            matched = (distance <= tolerance) and (similarity >= sim_threshold)
            msg = "Wajah cocok & terverifikasi!" if matched else f"Wajah tidak cocok (Kemiripan: {similarity}%, minimal: {sim_threshold}%)"

            return {
                "matched": bool(matched),
                "similarity_score": round(similarity, 2),
                "distance": round(distance, 4),
                "face_detected": True,
                "engine": "face_recognition",
                "message": msg
            }

        # =========================================================
        # 3. EVALUASI MODEL: OPENCV FALLBACK
        # =========================================================
        else:
            if hasattr(cv2, 'compareHist'):
                correlation = float(cv2.compareHist(ref_encoding.astype(np.float32), live_encoding.astype(np.float32), cv2.HISTCMP_CORREL))
            else:
                norm1 = np.linalg.norm(ref_encoding)
                norm2 = np.linalg.norm(live_encoding)
                correlation = float(np.dot(ref_encoding, live_encoding) / (norm1 * norm2)) if (norm1 > 0 and norm2 > 0) else 0.0

            similarity = round(max(0.0, min(100.0, correlation * 100.0)), 2)
            sim_threshold = getattr(config, "SIMILARITY_THRESHOLD", 65.0)
            matched = similarity >= sim_threshold
            msg = "Wajah cocok (OpenCV Mode)!" if matched else f"Wajah tidak cocok ({similarity}%)"

            return {
                "matched": bool(matched),
                "similarity_score": round(similarity, 2),
                "distance": round(1.0 - correlation, 4),
                "face_detected": True,
                "engine": "visual_fallback",
                "message": msg
            }


# Singleton instance yang di-import oleh app.py
face_engine = FaceEngine()
