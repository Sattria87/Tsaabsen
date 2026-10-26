import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/auth_service.dart';
import '../utils/mysql_helper.dart';

/// Widget foto profil karyawan yang tangguh (robust).
/// Mendukung foto dari URL Backend (Network), Base64, Web Admin, Local Asset,
/// serta fallback otomatis jika file belum selesai dimuat.
class EmployeeAvatarWidget extends StatefulWidget {
  final Map<String, dynamic> userData;
  final double radius;

  const EmployeeAvatarWidget({
    super.key,
    required this.userData,
    this.radius = 26,
  });

  @override
  State<EmployeeAvatarWidget> createState() => _EmployeeAvatarWidgetState();
}

class _EmployeeAvatarWidgetState extends State<EmployeeAvatarWidget> {
  int _currentUrlIndex = 0;
  List<String> _candidateUrls = [];
  bool _tryAsset = true;
  String? _facePath;
  bool _isBase64 = false;
  Uint8List? _base64Bytes;

  @override
  void initState() {
    super.initState();
    _initImageSources();
  }

  @override
  void didUpdateWidget(covariant EmployeeAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userData['face_image'] != widget.userData['face_image'] ||
        oldWidget.userData['username'] != widget.userData['username']) {
      _initImageSources();
    }
  }

  void _initImageSources() {
    _facePath = widget.userData['face_image']?.toString().trim();
    if (_facePath != null) {
      _facePath = _facePath!.replaceAll('\\', '/');
    }
    _currentUrlIndex = 0;
    _tryAsset = true;
    _isBase64 = false;
    _base64Bytes = null;
    _candidateUrls = [];

    final username = widget.userData['username']?.toString().trim() ?? '';

    // Ambil host dari MySQLHelper.baseUrl
    String host = MySQLHelper.baseUrl.trim();
    if (host.endsWith('/api')) {
      host = host.substring(0, host.length - 4);
    }
    final uri = Uri.tryParse(host);
    final baseHost = uri?.host ?? '208.76.40.204';
    final scheme = uri?.scheme ?? 'http';

    // 1. Cek apakah format Base64 langsung
    if (_facePath != null && _facePath!.isNotEmpty) {
      if (_facePath!.startsWith('data:image') ||
          (!_facePath!.startsWith('http') &&
              !_facePath!.contains('/') &&
              _facePath!.length > 150)) {
        try {
          String raw = _facePath!;
          if (raw.contains(',')) {
            raw = raw.split(',')[1];
          }
          _base64Bytes = base64Decode(raw);
          _isBase64 = true;
          return;
        } catch (_) {}
      }

      // 2. Jika sudah merupakan full URL
      if (_facePath!.startsWith('http://') || _facePath!.startsWith('https://')) {
        _candidateUrls.add(_facePath!);
      } else {
        // Path relatif, contoh: "assets/foto_karyawan/110_196_18_rfky.jpg"
        final clean = _facePath!.startsWith('/') ? _facePath!.substring(1) : _facePath!;

        // Kandidat A: Endpoint stream backend khusus user (Paling aman & akurat)
        if (username.isNotEmpty) {
          _candidateUrls.add('$host/api/user/photo/$username');
          if (host.contains(':5000')) {
            _candidateUrls.add(host.replaceAll(':5000', ':3000') + '/api/user/photo/$username');
          }
        }

        // Kandidat B: Path statis di host aktif (port 5000/3000)
        _candidateUrls.add('$host/$clean');
        if (!clean.startsWith('assets/')) {
          _candidateUrls.add('$host/assets/$clean');
        }

        // Kandidat C: Web Admin TSA (port 8085 tempat foto fisik tersimpan)
        _candidateUrls.add('$scheme://$baseHost:8085/$clean');
        if (!clean.startsWith('assets/')) {
          _candidateUrls.add('$scheme://$baseHost:8085/assets/$clean');
        }

        // Kandidat D: Fallback IP VPS langsung
        if (baseHost != '208.76.40.204') {
          _candidateUrls.add('http://208.76.40.204:5000/api/user/photo/$username');
          _candidateUrls.add('http://208.76.40.204:8085/$clean');
        }
      }
    } else if (username.isNotEmpty) {
      // Jika face_image belum ada di session lokal, prioritaskan endpoint foto dan fetch referensi
      _candidateUrls.add('$host/api/user/photo/$username');
      _candidateUrls.add('$scheme://$baseHost:8085/assets/foto_karyawan/$username.jpg');
      _fetchFaceReference(username);
    }
  }

  Future<void> _fetchFaceReference(String username) async {
    try {
      final ref = await MySQLHelper.getUserFaceReference(username);
      if (ref != null && ref.isNotEmpty && mounted) {
        setState(() {
          widget.userData['face_image'] = ref;
          _initImageSources();
        });
        // Perbarui sesi tersimpan di storage lokal agar persist saat app dibuka lagi
        AuthService.saveSession(widget.userData);
      }
    } catch (_) {}
  }

  Widget _buildFallbackAvatar() {
    return Image.asset(
      'assets/avatar_employee_tie.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.person_rounded,
        color: Color(0xFF94A3B8),
        size: 28,
      ),
    );
  }

  Widget _buildImageContent() {
    // A. Render Base64 Memory Image
    if (_isBase64 && _base64Bytes != null) {
      return Image.memory(
        _base64Bytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackAvatar(),
      );
    }

    // B. Coba URL Network secara berurutan
    if (_currentUrlIndex < _candidateUrls.length) {
      final url = _candidateUrls[_currentUrlIndex];
      return Image.network(
        url,
        key: ValueKey('avatar_${url}_$_currentUrlIndex'),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // Gagal memuat URL ini, coba kandidat URL berikutnya secara asinkron
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _currentUrlIndex < _candidateUrls.length) {
              setState(() {
                _currentUrlIndex++;
              });
            }
          });
          return Container(
            color: const Color(0xFFF1F5F9),
            child: const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
          );
        },
      );
    }

    // C. Coba Local Asset Bundle (jika ada file di dalam APK)
    if (_tryAsset && _facePath != null && _facePath!.isNotEmpty && !_facePath!.startsWith('http')) {
      final clean = _facePath!.startsWith('/') ? _facePath!.substring(1) : _facePath!;
      return Image.asset(
        clean,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _tryAsset) {
              setState(() {
                _tryAsset = false;
              });
            }
          });
          return _buildFallbackAvatar();
        },
      );
    }

    // D. Fallback default avatar
    return _buildFallbackAvatar();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFFFB800), // Ring emas elegan
          width: 1.2,
        ),
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: _buildImageContent(),
        ),
      ),
    );
  }
}
