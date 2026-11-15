import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mysql_helper.dart';

/// Helper untuk mengelola antrean presensi saat offline (tanpa sinyal internet)
/// Begitu presensi berhasil terkirim ke server, data lokal langsung dihapus bersih
/// agar tidak memenuhi penyimpanan memori HP karyawan.
class OfflineAttendanceHelper {
  static const String _kQueueKey = 'tsa_offline_attendance_queue';

  /// Menyimpan rekaman absensi ke antrean offline lokal
  static Future<bool> saveOfflineRecord({
    required String username,
    required String type,
    String? reason,
    String? imageBase64,
    String? evidenceImageBase64,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> currentQueue = prefs.getStringList(_kQueueKey) ?? [];

      final Map<String, dynamic> record = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'username': username,
        'type': type,
        'reason': reason ?? '',
        'image': imageBase64 ?? '',
        'evidence_image': evidenceImageBase64 ?? '',
        'created_at': DateTime.now().toIso8601String(),
      };

      currentQueue.add(jsonEncode(record));
      await prefs.setStringList(_kQueueKey, currentQueue);
      debugPrint('[OfflineAttendance] Berhasil menyimpan antrean offline (${currentQueue.length} data)');
      return true;
    } catch (e) {
      debugPrint('[OfflineAttendance] Gagal menyimpan offline: $e');
      return false;
    }
  }

  /// Memeriksa jumlah antrean offline yang belum tersinkronisasi
  static Future<int> getPendingQueueCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> currentQueue = prefs.getStringList(_kQueueKey) ?? [];
      return currentQueue.length;
    } catch (_) {
      return 0;
    }
  }

  /// Sinkronisasi otomatis data presensi offline ke server
  /// Data yang SUKSES dikirim akan LANGSUNG DIHAPUS dari penyimpanan lokal
  static Future<int> syncPendingRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> currentQueue = prefs.getStringList(_kQueueKey) ?? [];
      if (currentQueue.isEmpty) return 0;

      final List<String> remainingQueue = [];
      int successCount = 0;

      for (final itemStr in currentQueue) {
        try {
          final Map<String, dynamic> item = jsonDecode(itemStr);
          final String username = item['username'] ?? '';
          final String type = item['type'] ?? '';
          final String reason = item['reason'] ?? '';
          final String image = item['image'] ?? '';
          final String evidence = item['evidence_image'] ?? '';

          // Beri penanda tambahan bahwa ini data presensi tersinkron dari offline
          final String finalReason = reason.contains('[Offline Sync]')
              ? reason
              : '$reason [Offline Sync]';

          final bool success = await MySQLHelper.saveAttendance(
            username,
            type,
            reason: finalReason,
            image: image.isNotEmpty ? image : null,
            evidenceImage: evidence.isNotEmpty ? evidence : null,
          );

          if (success) {
            successCount++;
            // Berhasil terkirim -> Jangan dimasukkan ke remainingQueue (Otomatis terhapus)
            debugPrint('[OfflineAttendance] Data ID ${item['id']} sukses tersinkronisasi dan dihapus dari lokal.');
          } else {
            // Gagal terkirim -> Pertahankan di antrean untuk dicoba lagi
            remainingQueue.add(itemStr);
          }
        } catch (itemErr) {
          debugPrint('[OfflineAttendance] Error item sync: $itemErr');
          remainingQueue.add(itemStr);
        }
      }

      // Perbarui antrean dengan hanya data yang belum berhasil dikirim
      await prefs.setStringList(_kQueueKey, remainingQueue);
      debugPrint('[OfflineAttendance] Sinkronisasi selesai: $successCount sukses, ${remainingQueue.length} tersisa.');
      return successCount;
    } catch (e) {
      debugPrint('[OfflineAttendance] Error syncPendingRecords: $e');
      return 0;
    }
  }

  /// Hapus seluruh antrean secara manual jika diperlukan
  static Future<void> clearAllQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kQueueKey);
  }
}
