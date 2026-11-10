import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'mysql_helper.dart';

/// Helper Komprehensif untuk Auto-Update In-App Aplikasi Mobile
class AppUpdateHelper {
  /// Versi aplikasi yang terpasang di perangkat ini
  static const String currentVersionName = "1.0.0";
  static const int currentVersionCode = 1;

  /// Flag agar dialog tidak muncul berulang kali di sesi yang sama jika sudah ditolak
  static bool _hasPromptedThisSession = false;

  /// Memeriksa ketersediaan pembaruan dari server backend
  static Future<void> checkUpdate(
    BuildContext context, {
    bool isManual = false,
  }) async {
    if (!isManual && _hasPromptedThisSession) {
      return;
    }

    try {
      final candidateUrls = [
        MySQLHelper.baseUrl,
        ...candidateApiUrls,
      ];

      Map<String, dynamic>? updateData;

      for (final rawUrl in candidateUrls) {
        try {
          final uri = Uri.parse(
            '$rawUrl/app-version?version_code=$currentVersionCode',
          );
          final res = await http.get(uri).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final body = jsonDecode(res.body);
            if (body is Map<String, dynamic> && body['status'] == 'success') {
              updateData = body;
              break;
            }
          }
        } catch (_) {
          continue;
        }
      }

      if (updateData == null) {
        if (isManual && context.mounted) {
          _showToast(context, 'Gagal terhubung ke server pembaruan.');
        }
        return;
      }

      final bool hasUpdate = updateData['has_update'] == true;
      if (!hasUpdate) {
        if (isManual && context.mounted) {
          _showToast(
            context,
            'Aplikasi Anda sudah dalam versi terbaru (v$currentVersionName).',
            isSuccess: true,
          );
        }
        return;
      }

      _hasPromptedThisSession = true;

      final String latestVersion = updateData['latest_version'] ?? '1.0.1';
      final int latestCode = updateData['version_code'] ?? 2;
      final bool isMandatory = updateData['is_mandatory'] == true;
      final String title = updateData['title'] ?? 'Pembaruan Aplikasi Tersedia';
      final String changelog =
          updateData['changelog'] ??
          'Pembaruan fitur baru dan peningkatan stabilitas sistem.';
      final String downloadUrl = updateData['download_url'] ?? '';

      if (!context.mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: !isMandatory,
        builder: (ctx) {
          return PopScope(
            canPop: !isMandatory,
            child: _buildUpdateDialog(
              ctx,
              title: title,
              latestVersion: latestVersion,
              latestCode: latestCode,
              changelog: changelog,
              downloadUrl: downloadUrl,
              isMandatory: isMandatory,
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('[AutoUpdate Error]: $e');
      if (isManual && context.mounted) {
        _showToast(context, 'Terjadi kesalahan saat memeriksa update: $e');
      }
    }
  }

  /// Dialog Pop-up Pembaruan Modern
  static Widget _buildUpdateDialog(
    BuildContext context, {
    required String title,
    required String latestVersion,
    required int latestCode,
    required String changelog,
    required String downloadUrl,
    required bool isMandatory,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 10,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ikon Header Update
            Center(
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBFDBFE), width: 2),
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Color(0xFF1D4ED8),
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Judul Pembaruan
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),

            // Badge Versi Baru
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Text(
                  'v$currentVersionName  ➔  v$latestVersion (Build $latestCode)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Kotak Catatan Perubahan (Changelog)
            const Text(
              'Apa yang baru:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  changelog,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF334155),
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tombol Aksi
            Row(
              children: [
                if (!isMandatory) ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Nanti Saja',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: isMandatory ? 1 : 1,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _startInAppDownload(context, downloadUrl, latestVersion);
                    },
                    child: const Text(
                      'Perbarui Sekarang',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Proses Download File APK secara In-App dengan Progress Bar
  static Future<void> _startInAppDownload(
    BuildContext context,
    String downloadUrl,
    String targetVersion,
  ) async {
    // Siapkan URL lengkap
    String fullUrl = downloadUrl;
    if (fullUrl.startsWith('/')) {
      final base = MySQLHelper.baseUrl.replaceAll('/api', '');
      fullUrl = '$base$fullUrl';
    }

    double progress = 0.0;
    int receivedBytes = 0;
    int totalBytes = 0;
    bool isDownloading = true;
    String statusText = 'Menghubungkan ke server...';

    // State setter dialog
    StateSetter? dialogSetState;

    // Tampilkan Dialog Progress Download
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            dialogSetState = setModalState;
            return PopScope(
              canPop: false,
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_download_rounded,
                        color: Color(0xFF1D4ED8),
                        size: 44,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Mengunduh Pembaruan (v$targetVersion)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: isDownloading && progress > 0 ? progress : null,
                        backgroundColor: const Color(0xFFE2E8F0),
                        color: const Color(0xFF1D4ED8),
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              statusText,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(fullUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Server merespon dengan kode ${response.statusCode}');
      }

      totalBytes = response.contentLength ?? 0;

      final tempDir = await getTemporaryDirectory();
      final apkFile = File(
        '${tempDir.path}/app_update_${DateTime.now().millisecondsSinceEpoch}.apk',
      );
      final sink = apkFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          progress = receivedBytes / totalBytes;
          final mbRec = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTot = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          statusText = '$mbRec MB dari $mbTot MB';
        } else {
          final mbRec = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          statusText = 'Terunduh $mbRec MB';
        }
        if (dialogSetState != null) {
          dialogSetState!(() {});
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      // Tutup dialog progress download
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Otomatis Buka Installer APK Android
      debugPrint('[AutoUpdate] Membuka file APK: ${apkFile.path}');
      final openResult = await OpenFilex.open(apkFile.path);

      if (openResult.type != ResultType.done && context.mounted) {
        // Jika pembukaan otomatis gagal (misal izin perangkat), berikan opsi manual
        _showFallbackInstallDialog(context, apkFile.path, fullUrl);
      }
    } catch (e) {
      debugPrint('[Download APK Error]: $e');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Tutup dialog download
        _showFallbackInstallDialog(context, null, fullUrl);
      }
    }
  }

  /// Dialog Cadangan jika pembukaan installer APK terhalang oleh pengaturan OS
  static void _showFallbackInstallDialog(
    BuildContext context,
    String? localPath,
    String browserUrl,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('Pemasangan Pembaruan', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          'File pembaruan sudah selesai diunduh. Jika layar instalasi tidak muncul otomatis, pastikan izin "Pasang aplikasi yang tidak dikenal" telah aktif untuk aplikasi ini, atau unduh langsung via browser.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          if (localPath != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                OpenFilex.open(localPath);
              },
              child: const Text('Coba Buka Lagi'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse(browserUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('Unduh via Browser'),
          ),
        ],
      ),
    );
  }

  static void _showToast(
    BuildContext context,
    String message, {
    bool isSuccess = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green[700] : Colors.blueGrey[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

