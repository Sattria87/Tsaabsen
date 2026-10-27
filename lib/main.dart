import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'utils/auth_service.dart';
import 'utils/app_nav.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error inisialisasi kamera: $e');
  }

  runApp(MaterialApp(
    navigatorKey: appNavigatorKey,
    debugShowCheckedModeBanner: false,
    home: const SplashRouter(),
  ));
}

/// ============================================================
/// SplashRouter — Splash Screen Video (assets/splash1.mp4)
/// ============================================================
/// Memutar video splash screen animasi MP4 pada pembukaan awal aplikasi.
/// Saat video selesai atau tombol Lewati ditekan:
///   - Ada sesi aktif  → langsung masuk ke HomeScreen
///   - Tidak ada sesi  → masuk ke LoginScreen
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  VideoPlayerController? _videoCtrl;
  bool _isVideoInitialized = false;
  Map<String, dynamic>? _savedUser;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initVideoAndSession();
  }

  Future<void> _initVideoAndSession() async {
    // 1. Baca sesi login user dari penyimpanan lokal
    AuthService.getSavedUser().then((userData) {
      if (mounted) {
        _savedUser = userData;
      }
    }).catchError((e) {
      debugPrint('[Splash Session Error]: $e');
    });

    // 2. Inisialisasi pemutar video splash1.mp4 dari assets
    try {
      _videoCtrl = VideoPlayerController.asset('assets/splash1.mp4');
      await _videoCtrl!.initialize();

      if (!mounted) return;

      setState(() {
        _isVideoInitialized = true;
      });

      _videoCtrl!.setVolume(1.0);
      _videoCtrl!.play();

      // Listener saat video selesai diputar
      _videoCtrl!.addListener(() {
        if (_videoCtrl != null &&
            _videoCtrl!.value.isInitialized &&
            !_navigated &&
            _videoCtrl!.value.position >= _videoCtrl!.value.duration) {
          _proceedToNextScreen();
        }
      });

      // Pengaman batas waktu maksimal durasi video (6 detik)
      Future.delayed(const Duration(milliseconds: 5800), () {
        if (!_navigated && mounted) {
          _proceedToNextScreen();
        }
      });
    } catch (e) {
      debugPrint('[Splash Video Init Error]: $e');
      // Jika video tidak dapat diputar pada perangkat tertentu, tunggu sejenak lalu lanjut
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (!_navigated && mounted) {
          _proceedToNextScreen();
        }
      });
    }
  }

  void _proceedToNextScreen() {
    if (_navigated || !mounted) return;
    _navigated = true;

    try {
      _videoCtrl?.pause();
    } catch (_) {}

    final userData = _savedUser;
    if (userData != null &&
        userData.isNotEmpty &&
        userData['username'] != null &&
        userData['username'].toString().trim().isNotEmpty) {
      debugPrint('[Splash] Sesi aktif ditemukan untuk: ${userData['username']}. Langsung ke HomeScreen.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(userData: userData),
        ),
      );
    } else {
      debugPrint('[Splash] Tidak ada sesi login tersimpan. Masuk ke LoginScreen.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E143C), // Warna latar belakang navy serasi video
      body: Stack(
        fit: StackFit.expand,
        children: [
          // A. Pemutar Video Splash
          if (_isVideoInitialized && _videoCtrl != null)
            Center(
              child: AspectRatio(
                aspectRatio: _videoCtrl!.value.aspectRatio,
                child: VideoPlayer(_videoCtrl!),
              ),
            )
          else
            // B. Tampilan Fallback selama video mempersiapkan diri
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.asset(
                        'assets/splash1.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'WG Absensi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sistem Absensi Karyawan',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),

          // Tombol "Lewati" di pojok kanan atas
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: _proceedToNextScreen,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const Text(
                  'Lewati',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}