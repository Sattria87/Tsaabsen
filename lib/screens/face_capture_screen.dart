import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../utils/mysql_helper.dart';
import '../utils/offline_attendance_helper.dart';
import '../main.dart'; // Akses variabel list 'cameras' dari main.dart
import 'clock_in_success_screen.dart';

class FaceCaptureScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String locationName;
  final int distance;
  final File? evidenceImage;

  const FaceCaptureScreen({
    super.key,
    required this.userData,
    this.locationName = 'Kantor Pusat',
    this.distance = 30,
    this.evidenceImage,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  XFile? _capturedImage; // Menampung foto selfie yang baru diambil
  bool _isCapturing = false; // Status saat proses menjepret kamera
  bool _isSubmitting = false; // Status saat proses submit Clock In ke backend
  bool _isVerifyingAI = false; // Status saat proses verifikasi AI berjalan
  String _aiVerificationStatus = ''; // Teks status verifikasi AI
  double? _similarityScore; // Skor kemiripan AI (persen)
  bool? _isAiMatched; // Hasil kecocokan AI

  // FITUR LIVENESS DETECTION INTERAKTIF (DUAL-FRAME MOTION LIVENESS)
  bool _isLivenessRunning = false;
  int _livenessStep = 0; // 0 = Idle, 1 = Frame 1 (Tatap Netral), 2 = Frame 2 (Kedip/Senyum), 3 = Analisis
  String _livenessStepText = '';
  double? _livenessMotionDelta;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      if (cameras.isEmpty) {
        cameras = await availableCameras();
      }
      if (cameras.isNotEmpty) {
        CameraDescription selectedCamera = cameras[0];

        // Cari secara spesifik kamera depan (front camera)
        for (var camera in cameras) {
          if (camera.lensDirection == CameraLensDirection.front) {
            selectedCamera = camera;
            break;
          }
        }

        // Jika belum ketemu tapi ada lebih dari 1 kamera, ambil kamera depan
        if (selectedCamera.lensDirection != CameraLensDirection.front &&
            cameras.length > 1) {
          selectedCamera = cameras[1];
        }

        final controller = CameraController(
          selectedCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        _controller = controller;
        _initializeControllerFuture = controller.initialize().then((_) {
          if (!mounted) return;
          setState(() {});
        });
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // 1. Ekstraksi sampel piksel untuk perbandingan gerakan liveness
  Future<Uint8List?> _extractSamplePixels(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 80);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Liveness] Gagal decode pixel: $e');
      return null;
    }
  }

  // Hitung rata-rata selisih intensitas piksel (Motion Score)
  double _calculateMotionScore(Uint8List p1, Uint8List p2) {
    final int minLen = p1.length < p2.length ? p1.length : p2.length;
    if (minLen == 0) return 0.0;

    double totalDiff = 0.0;
    int sampleCount = 0;
    for (int i = 0; i < minLen; i += 4) {
      final int rDiff = (p1[i] - p2[i]).abs();
      final int gDiff = (p1[i + 1] - p2[i + 1]).abs();
      final int bDiff = (p1[i + 2] - p2[i + 2]).abs();
      totalDiff += (rDiff + gDiff + bDiff) / 3.0;
      sampleCount++;
    }
    return sampleCount > 0 ? (totalDiff / sampleCount) : 0.0;
  }

  // 2. Alur Interaktif Liveness Detection Multi-Frame
  Future<void> _startLivenessSequence() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isLivenessRunning ||
        _isSubmitting) {
      return;
    }

    setState(() {
      _isLivenessRunning = true;
      _isCapturing = true;
      _livenessStep = 1;
      _livenessStepText = 'Tahap 1/2: Tatap lurus kamera...';
    });

    try {
      await _initializeControllerFuture;

      // Tunggu 800ms agar posisi wajah pengguna stabil di kamera
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // Jepret Frame 1 (Posisi Wajah Netral)
      final XFile frame1 = await _controller!.takePicture();
      debugPrint('[Liveness] Frame 1 (Netral) tersimpan di: ${frame1.path}');

      // Pindah ke Tahap 2: Minta Kedipan Mata / Senyuman
      if (!mounted) return;
      setState(() {
        _livenessStep = 2;
        _livenessStepText = 'Tahap 2/2: Sekarang KEDIPKAN MATA atau TERSENYUM!';
      });

      // Jeda 1.4 detik bagi pengguna untuk melakukan kedipan atau senyuman
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;

      // Jepret Frame 2 (Posisi Wajah Aktif)
      final XFile frame2 = await _controller!.takePicture();
      debugPrint('[Liveness] Frame 2 (Aktif) tersimpan di: ${frame2.path}');

      // Pindah ke Tahap 3: Analisis Perbedaan Gerakan
      if (!mounted) return;
      setState(() {
        _livenessStep = 3;
        _livenessStepText = 'Menganalisis keaslian gerakan wajah...';
      });

      final pixels1 = await _extractSamplePixels(frame1);
      final pixels2 = await _extractSamplePixels(frame2);

      double motionScore = 0.0;
      if (pixels1 != null && pixels2 != null) {
        motionScore = _calculateMotionScore(pixels1, pixels2);
      }
      debugPrint('[Liveness] Skor perbedaan gerakan (Motion Score): $motionScore');

      // Ambang batas: Foto kertas/layar HP biasanya memiliki selisih < 2.5
      // Manusia hidup yang berkedip/tersenyum menghasilkan selisih > 2.8
      const double kLivenessThreshold = 2.8;

      if (motionScore < kLivenessThreshold) {
        // GAGAL LIVENESS: Tidak ada gerakan wajah yang memadai (terindikasi foto mati / layar)
        if (!mounted) return;
        setState(() {
          _isLivenessRunning = false;
          _isCapturing = false;
          _livenessStep = 0;
          _livenessStepText = '';
        });

        _showLivenessFailedDialog(motionScore);
        return;
      }

      // BERHASIL LIVENESS: Gerakan hidup nyata terverifikasi!
      if (!mounted) return;
      setState(() {
        _capturedImage = frame2; // Gunakan frame 2 yang memiliki ekspresi hidup
        _livenessMotionDelta = motionScore;
        _isLivenessRunning = false;
        _isCapturing = false;
        _livenessStep = 0;
        _livenessStepText = '';
        _isVerifyingAI = false;
        _aiVerificationStatus = 'Liveness Terverifikasi! Foto siap diverifikasi Model AI';
        _similarityScore = null;
        _isAiMatched = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Liveness Berhasil: Gerakan wajah asli terdeteksi! (Skor: ${motionScore.toStringAsFixed(1)})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Liveness] Error sequence: $e');
      if (mounted) {
        setState(() {
          _isLivenessRunning = false;
          _isCapturing = false;
          _livenessStep = 0;
          _livenessStepText = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Terjadi kesalahan kamera saat verifikasi: $e'),
          ),
        );
      }
    }
  }

  // Dialog peringatan jika Liveness gagal (terdeteksi foto diam / layar HP)
  void _showLivenessFailedDialog(double score) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Liveness Gagal!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tidak terdeteksi gerakan wajah yang cukup. Sistem mendeteksi kemungkinan foto diam, kertas cetak, atau layar ponsel.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFB91C1C), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pastikan Anda berkedip perlahan atau tersenyum saat instruksi tahap ke-2 muncul di layar.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _startLivenessSequence();
            },
            child: const Text('Ulangi Verifikasi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 3. Foto Ulang / Reset
  void _retakePicture() {
    if (_isSubmitting || _isLivenessRunning) return;
    setState(() {
      _capturedImage = null;
      _isVerifyingAI = false;
      _aiVerificationStatus = '';
      _similarityScore = null;
      _isAiMatched = null;
      _isLivenessRunning = false;
      _livenessStep = 0;
      _livenessStepText = '';
      _livenessMotionDelta = null;
    });
  }

  /// Optimasi ukuran foto selfie dengan native engine Skia (resolusi 480px, ~200KB)
  /// Menghindari upload file mentah 3-5MB dari kamera HP yang memperlambat koneksi internet
  Future<String> _compressAndEncodeImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 480);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        final compressed = byteData.buffer.asUint8List();
        debugPrint(
          '[FaceCapture] Foto dioptimasi: ${(bytes.length / 1024).toStringAsFixed(1)} KB -> ${(compressed.length / 1024).toStringAsFixed(1)} KB',
        );
        return 'data:image/png;base64,${base64Encode(compressed)}';
      }
    } catch (e) {
      debugPrint(
        '[FaceCapture] Fallback kompresi gagal ($e), gunakan foto asli',
      );
    }
    final rawBytes = await file.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(rawBytes)}';
  }

  // 3. Konfirmasi & Verifikasi Wajah dengan Model AI lalu Submit Clock In
  Future<void> _submitClockIn() async {
    if (_capturedImage == null || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _isVerifyingAI = true;
      _aiVerificationStatus = 'Mengoptimalkan foto selfie...';
    });

    try {
      // 1. Kompres foto selfie ke ukuran optimal sebelum dikirim via internet
      final imageBase64 = await _compressAndEncodeImage(
        File(_capturedImage!.path),
      );
      final username = (widget.userData['username'] ?? '').toString();

      // 2. Verifikasi Wajah dengan Microservice AI (Face Recognition Engine)
      setState(() {
        _aiVerificationStatus = 'Menganalisis wajah dengan Model AI...';
      });

      final aiResult = await MySQLHelper.verifyFaceWithAI(
        username,
        imageBase64,
      );

      if (!mounted) return;

      final bool matched = aiResult['matched'] == true;
      final double score =
          (aiResult['similarity_score'] as num?)?.toDouble() ?? 0.0;
      final String aiMsg = aiResult['message']?.toString() ?? '';

      setState(() {
        _isVerifyingAI = false;
        _isAiMatched = matched;
        _similarityScore = score;
      });

      // JIKA HASIL TIDAK COCOK ATAU WAJAH TIDAK TERDETEKSI:
      if (!matched) {
        setState(() => _isSubmitting = false);

        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Row(
              children: const [
                Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 28),
                SizedBox(width: 10),
                Text(
                  'Verifikasi AI Gagal',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  aiMsg,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF334155),
                    height: 1.4,
                  ),
                ),
                if (score > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Skor Kemiripan Wajah:',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                        Text(
                          '${score.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Tips: Posisikan wajah Anda tegak lurus ke kamera dengan pencahayaan terang dan tanpa masker.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _retakePicture();
                },
                child: const Text(
                  'Ambil Ulang Foto',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }

      // 3. JIKA WAJAH TERVERIFIKASI OLEH MODEL AI: SIMPAN KE DATABASE
      setState(() {
        _aiVerificationStatus =
            'Wajah Cocok (${score.toStringAsFixed(1)}%)! Menyimpan absensi...';
      });

      String? evidenceBase64;
      if (widget.evidenceImage != null) {
        try {
          evidenceBase64 = await _compressAndEncodeImage(widget.evidenceImage!);
        } catch (evErr) {
          debugPrint('Error mengompres evidence: $evErr');
        }
      }

      bool success = await MySQLHelper.saveAttendance(
        username,
        'clock_in',
        reason: widget.locationName,
        image: imageBase64,
        evidenceImage: evidenceBase64,
      );

      if (!mounted) return;

      if (success) {
        // Tampilkan pesan sukses verifikasi AI
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            content: Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Verifikasi AI Berhasil: Kemiripan ${score.toStringAsFixed(1)}%!',
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );

        // Pindah ke layar Clock In Berhasil
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ClockInSuccessScreen(
              userData: widget.userData,
              locationName: widget.locationName,
              distance: widget.distance,
              similarity: score,
            ),
          ),
        );
      } else {
        // JIKA GAGAL JARINGAN / KONEKSI SERVER MATI -> SIMPAN KE OFFLINE QUEUE
        final bool offlineSaved = await OfflineAttendanceHelper.saveOfflineRecord(
          username: username,
          type: 'clock_in',
          reason: widget.locationName,
          imageBase64: imageBase64,
          evidenceImageBase64: evidenceBase64,
        );

        if (!mounted) return;

        if (offlineSaved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFD97706),
              duration: Duration(seconds: 4),
              content: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sinyal Tidak Stabil: Presensi disimpan Offline dan akan otomatis tersinkron saat internet aktif.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ClockInSuccessScreen(
                userData: widget.userData,
                locationName: '${widget.locationName} (Offline Saved)',
                distance: widget.distance,
                similarity: score,
              ),
            ),
          );
          return;
        }

        final errorMsg =
            MySQLHelper.lastSaveError ??
            'Gagal menyimpan absensi ke server! Silakan coba lagi.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      debugPrint('Error submit clock in: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Terjadi kesalahan verifikasi: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isSubmitting = false;
          _isVerifyingAI = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final bool hasCaptured = _capturedImage != null;

            return SafeArea(
              child: Column(
                children: [
                  // HEADER ATAS (Tombol Close/Back & Judul)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            hasCaptured ? Icons.arrow_back : Icons.close,
                            color: Colors.black,
                            size: 28,
                          ),
                          onPressed: () {
                            if (hasCaptured) {
                              _retakePicture();
                            } else {
                              Navigator.pop(context);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hasCaptured
                              ? 'Preview Foto Kehadiran'
                              : 'Ambil Foto Kehadiran',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // AREA KAMERA / PREVIEW FOTO
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: Colors.black,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (hasCaptured)
                              // TAMPILKAN FOTO HASIL JEPRETAN
                              Image.file(
                                File(_capturedImage!.path),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              )
                            else
                              // PREVIEW LIVE KAMERA DEPAN (MIRROR)
                              Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationY(3.14159),
                                child: _controller != null
                                    ? CameraPreview(_controller!)
                                    : const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                              ),

                            // PANDUAN BINGKAI FOTO (HANYA SAAT BELUM JEPRET)
                            if (!hasCaptured)
                              Center(
                                child: Container(
                                  width: 220,
                                  height: 290,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(130),
                                    border: Border.all(
                                      color: _isLivenessRunning
                                          ? (_livenessStep == 2
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFF38BDF8))
                                          : const Color(0xFF007AFF),
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_isLivenessRunning
                                                ? (_livenessStep == 2
                                                    ? const Color(0xFFF59E0B)
                                                    : const Color(0xFF38BDF8))
                                                : const Color(0xFF007AFF))
                                            .withValues(alpha: 0.25),
                                        blurRadius: 15,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // OVERLAY ANIMASI LANGKAH LIVENESS DETECTION
                            if (_isLivenessRunning)
                              Container(
                                color: Colors.black.withValues(alpha: 0.55),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          color: _livenessStep == 2
                                              ? const Color(0xFFD97706).withValues(alpha: 0.25)
                                              : const Color(0xFF007AFF).withValues(alpha: 0.25),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _livenessStep == 2
                                                ? const Color(0xFFF59E0B)
                                                : const Color(0xFF38BDF8),
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (_livenessStep == 2
                                                      ? const Color(0xFFF59E0B)
                                                      : const Color(0xFF007AFF))
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 20,
                                              spreadRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          _livenessStep == 1
                                              ? Icons.face_rounded
                                              : (_livenessStep == 2
                                                  ? Icons.remove_red_eye_rounded
                                                  : Icons.hourglass_top_rounded),
                                          color: Colors.white,
                                          size: 52,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        margin: const EdgeInsets.symmetric(horizontal: 24),
                                        decoration: BoxDecoration(
                                          color: _livenessStep == 2 ? const Color(0xFFD97706) : const Color(0xFF007AFF),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          _livenessStep == 1
                                              ? 'TAHAP 1: DIAM & TATAP KAMERA'
                                              : (_livenessStep == 2
                                                  ? 'TAHAP 2: KEDIPKAN MATA / SENYUM!'
                                                  : 'MENGANALISIS GERAKAN WAJAH...'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // BADGE PETUNJUK DI ATAS PREVIEW
                            Positioned(
                              top: 16,
                              left: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isLivenessRunning
                                          ? (_livenessStep == 2
                                              ? Icons.remove_red_eye_rounded
                                              : Icons.face_rounded)
                                          : (_isVerifyingAI
                                              ? Icons.psychology_rounded
                                              : (_isAiMatched == true
                                                  ? Icons.verified_rounded
                                                  : (hasCaptured
                                                      ? Icons.check_circle_outline
                                                      : Icons.camera_alt_outlined))),
                                      color: _isLivenessRunning
                                          ? (_livenessStep == 2
                                              ? const Color(0xFFFBBF24)
                                              : const Color(0xFF60A5FA))
                                          : (_isAiMatched == true
                                              ? const Color(0xFF4ADE80)
                                              : (_isVerifyingAI
                                                  ? const Color(0xFF60A5FA)
                                                  : (hasCaptured
                                                      ? const Color(0xFF4ADE80)
                                                      : Colors.white))),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _isLivenessRunning
                                            ? _livenessStepText
                                            : (_isVerifyingAI
                                                ? _aiVerificationStatus
                                                : (_isAiMatched == true
                                                    ? 'Wajah Cocok (${_similarityScore!.toStringAsFixed(1)}%)'
                                                    : (hasCaptured
                                                        ? (_livenessMotionDelta != null
                                                            ? 'Liveness Terverifikasi (Delta: ${_livenessMotionDelta!.toStringAsFixed(1)})'
                                                            : 'Foto siap diverifikasi Model AI')
                                                        : 'Posisikan wajah Anda pada lingkaran'))),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // OVERLAY ANIMASI SCANNING MODEL AI
                            if (_isVerifyingAI)
                              Container(
                                color: Colors.black.withValues(alpha: 0.6),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.5,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFF007AFF),
                                            width: 2.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF007AFF)
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 20,
                                              spreadRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.face_retouching_natural_rounded,
                                          color: Color(0xFF007AFF),
                                          size: 48,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'MODEL AI FACE RECOGNITION',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                        ),
                                        child: Text(
                                          _aiVerificationStatus,
                                          style: const TextStyle(
                                            color: Color(0xFF93C5FD),
                                            fontSize: 12.5,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const SizedBox(
                                        width: 130,
                                        child: LinearProgressIndicator(
                                          backgroundColor: Colors.white24,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Color(0xFF007AFF),
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // BADGE SUKSES KEMIRIPAN AI SETELAH VERIFIKASI
                            if (_similarityScore != null &&
                                _isAiMatched == true)
                              Positioned(
                                bottom: 16,
                                left: 16,
                                right: 16,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF16A34A)
                                        .withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.verified_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Wajah Terverifikasi (${_similarityScore!.toStringAsFixed(1)}%)',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // TOMBOL AKSI BAGIAN BAWAH
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: hasCaptured
                        // SETELAH SELESAI SELFIE: BERIKAN OPSI "GANTI FOTO" ATAU "VERIFIKASI AI & CLOCK IN"
                        ? Row(
                            children: [
                              // 1. TOMBOL GANTI FOTO
                              Expanded(
                                child: SizedBox(
                                  height: 55,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0xFF007AFF),
                                        width: 1.8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                    onPressed: _isSubmitting
                                        ? null
                                        : _retakePicture,
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      color: Color(0xFF007AFF),
                                    ),
                                    label: const Text(
                                      'Ganti Foto',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF007AFF),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              // 2. TOMBOL VERIFIKASI AI & CLOCK IN
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 55,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00A800),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: _isSubmitting
                                        ? null
                                        : _submitClockIn,
                                    icon: _isSubmitting
                                        ? const SizedBox.shrink()
                                        : const Icon(
                                            Icons.verified_user_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                    label: _isSubmitting
                                        ? const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Verifikasi AI...',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Text(
                                            'Verifikasi AI & Clock In',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        // SEBELUM SELFIE: INSTRUKSI LIVENESS & TOMBOL VERIFIKASI WAJAH
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // KARTU TANTANGAN LIVENESS DETECTION INTERAKTIF
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: _isLivenessRunning
                                      ? (_livenessStep == 2 ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF))
                                      : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _isLivenessRunning
                                        ? (_livenessStep == 2 ? const Color(0xFFFDE68A) : const Color(0xFF93C5FD))
                                        : const Color(0xFF93C5FD),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: _isLivenessRunning && _livenessStep == 2
                                            ? const Color(0xFFD97706)
                                            : const Color(0xFF007AFF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _isLivenessRunning
                                            ? (_livenessStep == 2 ? Icons.remove_red_eye_rounded : Icons.face_rounded)
                                            : Icons.security_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _isLivenessRunning ? 'Proses Deteksi Gerakan Hidup:' : 'Verifikasi Keaslian Wajah (Liveness):',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: _isLivenessRunning && _livenessStep == 2
                                                  ? const Color(0xFF92400E)
                                                  : const Color(0xFF1E3A8A),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _isLivenessRunning
                                                ? _livenessStepText
                                                : 'Tatap kamera lalu kedipkan mata atau tersenyum saat diminta.',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: _isLivenessRunning && _livenessStep == 2
                                                  ? const Color(0xFFB45309)
                                                  : const Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isLivenessRunning && _livenessStep == 2
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFF007AFF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: (_isCapturing || _isLivenessRunning) ? null : _startLivenessSequence,
                                  icon: _isLivenessRunning
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.face_retouching_natural_rounded,
                                          color: Colors.white,
                                        ),
                                  label: Text(
                                    _isLivenessRunning
                                        ? _livenessStepText
                                        : 'Mulai Verifikasi Wajah (Liveness)',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
