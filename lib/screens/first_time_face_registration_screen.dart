import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../utils/auth_service.dart';
import '../utils/mysql_helper.dart';
import 'home_screen.dart';

/// ============================================================
/// FirstTimeFaceRegistrationScreen — Onboarding Perekaman Wajah AI
/// ============================================================
/// Muncul otomatis saat karyawan pertama kali login jika belum
/// memiliki foto wajah acuan AI di sistem.
class FirstTimeFaceRegistrationScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const FirstTimeFaceRegistrationScreen({
    super.key,
    required this.userData,
  });

  @override
  State<FirstTimeFaceRegistrationScreen> createState() =>
      _FirstTimeFaceRegistrationScreenState();
}

class _FirstTimeFaceRegistrationScreenState
    extends State<FirstTimeFaceRegistrationScreen> {
  CameraController? _cameraController;
  Future<void>? _initCameraFuture;
  XFile? _capturedImage;
  bool _isCapturing = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initFrontCamera();
  }

  Future<void> _initFrontCamera() async {
    setState(() => _errorMessage = null);
    try {
      if (cameras.isEmpty) {
        cameras = await availableCameras();
      }

      if (cameras.isEmpty) {
        setState(() {
          _errorMessage =
              'Kamera tidak terdeteksi pada perangkat ini. Pastikan izin kamera aktif.';
        });
        return;
      }

      // Prioritaskan kamera depan (front camera)
      CameraDescription selectedCamera = cameras[0];
      for (var cam in cameras) {
        if (cam.lensDirection == CameraLensDirection.front) {
          selectedCamera = cam;
          break;
        }
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _cameraController = controller;
      _initCameraFuture = controller.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });

      setState(() {});
    } catch (e) {
      debugPrint('[FirstTimeFace] Error kamera: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal mengakses kamera: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // Ambil Foto Selfie Acuan
  Future<void> _takePhoto() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);
    try {
      await _initCameraFuture;
      final file = await _cameraController!.takePicture();
      if (!mounted) return;
      setState(() {
        _capturedImage = file;
        _isCapturing = false;
      });
    } catch (e) {
      debugPrint('[FirstTimeFace] Error ambil foto: $e');
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengambil foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Simpan Foto ke Server & Update Sesi
  Future<void> _saveFaceReference() async {
    if (_capturedImage == null || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      final username = widget.userData['username'] ?? '';
      if (username.isEmpty) {
        throw Exception('Username tidak valid');
      }

      // Baca byte gambar dan ubah ke Base64
      final bytes = await File(_capturedImage!.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      final result = await MySQLHelper.registerFace(username, base64Image);

      if (!mounted) return;

      if (result['success'] == true) {
        final newFacePath = result['face_image']?.toString();

        // Update objek userData lokal
        widget.userData['face_image'] = newFacePath;
        widget.userData['needs_face_registration'] = false;

        // Simpan pembaruan ke SharedPreferences
        await AuthService.saveSession(widget.userData);

        if (!mounted) return;

        // Tampilkan dialog sukses yang informatif
        _showSuccessDialog();
      } else {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Gagal menyimpan foto acuan'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[FirstTimeFace Save Error]: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF10B981),
                size: 46,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Wajah Berhasil Didaftarkan!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Foto ini telah tersimpan sebagai data master acuan AI Face Recognition untuk absensi harian Anda.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A192F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(userData: widget.userData),
                    ),
                    (route) => false,
                  );
                },
                child: const Text(
                  'Masuk ke Beranda',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.userData['name']?.toString().isNotEmpty == true
        ? widget.userData['name'].toString()
        : (widget.userData['username'] ?? 'Karyawan');

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Header Informasi
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.face_retouching_natural_rounded,
                          color: Color(0xFF38BDF8),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Perekaman Wajah AI',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Halo $displayName, ambil 1 foto wajah Anda sebagai acuan master untuk absensi selanjutnya.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF94A3B8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // 2. Area Kamera / Preview Foto
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: _capturedImage != null
                              ? const Color(0xFF10B981)
                              : const Color(0xFF38BDF8),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_capturedImage != null
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF38BDF8))
                                .withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_capturedImage != null)
                            Image.file(
                              File(_capturedImage!.path),
                              fit: BoxFit.cover,
                            )
                          else if (_cameraController != null &&
                              _cameraController!.value.isInitialized)
                            CameraPreview(_cameraController!)
                          else if (_errorMessage != null)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.videocam_off_rounded,
                                      color: Colors.redAccent,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: _initFrontCamera,
                                      icon: const Icon(Icons.refresh, size: 16),
                                      label: const Text('Coba Lagi'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF38BDF8),
                              ),
                            ),

                          // Panduan Lingkaran Wajah (Face Oval Guide)
                          if (_capturedImage == null &&
                              _cameraController != null &&
                              _cameraController!.value.isInitialized)
                            Center(
                              child: Container(
                                width: 200,
                                height: 260,
                                decoration: BoxDecoration(
                                  shape: BoxShape.rectangle,
                                  borderRadius:
                                      BorderRadius.all(Radius.elliptical(200, 260)),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),

                          // Indikator Loading Saat Menyimpan
                          if (_isSaving)
                            Container(
                              color: Colors.black.withValues(alpha: 0.65),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    CircularProgressIndicator(
                                      color: Color(0xFF10B981),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Mendaftarkan foto acuan AI...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
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
              ),
            ),

            // 3. Petunjuk & Tombol Aksi Bawah
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                children: [
                  // Tips
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          color: Color(0xFFFBBF24),
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Pastikan pencahayaan cukup, wajah tegak menghadap kamera, dan tidak memakai masker.',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Tombol Kontrol
                  if (_capturedImage == null) ...[
                    // Tombol Ambil Foto
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                        ),
                        onPressed: _isCapturing ? null : _takePhoto,
                        icon: _isCapturing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.camera_alt_rounded, size: 22),
                        label: Text(
                          _isCapturing
                              ? 'Mengambil Foto...'
                              : 'Ambil Foto Wajah Sekarang',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Tombol Review: Ambil Ulang vs Simpan
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFCBD5E1),
                              side: const BorderSide(color: Color(0xFF475569)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _isSaving
                                ? null
                                : () {
                                    setState(() => _capturedImage = null);
                                  },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text(
                              'Foto Ulang',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            onPressed: _isSaving ? null : _saveFaceReference,
                            icon: const Icon(Icons.check_circle_rounded, size: 18),
                            label: const Text(
                              'Simpan Acuan AI',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

