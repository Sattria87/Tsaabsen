import 'package:flutter/material.dart';
import '../widgets/employee_avatar.dart';
import 'sick_permission_screen.dart';
import 'necessity_permission_screen.dart';

class PermissionScreen extends StatelessWidget {
  final Map<String, dynamic> userData;
  const PermissionScreen({super.key, required this.userData});

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
                    padding: const EdgeInsets.only(top: 44, left: 16, right: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Kembali',
                        ),
                      ],
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

              const SizedBox(height: 36),

              // ========================================================
              // 2. TEKS PERTANYAAN AJAKAN
              // ========================================================
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'Untuk hal apa kamu melakukan\npengajuan izin hari ini?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ========================================================
              // 3. ILUSTRASI UTAMA MASCOT BERPIKIR + WATERMARK LOGO TSA
              // ========================================================
              SizedBox(
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Watermark Logo TSA di belakang maskot
                    Opacity(
                      opacity: 0.85,
                      child: Image.asset(
                        'assets/Minimalist TSA Watermark Logo.png',
                        width: 210,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const SizedBox.shrink();
                        },
                      ),
                    ),

                    // Karakter Maskot TSA Berpikir dengan Tanda Tanya Biru
                    Image.asset(
                      'assets/Puzzled_TSA_Officer_with_Question_Mark-removebg-preview.png',
                      height: 170,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/Puzzled TSA Officer with Question Mark.png',
                          height: 170,
                          fit: BoxFit.contain,
                          errorBuilder: (c, e, s) {
                            return const Icon(Icons.help_outline, size: 80, color: Color(0xFF007AFF));
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ========================================================
              // 4. KARTU PILIHAN: SAKIT & KEPERLUAN
              // ========================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    // A. KARTU PILIHAN "SAKIT"
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SickPermissionScreen(userData: userData),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 86,
                                child: Image.asset(
                                  'assets/sick.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (c, e, s) => const Icon(
                                    Icons.sick_outlined,
                                    size: 48,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Sakit',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 18),

                    // B. KARTU PILIHAN "KEPERLUAN"
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NecessityPermissionScreen(userData: userData),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 86,
                                child: Image.asset(
                                  'assets/Worried_TSA_Officer_Holding_Family_Photo-removebg-preview.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (c, e, s) => Image.asset(
                                    'assets/Worried TSA Officer Holding Family Photo.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (c2, e2, s2) => const Icon(
                                      Icons.badge_outlined,
                                      size: 48,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Keperluan',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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