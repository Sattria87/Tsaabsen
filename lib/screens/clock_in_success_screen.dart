import 'package:flutter/material.dart';

import 'home_screen.dart';

class ClockInSuccessScreen extends StatelessWidget {
  final Map<String, dynamic> userData;
  final String locationName;
  final int distance;
  final double? similarity;

  const ClockInSuccessScreen({
    super.key,
    required this.userData,
    required this.locationName,
    required this.distance,
    this.similarity,
  });

  // Format jam digital (contoh: 08:50)
  String _getFormattedTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  // Format tanggal bahasa Indonesia (contoh: Kamis, 1 Oktober 2026)
  String _getFormattedDate() {
    final now = DateTime.now();
    const days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];

    final dayName = days[now.weekday - 1];
    final monthName = months[now.month - 1];
    return '$dayName, ${now.day} $monthName ${now.year}';
  }

  // Hitung keterangan performa kedatangan sesuai aturan:
  // - dibawah jam 08:50: "Sangat Baik"
  // - 08:50 sampai 09:00: "Baik"
  // - diatas 09:00: "Kurang Baik"
  Map<String, dynamic> _getClockInKeterangan() {
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;

    if (minutes < 530) {
      // Dibawah jam 08:50 (530 menit)
      return {
        'text': 'Sangat Baik',
        'color': const Color(0xFF00A800), // Hijau
        'bgColor': const Color(0xFFE8F5E9),
        'icon': Icons.stars_rounded,
      };
    } else if (minutes <= 540) {
      // Diantara jam 08:50 s/d 09:00 (530 - 540 menit)
      return {
        'text': 'Baik',
        'color': const Color(0xFF007AFF), // Biru
        'bgColor': const Color(0xFFE0F2FE),
        'icon': Icons.thumb_up_alt_rounded,
      };
    } else {
      // Diatas jam 09:00 (> 540 menit)
      return {
        'text': 'Kurang Baik',
        'color': const Color(0xFFE11D48), // Merah
        'bgColor': const Color(0xFFFFE4E6),
        'icon': Icons.warning_amber_rounded,
      };
    }
  }

  void _navigateToHome(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => HomeScreen(userData: userData)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String userName = userData['name']?.toString().isNotEmpty == true
        ? userData['name'].toString()
        : (userData['username']?.toString().isNotEmpty == true
              ? userData['username'].toString()
              : 'Susi Februari');

    final String displayLocation = locationName.isNotEmpty
        ? locationName
        : 'Kantor Pusat';
    final keteranganData = _getClockInKeterangan();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _navigateToHome(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 20.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // 1. LINGKARAN HIJAU DENGAN CENTANG PUTIH (SESUAI GAMBAR)
                  Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00A800), // Hijau terang persis referensi
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 50,
                      weight: 700,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 2. JUDUL TEKS HIJAU "Clock In Berhasil"
                  const Text(
                    'Clock In Berhasil',
                    style: TextStyle(
                      color: Color(0xFF00A800),
                      fontSize: 18.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 3. JAM DIGITAL BESAR (08:50)
                  Text(
                    _getFormattedTime(),
                    style: const TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: -1.0,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // 4. TANGGAL LENGKAP (Kamis, 1 Oktober 2026)
                  Text(
                    _getFormattedDate(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // 5. KARTU INFORMASI PUTIH (ELEVASI LEMBUT & CORNER 24px)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 26,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow('Nama', userName),
                        const Divider(height: 28, color: Color(0xFFEEEEEE)),
                        _buildInfoRow('Lokasi', displayLocation),
                        const Divider(height: 28, color: Color(0xFFEEEEEE)),
                        _buildInfoRow('Jarak', '$distance meter'),
                        if (similarity != null) ...[
                          const Divider(height: 28, color: Color(0xFFEEEEEE)),
                          _buildInfoRow('Verifikasi AI', 'Cocok (${similarity!.toStringAsFixed(1)}%)'),
                        ],
                        const Divider(height: 28, color: Color(0xFFEEEEEE)),
                        _buildKeteranganRow(keteranganData),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 6. TOMBOL HIJAU PILL "Back to Home" (PERSIS REFERENSI)
                  SizedBox(
                    width: 220,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _navigateToHome(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFF00A800,
                        ), // Hijau tombol
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: const Text(
                        'Back to Home',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Baris informasi kartu: label abu-abu di kiri, nilai hitam tebal di kanan
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Baris Keterangan Kehadiran (Sangat Baik / Baik / Kurang Baik) dengan badge warna
  Widget _buildKeteranganRow(Map<String, dynamic> ket) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Keterangan',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: ket['bgColor'] as Color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ket['icon'] as IconData,
                size: 14,
                color: ket['color'] as Color,
              ),
              const SizedBox(width: 5),
              Text(
                ket['text'] as String,
                style: TextStyle(
                  color: ket['color'] as Color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
