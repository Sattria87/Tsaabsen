import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'utils/auth_service.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error inisialisasi kamera: $e');
  }

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SplashRouter(),
  ));
}

/// ============================================================
/// SplashRouter — Pengarah Awal Berdasarkan Sesi Login
/// ============================================================
/// Widget ini ditampilkan pertama kali saat aplikasi dibuka.
/// Selama mengecek sesi, tampilkan splash screen loading.
/// Setelah selesai:
///   - Ada sesi aktif  → langsung ke HomeScreen (login persisten)
///   - Tidak ada sesi  → ke LoginScreen
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    // Animasi fade-in logo saat splash
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);

    // Cek sesi setelah frame pertama selesai render
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    try {
      // Jalankan animasi splash minimal 800ms dan pembacaan sesi secara paralel
      final results = await Future.wait([
        Future.delayed(const Duration(milliseconds: 800)),
        AuthService.getSavedUser(),
      ]);

      if (!mounted) return;

      final userData = results[1] as Map<String, dynamic>?;

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
        return;
      }

      debugPrint('[Splash] Tidak ada sesi login tersimpan. Masuk ke LoginScreen.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } catch (e, stack) {
      debugPrint('[Splash CheckSession Error] $e\n$stack');
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark navy sesuai tema app
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── LOGO / IKON ──────────────────────────────
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
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.business_center_rounded,
                        size: 44,
                        color: Color(0xFF0F172A),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── NAMA APLIKASI ────────────────────────────
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
              const SizedBox(height: 48),

              // ── LOADING INDICATOR ────────────────────────
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}