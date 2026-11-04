import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  /// Inisialisasi service notifikasi lokal Android
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(
        android: androidSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('[NotificationHelper] Notifikasi diklik: ${response.payload}');
        },
      );

      // Minta izin notifikasi pada Android 13+ (TIRAMISU ke atas)
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      _isInitialized = true;
      debugPrint('[NotificationHelper] Service notifikasi berhasil diinisialisasi.');
    } catch (e) {
      debugPrint('[NotificationHelper Error]: $e');
    }
  }

  /// Tampilkan notifikasi Pengumuman HRD di status bar HP
  static Future<void> showAnnouncementNotification({
    required int id,
    required String title,
    required String body,
    String? category,
  }) async {
    try {
      await init();

      final categoryIcon = category == 'libur'
          ? '🏖️'
          : (category == 'acara'
              ? '🎉'
              : (category == 'pengingat' ? '⏰' : '📢'));

      final androidDetails = AndroidNotificationDetails(
        'wg_announcements_channel',
        'Pengumuman HRD TSA',
        channelDescription:
            'Saluran pemberitahuan libur, acara, dan informasi penting dari HRD',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: '$categoryIcon $title',
          summaryText: 'Pemberitahuan HRD',
        ),
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
      );

      await _notificationsPlugin.show(
        id: id,
        title: '$categoryIcon $title',
        body: body,
        notificationDetails: notificationDetails,
      );
      debugPrint('[NotificationHelper] Berhasil memunculkan notifikasi id: $id');
    } catch (e) {
      debugPrint('[NotificationHelper] Gagal memunculkan notifikasi: $e');
    }
  }

  /// Tampilkan notifikasi Pengingat Absensi
  static Future<void> showAttendanceReminderNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await init();

      const androidDetails = AndroidNotificationDetails(
        'wg_attendance_reminders_channel',
        'Pengingat Absensi & Persetujuan',
        channelDescription:
            'Saluran pengingat Clock In dan status persetujuan kehadiran',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(''),
      );

      final notificationDetails = const NotificationDetails(
        android: androidDetails,
      );

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('[NotificationHelper Reminder Error]: $e');
    }
  }
}
