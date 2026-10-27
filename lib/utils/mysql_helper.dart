import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_nav.dart';

/// ============================================================
/// KONFIGURASI BACKEND API (EXPRESS.JS)
/// ============================================================
/// KONFIGURASI BACKEND API (EXPRESS.JS VPS)
/// ============================================================
const String apiBaseUrl = 'http://208.76.40.204:5000/api';
const String defaultAiBaseUrl = apiBaseUrl; // Menggunakan jalur aktif yang sama dengan login

const List<String> candidateApiUrls = [
  'http://208.76.40.204:5000/api',    // VPS Port 5000
  'http://208.76.40.204:3000/api',    // VPS Port 3000 (Fallback)
  'http://127.0.0.1:3000/api',        // Jalur USB Cable via 'adb reverse'
  'http://10.0.2.2:3000/api',         // Android Emulator
];

const List<String> candidateAiUrls = [
  apiBaseUrl,
  'http://208.76.40.204:5000/api',
  'http://208.76.40.204:3000/api',
  'http://127.0.0.1:3000/api',
];

/// Helper client untuk berkomunikasi dengan Backend Express.js REST API & AI Service.
/// Menjaga kompatibilitas nama metode agar kode screen tidak rusak.
class MySQLHelper {
  static String baseUrl = apiBaseUrl;
  static String aiBaseUrl = defaultAiBaseUrl;

  /// Ubah URL dasar API secara dinamis jika diperlukan
  static void setBaseUrl(String url) {
    baseUrl = url;
  }

  static void setAiBaseUrl(String url) {
    aiBaseUrl = url;
  }

  static String? lastLoginError;
  static String? lastSaveError;
  static bool _isMaintenanceDialogShowing = false;

  /// Deteksi apakah respon dari server/Coolify merupakan halaman pemeliharaan (Maintenance Mode)
  static bool isMaintenanceResponse(http.Response response) {
    if (response.statusCode == 503) return true;
    final body = response.body.toLowerCase();
    if (body.contains('sistem sedang pemeliharaan') ||
        body.contains('maintenance mode') ||
        body.contains('sedang dalam pemeliharaan') ||
        (response.statusCode >= 500 && body.contains('<!doctype html>'))) {
      return true;
    }
    return false;
  }

  /// Tampilkan Pop-up Dialog Maintenance secara global di aplikasi
  static void showMaintenanceDialog({BuildContext? context, VoidCallback? onRetry}) {
    if (_isMaintenanceDialogShowing) return;

    final targetContext = context ?? appNavigatorKey.currentContext;
    if (targetContext == null) return;

    _isMaintenanceDialogShowing = true;

    showDialog(
      context: targetContext,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7).withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.build_circle_rounded, color: Color(0xFFF59E0B), size: 42),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Sistem Sedang Maintenance',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Server absensi saat ini sedang dalam pemeliharaan berkala atau peningkatan performa sistem.\n\nSilakan coba lagi beberapa saat lagi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'Periksa Kembali',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: () {
                      _isMaintenanceDialogShowing = false;
                      Navigator.of(dialogCtx).pop();
                      if (onRetry != null) onRetry();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _isMaintenanceDialogShowing = false;
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text(
                    'Tutup',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isMaintenanceDialogShowing = false;
    });
  }

  /// 1. Autentikasi Login Karyawan
  /// Endpoint: POST /api/login
  static Future<Map<String, dynamic>?> login(
    String username,
    String password,
  ) async {
    lastLoginError = null;
    final urls = {baseUrl, ...candidateApiUrls}.toList();
    for (final url in urls) {
      try {
        debugPrint('[API Login] Mencoba request ke $url/login ...');
        final response = await http
            .post(
              Uri.parse('$url/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': username, 'password': password}),
            )
            .timeout(const Duration(seconds: 4));

        debugPrint(
          '[API Login] Response code: ${response.statusCode}, body: ${response.body}',
        );

        if (isMaintenanceResponse(response)) {
          lastLoginError = 'Server sedang dalam pemeliharaan (Maintenance Mode)';
          showMaintenanceDialog();
          return null;
        }

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            baseUrl = url; // Simpan URL aktif yang terbukti berhasil
            return {
              'username': data['username'],
              'name': data['name'],
              'face_image': data['face_image']?.toString(),
              'branch': data['branch']?.toString() ?? '',
            };
          }
        } else {
          try {
            final data = jsonDecode(response.body);
            lastLoginError =
                data['message'] ?? 'Login gagal (${response.statusCode})';
          } catch (_) {
            lastLoginError = 'Login gagal (${response.statusCode})';
          }
          // Jika username/password salah, hentikan agar tidak mengulang error yang sama
          return null;
        }
      } catch (e) {
        debugPrint('Koneksi gagal ke $url/login: $e');
        lastLoginError = 'Koneksi gagal: $e';
      }
    }
    return null;
  }

  /// 2. Ambil Foto Acuan Wajah Karyawan
  /// Endpoint: GET /api/user/face/:username
  static Future<String?> getUserFaceReference(String username) async {
    final urls = {baseUrl, ...candidateApiUrls}.toList();
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse('$url/user/face/$username'))
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            baseUrl = url;
            return data['face_image']?.toString();
          }
        }
      } catch (e) {
        debugPrint('Error API (getUserFaceReference) ke $url: $e');
      }
    }
    return null;
  }

  /// 3. Ambil Daftar Kantor Cabang
  /// Endpoint: GET /api/branches
  static Future<List<Map<String, dynamic>>> getBranches() async {
    final urls = {baseUrl, ...candidateApiUrls}.toList();
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse('$url/branches'))
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['data'] != null) {
            baseUrl = url;
            final list = data['data'] as List<dynamic>;
            return list.map((item) {
              return {
                'id': item['id'],
                'branch_name': item['branch_name']?.toString() ?? 'Cabang',
                'city': item['city']?.toString() ?? '',
                'latitude':
                    double.tryParse(item['latitude']?.toString() ?? '') ?? 0.0,
                'longitude':
                    double.tryParse(item['longitude']?.toString() ?? '') ?? 0.0,
                'radius':
                    (double.tryParse(item['radius']?.toString() ?? '') ?? 100.0)
                        .toInt(),
              };
            }).toList();
          }
        }
      } catch (e) {
        debugPrint('Error API (getBranches) ke $url: $e');
      }
    }
    return [];
  }

  /// 4. Simpan Absensi (clock_in, clock_out, izin)
  /// Endpoint: POST /api/attendance
  /// [image] opsional: base64 encoded image string untuk lampiran izin
  static Future<bool> saveAttendance(
    String username,
    String type, {
    String? reason,
    String? image,
  }) async {
    lastSaveError = null;
    final urls = {baseUrl, ...candidateApiUrls}.toList();

    for (final url in urls) {
      try {
        final Map<String, dynamic> body = {
          'username': username,
          'type': type,
          'reason': reason ?? '',
        };
        if (image != null && image.isNotEmpty) {
          body['image'] = image;
        }

        final response = await http
            .post(
              Uri.parse('$url/attendance'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 20));

        if (isMaintenanceResponse(response)) {
          lastSaveError = 'Server sedang dalam pemeliharaan (Maintenance Mode)';
          showMaintenanceDialog();
          return false;
        }

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            baseUrl = url;
            return true;
          }
          lastSaveError = data['message'] ?? 'Gagal menyimpan absensi';
          return false;
        } else {
          try {
            final data = jsonDecode(response.body);
            lastSaveError =
                data['message'] ?? 'Gagal menyimpan (${response.statusCode})';
          } catch (_) {
            lastSaveError =
                'Gagal menyimpan (${response.statusCode}): ${response.body}';
          }
          debugPrint(
            'Simpan absen gagal ($url): ${response.statusCode} - $lastSaveError',
          );

          // Jika server berhasil dihubungi tapi aturan bisnis menolak (cth 400: izin ditolak / Alpha),
          // tidak perlu mencoba kandidat URL lain karena server utama sudah memberi respon resmi.
          if (response.statusCode == 400) {
            baseUrl = url;
            return false;
          }
        }
      } catch (e) {
        debugPrint('Error API (saveAttendance) ke $url: $e');
        lastSaveError = 'Koneksi ke server gagal: $e';
      }
    }
    return false;
  }

  /// 5. Cek Status Absensi Siklus Hari Ini (reset 23:55)
  /// Endpoint: GET /api/attendance/status/:username
  static Future<Map<String, dynamic>?> getTodayAttendanceStatus(
    String username,
  ) async {
    final urls = {baseUrl, ...candidateApiUrls}.toList();
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse('$url/attendance/status/$username'))
            .timeout(const Duration(seconds: 6));

        if (isMaintenanceResponse(response)) {
          showMaintenanceDialog();
          return null;
        }

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            baseUrl = url;
            DateTime? cycleStart;
            DateTime? cycleEnd;
            if (data['cycleStart'] != null) {
              cycleStart = DateTime.tryParse(data['cycleStart'].toString());
            }
            if (data['cycleEnd'] != null) {
              cycleEnd = DateTime.tryParse(data['cycleEnd'].toString());
            }

            return {
              'hasClockedIn': data['hasClockedIn'] ?? false,
              'hasClockedOut': data['hasClockedOut'] ?? false,
              'clockInTime': data['clockInTime'] ?? '--:--',
              'clockInLocation': data['clockInLocation'] ?? 'Kantor Pusat',
              'clockInKeterangan': data['clockInKeterangan']?.toString(),
              'clockOutTime': data['clockOutTime'] ?? '--:--',
              'hasPermission': data['hasPermission'] ?? false,
              'permissionId': data['permissionId'],
              'permissionType': data['permissionType']?.toString(),
              'permissionStatus': data['permissionStatus']?.toString(),
              'permissionReason': data['permissionReason']?.toString(),
              'permissionTime': data['permissionTime']?.toString(),
              'cycleStart': cycleStart,
              'cycleEnd': cycleEnd,
            };
          }
        }
      } catch (e) {
        debugPrint('Error API (getTodayAttendanceStatus) ke $url: $e');
      }
    }
    return null;
  }

  /// 6. Verifikasi Wajah AI (Python Flask - Port 5001 / Proxy Express)
  /// Endpoint: POST /api/verify
  static Future<Map<String, dynamic>> verifyFaceWithAI(
    String username,
    String selfieBase64,
  ) async {
    final urls = <String>[];
    if (baseUrl.isNotEmpty) urls.add(baseUrl);
    if (!urls.contains(apiBaseUrl) && apiBaseUrl.isNotEmpty) urls.add(apiBaseUrl);
    for (final u in candidateAiUrls) {
      if (!urls.contains(u)) urls.add(u);
    }

    for (final url in urls) {
      try {
        debugPrint('[AI Service] Mengirim foto @$username ke $url/verify ...');
        final response = await http
            .post(
              Uri.parse('$url/verify'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'username': username,
                'image': selfieBase64,
              }),
            )
            .timeout(const Duration(seconds: 8));

        debugPrint('[AI Service] Response ($url): ${response.statusCode} - ${response.body}');

        if (isMaintenanceResponse(response)) {
          showMaintenanceDialog();
          return {
            'success': false,
            'matched': false,
            'connected': false,
            'similarity_score': 0.0,
            'face_detected': false,
            'message': 'Server sedang dalam pemeliharaan (Maintenance Mode).',
          };
        }

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          aiBaseUrl = url;
          final bool matched = data['matched'] == true;
          final double similarity = (data['similarity_score'] as num?)?.toDouble() ?? 0.0;
          return {
            'success': true,
            'matched': matched,
            'similarity_score': similarity,
            'distance': (data['distance'] as num?)?.toDouble() ?? 1.0,
            'face_detected': data['face_detected'] ?? true,
            'message': data['message'] ?? (matched ? 'Wajah Cocok & Terverifikasi!' : 'Wajah Tidak Cocok!'),
          };
        } else if (response.statusCode == 400 || response.statusCode == 404) {
          final data = jsonDecode(response.body);
          return {
            'success': false,
            'matched': false,
            'similarity_score': 0.0,
            'face_detected': data['face_detected'] ?? false,
            'message': data['message'] ?? 'Verifikasi AI gagal (${response.statusCode})',
          };
        }
      } catch (e) {
        debugPrint('[AI Service] URL $url gagal dihubungi ($e), mencoba kandidat berikutnya...');
      }
    }

    return {
      'success': false,
      'matched': false,
      'connected': false,
      'similarity_score': 0.0,
      'face_detected': false,
      'message': 'Gagal terhubung ke AI Service (Port 5001). Pastikan AI Service Python sudah dijalankan!',
    };
  }
}

/// Alias ApiService untuk arsitektur yang lebih bersih
typedef ApiService = MySQLHelper;
