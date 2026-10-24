import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/mysql_helper.dart';
import '../utils/auth_service.dart';
import '../widgets/employee_avatar.dart';
import 'login_screen.dart';
import 'location_verification_screen.dart';
import 'permission_screen.dart';
import 'clock_out_success_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const HomeScreen({super.key, required this.userData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  bool _isLoading = true;
  bool _hasClockedIn = false;
  bool _hasClockedOut = false;
  String _clockInTime = '--:--';
  String _clockInLocation = 'Kantor Pusat';
  String? _clockInKeterangan;
  String _clockOutTime = '--:--';
  bool _isSubmittingClockOut = false;
  Timer? _dailyResetTimer;

  // State untuk Pengajuan Izin / Sakit
  bool _hasPermission = false;
  String? _permissionType;
  String? _permissionStatus; // 'Pending', 'Approved', 'Rejected'
  String? _permissionReason;
  String? _permissionTime;

  @override
  void initState() {
    super.initState();
    _checkAttendanceStatus();
    _scheduleNextResetTimer();
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // Menjadwalkan reset otomatis saat jam menunjukkan 23:55
  void _scheduleNextResetTimer() {
    _dailyResetTimer?.cancel();
    final now = DateTime.now();
    var nextReset = DateTime(now.year, now.month, now.day, 23, 55, 0);
    if (!now.isBefore(nextReset)) {
      nextReset = nextReset.add(const Duration(days: 1));
    }
    final diff = nextReset.difference(now);
    _dailyResetTimer = Timer(diff, () {
      if (mounted) {
        debugPrint('Waktu 23:55 tercapai: Reset absensi harian otomatis');
        _checkAttendanceStatus();
        _scheduleNextResetTimer();
      }
    });
  }

  // Cek status absensi hari ini dari Backend
  Future<void> _checkAttendanceStatus() async {
    setState(() => _isLoading = true);

    try {
      final username = widget.userData['username'] ?? '';
      final status = await MySQLHelper.getTodayAttendanceStatus(username);

      if (!mounted) return;
      if (status != null) {
        setState(() {
          _hasClockedIn = status['hasClockedIn'] ?? false;
          _hasClockedOut = status['hasClockedOut'] ?? false;
          _clockInTime = status['clockInTime'] ?? '--:--';
          _clockInLocation = status['clockInLocation'] ?? 'Kantor Pusat';
          _clockInKeterangan = status['clockInKeterangan'];
          _clockOutTime = status['clockOutTime'] ?? '--:--';

          // Hitung keterangan jika belum ada dari backend
          if ((_clockInKeterangan == null || _clockInKeterangan!.isEmpty) &&
              _clockInTime.isNotEmpty &&
              _clockInTime != '--:--') {
            try {
              final parts = _clockInTime.split(':');
              final h = int.parse(parts[0]);
              final m = int.parse(parts[1]);
              final tot = h * 60 + m;
              if (tot < 530) {
                _clockInKeterangan = 'Sangat Baik';
              } else if (tot <= 540) {
                _clockInKeterangan = 'Baik';
              } else {
                _clockInKeterangan = 'Kurang Baik';
              }
            } catch (_) {}
          }

          // Data status pengajuan izin
          _hasPermission = status['hasPermission'] ?? false;
          _permissionType = status['permissionType'];
          _permissionStatus = status['permissionStatus'];
          _permissionReason = status['permissionReason'];
          _permissionTime = status['permissionTime'];

          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error cek status absensi: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Format tanggal dalam bahasa Inggris persis seperti gambar: "Thursday, October 1 2026"
  String _getFormattedDate() {
    final now = DateTime.now();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final dayName = days[now.weekday - 1];
    final monthName = months[now.month - 1];
    return '$dayName, $monthName ${now.day} ${now.year}';
  }

  // Salam dinamis menyesuaikan waktu
  String _getGreetingText() {
    final hour = DateTime.now().hour;
    if (hour >= 4 && hour < 12) {
      return 'Apa yang kamu perlukan pagi ini?';
    } else if (hour >= 12 && hour < 15) {
      return 'Apa yang kamu perlukan siang ini?';
    } else if (hour >= 15 && hour < 18) {
      return 'Apa yang kamu perlukan sore ini?';
    } else {
      return 'Apa yang kamu perlukan malam ini?';
    }
  }

  // Dialog konfirmasi Clock Out
  void _confirmClockOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Konfirmasi Clock Out',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'Apakah Anda yakin ingin melakukan Clock Out dari $_clockInLocation sekarang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleClockOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Ya, Clock Out',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Proses simpan Clock Out ke Backend
  Future<void> _handleClockOut() async {
    setState(() => _isSubmittingClockOut = true);

    final now = DateTime.now();
    final formattedNow =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    try {
      bool success = await MySQLHelper.saveAttendance(
        widget.userData['username'],
        'clock_out',
        reason: _clockInLocation,
      );

      if (!mounted) return;

      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ClockOutSuccessScreen(
              userData: widget.userData,
              locationName: _clockInLocation,
              clockInTime: _clockInTime,
              clockOutTime: formattedNow,
            ),
          ),
        );
      } else {
        setState(() => _isSubmittingClockOut = false);
        final errorMsg = MySQLHelper.lastSaveError ??
            'Gagal melakukan Clock Out ke server!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error Clock Out: $e');
      if (mounted) {
        setState(() => _isSubmittingClockOut = false);
      }
    }
  }

  /// Tampilkan dialog konfirmasi Logout.
  /// Jika dikonfirmasi: hapus sesi tersimpan → kembali ke LoginScreen.
  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFF0F172A), size: 22),
            SizedBox(width: 10),
            Text(
              'Konfirmasi Logout',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Apakah Anda yakin ingin keluar?\nAnda perlu login kembali untuk mengakses aplikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // ✅ Hapus sesi tersimpan agar user diarahkan ke LoginScreen saat buka ulang
      await AuthService.clearSession();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String userName = widget.userData['name'] ?? 'Karyawan';

    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _checkAttendanceStatus,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // ==========================================
                    // 1. HEADER ATAS (NAVY CURVED + FLOATING CARD)
                    // ==========================================
                    _buildHeaderSection(userName),

                    const SizedBox(height: 28),

                    // ==========================================
                    // 2. KONTEN TENGAH BERDASARKAN STATUS ABSEN
                    // ==========================================
                    if (_hasPermission)
                      _buildPermissionStatusView()
                    else if (!_hasClockedIn)
                      _buildClockInView()
                    else if (_hasClockedIn && !_hasClockedOut)
                      _buildClockOutView()
                    else
                      _buildCompletedView(),
                  ],
                ),
              ),
            ),
    );
  }

  // WIDGET HEADER ATAS: Background Navy melengkung + Card Profil Emas
  Widget _buildHeaderSection(String userName) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // A. Background Navy Lengkung
        ClipPath(
          clipper: HeaderArcClipper(),
          child: Container(
            height: 180,
            width: double.infinity,
            color: const Color(0xFF0F1A3A),
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14, top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          tooltip: 'Segarkan Status',
                          onPressed: _isLoading ? null : _checkAttendanceStatus,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          tooltip: 'Logout',
                          onPressed: () => _confirmLogout(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // B. Card Profil Mengambang dengan Garis Tepi Emas (Ditata lebih ke bawah)
        Padding(
          padding: const EdgeInsets.only(top: 85, left: 20, right: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(
                  0xFFFFB800,
                ), // Border emas persis seperti gambar
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                EmployeeAvatarWidget(userData: widget.userData, radius: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Holla,',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        height: 1,
                        width: double.infinity,
                        color: const Color(0xFFE5E7EB),
                      ),
                      Text(
                        _getFormattedDate(),
                        style: const TextStyle(
                          color: Color(0xFFF97316),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // TAMPILAN 1: BELUM CLOCK IN (Carousel Clock in / Izin)
  Widget _buildClockInView() {
    return Column(
      children: [
        const SizedBox(height: 14),

        // Teks Sapaan "Apa yang kamu perlukan pagi ini?"
        Text(
          _getGreetingText(),
          style: const TextStyle(
            color: Color(0xFF4B5563),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),

        // Carousel Mascot dengan Watermark TSA
        SizedBox(
          height: 230,
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            children: [
              // Halaman 0: Clock In Mascot
              _buildMascotSlide(mascotAsset: 'assets/clockin.png'),
              // Halaman 1: Izin Mascot
              _buildMascotSlide(
                mascotAsset: 'assets/image-removebg-preview (1).png',
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Indikator Dots (Kuning & Abu-abu)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentIndex == 0
                    ? const Color(0xFFFFB800)
                    : const Color(0xFFD1D5DB),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentIndex == 1
                    ? const Color(0xFFFFB800)
                    : const Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Tombol Biru Terpusat "Clock in" / "Izin"
        Center(
          child: SizedBox(
            width: 190,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                if (_currentIndex == 0) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          LocationVerificationScreen(userData: widget.userData),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PermissionScreen(userData: widget.userData),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(
                  0xFF007AFF,
                ), // Biru cerah persis seperti gambar
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 0,
              ),
              child: Text(
                _currentIndex == 0 ? 'Clock in' : 'Izin',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),
      ],
    );
  }

  // Slide Maskot: Watermark TSA di belakang + Karakter 3D di depan
  Widget _buildMascotSlide({required String mascotAsset}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Watermark TSA
        Opacity(
          opacity: 0.85,
          child: Image.asset(
            'assets/Minimalist TSA Watermark Logo.png',
            width: 240,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
        ),

        // Maskot Petugas 3D
        Image.asset(
          mascotAsset,
          height: 200,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.person, size: 120, color: Colors.grey),
        ),
      ],
    );
  }

  // TAMPILAN 2: SUDAH CLOCK IN -> TAMPILAN CLOCK OUT
  Widget _buildClockOutView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // Ikon Jam Melingkar Biru dengan Panah (Sesuai Desain)
          const ClockOutRefreshIcon(size: 80),

          const SizedBox(height: 18),

          // Teks Ajakan: Klik Tombol untuk Clock Out
          const Text(
            'Klik Tombol untuk\nClock Out',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
              height: 1.35,
            ),
          ),

          const SizedBox(height: 24),

          // Tombol Biru Clock Out
          Center(
            child: SizedBox(
              width: 210,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmittingClockOut ? null : _confirmClockOut,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: _isSubmittingClockOut
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Clock Out',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 36),

          // Card Informasi Clock In & Lokasi (Sesuai Desain)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Baris 1: Jam Clock In
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      color: Color(0xFF6B7280),
                      size: 26,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Clock In',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _clockInTime.isNotEmpty && _clockInTime != '--:--'
                              ? _clockInTime
                              : '08:50',
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const Divider(
                  height: 28,
                  color: Color(0xFFF1F5F9),
                  thickness: 1.2,
                ),

                // Baris 2: Lokasi Kantor
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Color(0xFF6B7280),
                      size: 26,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lokasi',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _clockInLocation.isNotEmpty
                              ? _clockInLocation
                              : 'Kantor Pusat',
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Baris 3: Keterangan Kehadiran (Sangat Baik / Baik / Kurang Baik)
                if (_clockInKeterangan != null && _clockInKeterangan!.isNotEmpty) ...[
                  const Divider(
                    height: 28,
                    color: Color(0xFFF1F5F9),
                    thickness: 1.2,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_outlined,
                        color: Color(0xFF6B7280),
                        size: 26,
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Keterangan',
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildKeteranganBadge(_clockInKeterangan!),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // TAMPILAN 3: SUDAH CLOCK OUT (ABSENSI HARI INI SELESAI)
  Widget _buildCompletedView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          const SizedBox(height: 20),

          const Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Color(0xFF00A800),
          ),

          const SizedBox(height: 16),

          const Text(
            'Absensi Hari Ini Selesai!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Anda telah menyelesaikan Clock In dan Clock Out untuk siklus hari ini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
          ),

          const SizedBox(height: 24),

          // Rangkuman Jam
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text(
                      'Clock In',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _clockInTime,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Container(width: 1, height: 32, color: const Color(0xFFE5E7EB)),
                Column(
                  children: [
                    const Text(
                      'Clock Out',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _clockOutTime,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                if (_clockInKeterangan != null && _clockInKeterangan!.isNotEmpty) ...[
                  Container(width: 1, height: 32, color: const Color(0xFFE5E7EB)),
                  Column(
                    children: [
                      const Text(
                        'Keterangan',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      _buildKeteranganBadge(_clockInKeterangan!),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // Helper Badge Keterangan Kehadiran
  Widget _buildKeteranganBadge(String ket) {
    Color bg;
    Color textColor;
    IconData icon;

    if (ket == 'Sangat Baik') {
      bg = const Color(0xFFE8F5E9);
      textColor = const Color(0xFF00A800);
      icon = Icons.stars_rounded;
    } else if (ket == 'Baik') {
      bg = const Color(0xFFE0F2FE);
      textColor = const Color(0xFF007AFF);
      icon = Icons.thumb_up_alt_rounded;
    } else {
      bg = const Color(0xFFFFE4E6);
      textColor = const Color(0xFFE11D48);
      icon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            ket,
            style: TextStyle(
              color: textColor,
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // TAMPILAN 4: STATUS PENGAJUAN IZIN (PENDING / ABSEN IZIN / ALPHA)
  Widget _buildPermissionStatusView() {
    final statusLower = (_permissionStatus ?? 'pending').toLowerCase();
    final bool isPending = statusLower == 'pending';
    final bool isApproved = statusLower == 'approved';
    final bool isRejected = statusLower == 'rejected';

    // Format tipe izin yang rapi
    String typeLabel = 'Izin';
    if (_permissionType != null) {
      if (_permissionType!.contains('sakit')) {
        typeLabel = 'Sakit';
      } else if (_permissionType!.contains('keperluan')) {
        typeLabel = 'Izin Keperluan';
      } else if (_permissionType!.contains('cuti')) {
        typeLabel = 'Cuti';
      }
    }

    // Konfigurasi tema warna & teks berdasarkan status
    final Color themeColor;
    final Color bgLightColor;
    final IconData statusIcon;
    final String mainStatusText;
    final String statusSubtitle;
    final String badgeText;

    if (isApproved) {
      themeColor = const Color(0xFF10B981); // Emerald Hijau
      bgLightColor = const Color(0xFFECFDF5);
      statusIcon = Icons.check_circle_rounded;
      mainStatusText = 'Absen Izin';
      statusSubtitle =
          'Pengajuan izin Anda telah disetujui oleh admin di web dashboard. Kehadiran Anda hari ini terekam sebagai Absen Izin.';
      badgeText = 'DISETUJUI ADMIN';
    } else if (isRejected) {
      themeColor = const Color(0xFFEF4444); // Merah Terang
      bgLightColor = const Color(0xFFFEF2F2);
      statusIcon = Icons.cancel_rounded;
      mainStatusText = 'Alpha (Tidak Hadir)';
      statusSubtitle =
          'Pengajuan izin Anda tidak disetujui oleh admin. Status kehadiran Anda untuk hari ini tercatat sebagai Alpha / Tidak Hadir.';
      badgeText = 'TIDAK DISETUJUI';
    } else {
      // Pending
      themeColor = const Color(0xFFF59E0B); // Amber / Kuning Emas
      bgLightColor = const Color(0xFFFFFBEB);
      statusIcon = Icons.hourglass_top_rounded;
      mainStatusText = 'Status: Pending';
      statusSubtitle =
          'Pengajuan izin Anda telah terkirim dan sedang menunggu persetujuan dari admin di web. Mohon menunggu atau segarkan status secara berkala.';
      badgeText = 'MENUNGGU PERSETUJUAN';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // 1. IKON BESAR BERLATAR BELAKANG HALUS
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: bgLightColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: themeColor.withValues(alpha: 0.3),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              statusIcon,
              size: 46,
              color: themeColor,
            ),
          ),

          const SizedBox(height: 18),

          // 2. BADGE KAPSUL STATUS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: bgLightColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: themeColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: themeColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 3. TEKS STATUS UTAMA
          Text(
            mainStatusText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isRejected
                  ? const Color(0xFFDC2626)
                  : (isApproved ? const Color(0xFF047857) : const Color(0xFF1E293B)),
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 8),

          // 4. DESKRIPSI PENJELASAN
          Text(
            statusSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              height: 1.45,
            ),
          ),

          const SizedBox(height: 22),

          // 5. KARTU DETAIL INFORMASI PENGAJUAN
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                // Jenis Pengajuan
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Jenis Pengajuan',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22, color: Color(0xFFF3F4F6)),

                // Waktu Pengajuan
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Waktu',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _permissionTime ?? '--:--',
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22, color: Color(0xFFF3F4F6)),

                // Status di Sistem
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Status Absensi',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: bgLightColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isApproved
                            ? 'Absen Izin'
                            : (isRejected ? 'Alpha' : 'Pending'),
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                // Alasan (jika ada)
                if (_permissionReason != null &&
                    _permissionReason!.trim().isNotEmpty) ...[
                  const Divider(height: 22, color: Color(0xFFF3F4F6)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Keterangan / Alasan:',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _permissionReason!,
                          style: const TextStyle(
                            color: Color(0xFF374151),
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 6. TOMBOL AKSI BERDASARKAN STATUS
          if (isPending) ...[
            // Tombol Segarkan Status untuk Pending
            Center(
              child: SizedBox(
                width: 200,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _checkAttendanceStatus,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text(
                    'Segarkan Status',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F1A3A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tarik layar ke bawah untuk cek status terbaru',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5),
            ),
          ] else if (isRejected) ...[
            // Status ditolak (Alpha): Hanya opsi ajukan ulang izin, tidak ada opsi Clock In
            Center(
              child: SizedBox(
                width: 220,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            PermissionScreen(userData: widget.userData),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_note_rounded, size: 20),
                  label: const Text(
                    'Ajukan Ulang Izin',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F1A3A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: _isLoading ? null : _checkAttendanceStatus,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Segarkan Status',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ),
            ),
          ] else ...[
            // Approved: Tombol refresh untuk memastikan
            Center(
              child: TextButton.icon(
                onPressed: _checkAttendanceStatus,
                icon: const Icon(Icons.sync_rounded, size: 18, color: Color(0xFF6B7280)),
                label: const Text(
                  'Perbarui Data',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 12.5),
                ),
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// Clipper untuk kurva header atas melengkung
class HeaderArcClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 24);
    path.quadraticBezierTo(
      size.width / 2,
      size.height + 24,
      size.width,
      size.height - 24,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
