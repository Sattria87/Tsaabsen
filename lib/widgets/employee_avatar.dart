import 'package:flutter/material.dart';

/// Widget foto profil karyawan.
/// Menampilkan foto dari assets (path database) jika tersedia,
/// fallback ke logo WG jika tidak ada.
class EmployeeAvatarWidget extends StatelessWidget {
  final Map<String, dynamic> userData;
  final double radius;

  const EmployeeAvatarWidget({
    super.key,
    required this.userData,
    this.radius = 26,
  });

  @override
  Widget build(BuildContext context) {
    final String? facePath = userData['face_image']?.toString();

    if (facePath != null && facePath.isNotEmpty) {
      // Path dari database: "assets/foto_karyawan/filename.jpg"
      // Gunakan AssetImage karena file sudah dikopikan ke dalam project Flutter
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: AssetImage(facePath),
        onBackgroundImageError: (_, _) {},
        child: null,
      );
    }

    // Fallback: avatar karyawan atau icon
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: const AssetImage('assets/avatar_employee_tie.png'),
      onBackgroundImageError: (_, _) {},
      child: const Icon(Icons.person, color: Colors.grey),
    );
  }
}
