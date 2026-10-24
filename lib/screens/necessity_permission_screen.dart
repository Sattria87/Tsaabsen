import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/mysql_helper.dart';
import '../widgets/employee_avatar.dart';
import 'permission_success_screen.dart';

class NecessityPermissionScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const NecessityPermissionScreen({super.key, required this.userData});

  @override
  State<NecessityPermissionScreen> createState() => _NecessityPermissionScreenState();
}

class _NecessityPermissionScreenState extends State<NecessityPermissionScreen> {
  final TextEditingController _jenisUrusanController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  File? _selectedImage;
  bool _isLoading = false;

  // Fungsi untuk memunculkan kalender (Date Picker)
  Future<void> _selectDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF007AFF), // Aksen biru tema
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  // Fungsi untuk mengambil dokumen/foto pendukung — buka KAMERA secara otomatis
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  // Fungsi Submit Pengajuan Keperluan ke Database MySQL
  Future<void> _submitNecessityPermission() async {
    if (_jenisUrusanController.text.trim().isEmpty ||
        _dateController.text.isEmpty ||
        _reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua field wajib diisi!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Foto bukti keperluan WAJIB dilampirkan
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto bukti keperluan wajib dilampirkan! Ketuk kotak foto untuk membuka kamera.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    String fullReason =
        'Jenis Urusan: ${_jenisUrusanController.text.trim()} | Tanggal: ${_dateController.text} | Alasan: ${_reasonController.text.trim()} | [Dokumen Bukti Terlampir]';

    // Konversi foto ke base64 untuk dikirim ke backend
    String? imageBase64;
    if (_selectedImage != null) {
      final bytes = await _selectedImage!.readAsBytes();
      imageBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }

    // Simpan ke database menggunakan helper
    bool success = await MySQLHelper.saveAttendance(
      widget.userData['username'] ?? '',
      'izin_keperluan',
      reason: fullReason,
      image: imageBase64,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      // Navigasi ke halaman sukses dengan tipe 'Keperluan'
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PermissionSuccessScreen(
            userData: widget.userData,
            izinType: 'Keperluan',
            date: _dateController.text,
          ),
        ),
      );
    } else {
      final errorMsg = MySQLHelper.lastSaveError ??
          'Gagal menyimpan ke database! Pastikan server aktif.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = widget.userData['name']?.toString().isNotEmpty == true
        ? widget.userData['name'].toString()
        : (widget.userData['username']?.toString().isNotEmpty == true
            ? widget.userData['username'].toString()
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
                              userData: widget.userData,
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
              // 2. JUDUL FORM: "Lengkapi detail pengajuan izin"
              // ========================================================
              const Center(
                child: Text(
                  'Lengkapi detail pengajuan izin',
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ========================================================
              // 3. FORM ISIAN
              // ========================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A. LABEL & INPUT JENIS URUSAN
                    const Text(
                      'Jenis Urusan',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFFCBD5E1),
                          width: 1.2,
                        ),
                      ),
                      child: TextField(
                        controller: _jenisUrusanController,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF1E293B),
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          hintText: 'Contoh: Urusan Keluarga / Penting...',
                          hintStyle: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // B. LABEL & INPUT TANGGAL
                    const Text(
                      'Tanggal',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _selectDate(context),
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFCBD5E1),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _dateController.text.isNotEmpty
                                    ? _dateController.text
                                    : 'Pilih tanggal izin...',
                                style: TextStyle(
                                  color: _dateController.text.isNotEmpty
                                      ? const Color(0xFF1E293B)
                                      : Colors.grey.shade400,
                                  fontSize: 13.5,
                                  fontWeight: _dateController.text.isNotEmpty
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.calendar_today_outlined,
                              color: Color(0xFF94A3B8),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // C. LABEL & INPUT ALASAN DENGAN WATERMARK TSA
                    const Text(
                      'Alasan',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 130,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFFCBD5E1),
                          width: 1.2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Stack(
                          children: [
                            // Watermark Logo TSA di dalam kotak isian persis mockup
                            Center(
                              child: Opacity(
                                opacity: 0.25,
                                child: Image.asset(
                                  'assets/Minimalist TSA Watermark Logo.png',
                                  width: 205,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),

                            // Field Input Multiline Alasan
                            TextField(
                              controller: _reasonController,
                              maxLines: 4,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF1E293B),
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                hintText: 'Tuliskan keterangan detail keperluan Anda...',
                                hintStyle: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // D. LABEL & UNGGAH DOKUMEN PENDUKUNG (WAJIB — BUKA KAMERA)
                    Row(
                      children: [
                        const Text(
                          'Foto Bukti Keperluan',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFFF3B30), width: 0.8),
                          ),
                          child: const Text(
                            'Wajib',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF3B30),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ketuk untuk membuka kamera',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickImage,
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: double.infinity,
                        height: 120,
                        decoration: BoxDecoration(
                          color: _selectedImage != null
                              ? Colors.white
                              : const Color(0xFFF0F7FF),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: _selectedImage != null
                                ? const Color(0xFF34C759)
                                : const Color(0xFF007AFF),
                            width: _selectedImage != null ? 2.0 : 1.5,
                          ),
                        ),
                        child: _selectedImage != null
                            ? Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.file(
                                      _selectedImage!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: 120,
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedImage = null),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF34C759),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Text(
                                          '✓ Foto Terlampir — Ketuk untuk ganti',
                                          style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 36,
                                    color: Color(0xFF007AFF),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Buka Kamera',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF007AFF),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Foto bukti keperluan diperlukan',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 38),

                    // ========================================================
                    // 4. TOMBOL BIRU "Ajukan" (PERSIS GAMBAR)
                    // ========================================================
                    Center(
                      child: SizedBox(
                        width: 215,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitNecessityPermission,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF), // Biru cerah persis tombol Ajukan
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Ajukan',
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}