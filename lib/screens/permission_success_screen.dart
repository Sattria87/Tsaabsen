import 'package:flutter/material.dart';
import '../widgets/employee_avatar.dart';
import 'home_screen.dart';

class PermissionSuccessScreen extends StatelessWidget {
  final Map<String, dynamic> userData;
  final String izinType; // 'Sakit' atau 'Keperluan'
  final String date;     // Tanggal pengajuan

  const PermissionSuccessScreen({
    super.key,
    required this.userData,
    required this.izinType,
    required this.date,
  });

  // Helper untuk memformat tanggal ke gaya "1 Oct 2026"
  String _formatDate(String rawDate) {
    if (rawDate.trim().isEmpty) {
      final now = DateTime.now();
      const List<String> months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${now.day} ${months[now.month - 1]} ${now.year}';
    }

    try {
      DateTime parsed = DateTime.parse(rawDate.trim());
      const List<String> months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
    } catch (_) {
      return rawDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = userData['name']?.toString().isNotEmpty == true
        ? userData['name'].toString()
        : (userData['username']?.toString().isNotEmpty == true
            ? userData['username'].toString()
            : 'Bagas Rudiyanto');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ========================================================
              // 1. HEADER NAVY LENGKUNG + KARTU PROFIL FLOATING (EMAS)
              // ========================================================
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Latar Belakang Lengkung Biru Navy Tua
                  Container(
                    height: 150,
                    decoration: const BoxDecoration(
                      color: Color(0xFF131B3E),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(36),
                        bottomRight: Radius.circular(36),
                      ),
                    ),
                  ),

                  // Kartu Profil Mengambang dengan Garis Kuning Emas
                  Padding(
                    padding: const EdgeInsets.only(top: 52, left: 24, right: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFFFD166), // Garis emas/kuning persis gambar
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Foto Profil Avatar Karyawan
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade200, width: 1),
                            ),
                            child: EmployeeAvatarWidget(
                              userData: userData,
                              radius: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Detail Nama & Status Izin
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Holla,',
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: Color(0xFF1E293B),
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 1,
                                  color: const Color(0xFFF1F5F9),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Izin',
                                  style: TextStyle(
                                    color: Color(0xFFFF7A00), // Oranye status Izin persis gambar
                                    fontSize: 13,
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
              ),

              const SizedBox(height: 38),

              // ========================================================
              // 2. MASKOT JEMPOL TSA DENGAN WATERMARK TSA
              // ========================================================
              SizedBox(
                height: 145,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Watermark Logo TSA di belakang maskot
                    Opacity(
                      opacity: 0.35,
                      child: Image.asset(
                        'assets/Minimalist TSA Watermark Logo.png',
                        width: 250,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),

                    // Karakter Maskot TSA Tersenyum Memberikan Jempol
                    Image.asset(
                      'assets/Cheerful_TSA_Mascot_Thumbs_Up-removebg-preview.png',
                      height: 140,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.check_circle_outline, size: 85, color: Color(0xFF007AFF)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ========================================================
              // 3. TEKS "Izin berhasil diajukan"
              // ========================================================
              const Center(
                child: Text(
                  'Izin berhasil diajukan',
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ========================================================
              // 4. KARTU DETAIL INFORMASI IZIN
              // ========================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Tipe Izin
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tipe Izin',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            izinType,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ),

                      // Tanggal
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tanggal',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _formatDate(date),
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ),

                      // Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Status',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Text(
                            'Waiting Approval',
                            style: TextStyle(
                              color: Color(0xFFFF4D4F), // Merah terang persis gambar
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // ========================================================
              // 5. TOMBOL BIRU "Back to Home"
              // ========================================================
              Center(
                child: SizedBox(
                  width: 215,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => HomeScreen(userData: userData),
                        ),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF), // Biru cerah persis tombol
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
              ),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}