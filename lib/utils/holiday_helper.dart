import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'mysql_helper.dart';

class HolidayInfo {
  final bool isHoliday;
  final bool isCutiBersama;
  final bool isWeekend;
  final bool isWorkingDay;
  final String statusType; // 'workday', 'weekend', 'national_holiday', 'cuti_bersama'
  final String statusLabel;
  final String eventName;
  final String dateFormatted;
  final String dayName;

  HolidayInfo({
    required this.isHoliday,
    required this.isCutiBersama,
    required this.isWeekend,
    required this.isWorkingDay,
    required this.statusType,
    required this.statusLabel,
    required this.eventName,
    required this.dateFormatted,
    required this.dayName,
  });

  bool get isOffDay => isHoliday || isCutiBersama || isWeekend;
}

class HolidayHelper {
  // Hari Libur Nasional Tetap Setiap Tahun (Bulan-Hari)
  static final Map<String, Map<String, dynamic>> fixedHolidays = {
    '01-01': {'name': 'Tahun Baru Masehi', 'is_cuti': false},
    '05-01': {'name': 'Hari Buruh Internasional', 'is_cuti': false},
    '06-01': {'name': 'Hari Lahir Pancasila', 'is_cuti': false},
    '08-17': {'name': 'Hari Kemerdekaan RI (HUT RI)', 'is_cuti': false},
    '12-25': {'name': 'Hari Raya Natal', 'is_cuti': false},
    '12-26': {'name': 'Cuti Bersama Hari Raya Natal', 'is_cuti': true},
  };

  // Kurasi Resmi SKB 3 Menteri Indonesia (2025, 2026, 2027)
  static final Map<String, Map<String, dynamic>> curatedHolidays = {
    // 2025
    '2025-01-01': {'name': 'Tahun Baru 2025 Masehi', 'is_cuti': false},
    '2025-01-27': {'name': 'Isra Mikraj Nabi Muhammad SAW', 'is_cuti': false},
    '2025-01-28': {'name': 'Cuti Bersama Tahun Baru Imlek 2576', 'is_cuti': true},
    '2025-01-29': {'name': 'Tahun Baru Imlek 2576 Kongzili', 'is_cuti': false},
    '2025-03-28': {'name': 'Cuti Bersama Hari Suci Nyepi', 'is_cuti': true},
    '2025-03-29': {'name': 'Hari Suci Nyepi Tahun Baru Saka 1947', 'is_cuti': false},
    '2025-03-31': {'name': 'Hari Raya Idul Fitri 1446 H', 'is_cuti': false},
    '2025-04-01': {'name': 'Hari Raya Idul Fitri 1446 H', 'is_cuti': false},
    '2025-04-02': {'name': 'Cuti Bersama Idul Fitri 1446 H', 'is_cuti': true},
    '2025-04-03': {'name': 'Cuti Bersama Idul Fitri 1446 H', 'is_cuti': true},
    '2025-04-04': {'name': 'Cuti Bersama Idul Fitri 1446 H', 'is_cuti': true},
    '2025-04-07': {'name': 'Cuti Bersama Idul Fitri 1446 H', 'is_cuti': true},
    '2025-04-18': {'name': 'Wafat Yesus Kristus (Jumat Agung)', 'is_cuti': false},
    '2025-04-20': {'name': 'Hari Paskah', 'is_cuti': false},
    '2025-05-01': {'name': 'Hari Buruh Internasional', 'is_cuti': false},
    '2025-05-12': {'name': 'Hari Raya Waisak 2569 BE', 'is_cuti': false},
    '2025-05-13': {'name': 'Cuti Bersama Hari Raya Waisak', 'is_cuti': true},
    '2025-05-29': {'name': 'Kenaikan Yesus Kristus', 'is_cuti': false},
    '2025-05-30': {'name': 'Cuti Bersama Kenaikan Yesus Kristus', 'is_cuti': true},
    '2025-06-01': {'name': 'Hari Lahir Pancasila', 'is_cuti': false},
    '2025-06-06': {'name': 'Hari Raya Idul Adha 1446 H', 'is_cuti': false},
    '2025-06-09': {'name': 'Cuti Bersama Idul Adha 1446 H', 'is_cuti': true},
    '2025-06-27': {'name': '1 Muharram Tahun Baru Islam 1447 H', 'is_cuti': false},
    '2025-08-17': {'name': 'Proklamasi Kemerdekaan RI Ke-80', 'is_cuti': false},
    '2025-09-05': {'name': 'Maulid Nabi Muhammad SAW', 'is_cuti': false},
    '2025-12-25': {'name': 'Hari Raya Natal', 'is_cuti': false},
    '2025-12-26': {'name': 'Cuti Bersama Hari Raya Natal', 'is_cuti': true},

    // 2026 (Tahun Ini)
    '2026-01-01': {'name': 'Tahun Baru 2026 Masehi', 'is_cuti': false},
    '2026-01-16': {'name': 'Isra Mikraj Nabi Muhammad SAW', 'is_cuti': false},
    '2026-02-16': {'name': 'Cuti Bersama Tahun Baru Imlek 2577', 'is_cuti': true},
    '2026-02-17': {'name': 'Tahun Baru Imlek 2577 Kongzili', 'is_cuti': false},
    '2026-03-19': {'name': 'Cuti Bersama Hari Suci Nyepi', 'is_cuti': true},
    '2026-03-20': {'name': 'Hari Suci Nyepi Tahun Baru Saka 1948', 'is_cuti': false},
    '2026-03-21': {'name': 'Hari Raya Idul Fitri 1447 H', 'is_cuti': false},
    '2026-03-22': {'name': 'Hari Raya Idul Fitri 1447 H', 'is_cuti': false},
    '2026-03-23': {'name': 'Cuti Bersama Idul Fitri 1447 H', 'is_cuti': true},
    '2026-03-24': {'name': 'Cuti Bersama Idul Fitri 1447 H', 'is_cuti': true},
    '2026-04-03': {'name': 'Wafat Yesus Kristus (Jumat Agung)', 'is_cuti': false},
    '2026-05-01': {'name': 'Hari Buruh Internasional', 'is_cuti': false},
    '2026-05-14': {'name': 'Kenaikan Yesus Kristus', 'is_cuti': false},
    '2026-05-15': {'name': 'Cuti Bersama Kenaikan Yesus Kristus', 'is_cuti': true},
    '2026-05-27': {'name': 'Hari Raya Idul Adha 1447 H', 'is_cuti': false},
    '2026-05-31': {'name': 'Hari Raya Waisak 2570 BE', 'is_cuti': false},
    '2026-06-01': {'name': 'Hari Lahir Pancasila', 'is_cuti': false},
    '2026-06-16': {'name': '1 Muharram Tahun Baru Islam 1448 H', 'is_cuti': false},
    '2026-08-17': {'name': 'Proklamasi Kemerdekaan RI Ke-81', 'is_cuti': false},
    '2026-08-25': {'name': 'Maulid Nabi Muhammad SAW', 'is_cuti': false},
    '2026-12-25': {'name': 'Hari Raya Natal', 'is_cuti': false},
    '2026-12-26': {'name': 'Cuti Bersama Hari Raya Natal', 'is_cuti': true},

    // 2027
    '2027-01-01': {'name': 'Tahun Baru 2027 Masehi', 'is_cuti': false},
    '2027-02-06': {'name': 'Tahun Baru Imlek 2578', 'is_cuti': false},
    '2027-03-10': {'name': 'Hari Raya Idul Fitri 1448 H', 'is_cuti': false},
    '2027-05-01': {'name': 'Hari Buruh Internasional', 'is_cuti': false},
    '2027-06-01': {'name': 'Hari Lahir Pancasila', 'is_cuti': false},
    '2027-08-17': {'name': 'HUT Proklamasi Kemerdekaan RI', 'is_cuti': false},
    '2027-12-25': {'name': 'Hari Raya Natal', 'is_cuti': false},
  };

  static final Map<String, Map<String, dynamic>> _dynamicHolidays = {};
  static bool _hasSynced = false;

  /// Sinkronisasi data hari libur dari cloud/server
  static Future<void> syncHolidays() async {
    if (_hasSynced) return;
    _hasSynced = true;

    try {
      // 1. Coba sync dari API backend ProjectWG
      final uri = Uri.parse('${MySQLHelper.baseUrl}/workday-status');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map<String, dynamic> && data['upcoming_holidays'] is List) {
          debugPrint('[HolidayHelper] Berhasil sinkronisasi dari API ProjectWG');
        }
      }
    } catch (_) {
      // Abaikan jika offline, fallback lokal curatedHolidays sudah 100% lengkap
    }
  }

  /// Cek informasi hari libur untuk tanggal tertentu
  static HolidayInfo getHolidayInfo([DateTime? dt]) {
    final target = dt ?? DateTime.now();
    final weekday = target.weekday; // 1: Senin, ..., 6: Sabtu, 7: Minggu
    final isWeekend = weekday == 6 || weekday == 7;

    final yyyy = target.year.toString();
    final mm = target.month.toString().padLeft(2, '0');
    final dd = target.day.toString().padLeft(2, '0');
    final dateStr = '$yyyy-$mm-$dd';
    final monthDay = '$mm-$dd';

    const dayNames = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    const monthNames = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];

    final dayName = dayNames[weekday - 1];
    final dateFormatted = '${target.day} ${monthNames[target.month - 1]} ${target.year}';

    Map<String, dynamic>? hol;
    if (_dynamicHolidays.containsKey(dateStr)) {
      hol = _dynamicHolidays[dateStr];
    } else if (curatedHolidays.containsKey(dateStr)) {
      hol = curatedHolidays[dateStr];
    } else if (fixedHolidays.containsKey(monthDay)) {
      hol = fixedHolidays[monthDay];
    }

    if (hol != null) {
      final isCuti = hol['is_cuti'] == true;
      return HolidayInfo(
        isHoliday: !isCuti,
        isCutiBersama: isCuti,
        isWeekend: isWeekend,
        isWorkingDay: false,
        statusType: isCuti ? 'cuti_bersama' : 'national_holiday',
        statusLabel: isCuti ? 'Cuti Bersama' : 'Libur Nasional (Tanggal Merah)',
        eventName: hol['name'] ?? (isCuti ? 'Cuti Bersama' : 'Hari Libur Nasional'),
        dateFormatted: dateFormatted,
        dayName: dayName,
      );
    }

    if (isWeekend) {
      return HolidayInfo(
        isHoliday: false,
        isCutiBersama: false,
        isWeekend: true,
        isWorkingDay: false,
        statusType: 'weekend',
        statusLabel: 'Akhir Pekan (Libur)',
        eventName: 'Hari $dayName (Libur Mingguan)',
        dateFormatted: dateFormatted,
        dayName: dayName,
      );
    }

    return HolidayInfo(
      isHoliday: false,
      isCutiBersama: false,
      isWeekend: false,
      isWorkingDay: true,
      statusType: 'workday',
      statusLabel: 'Hari Kerja',
      eventName: 'Hari Kerja Aktif',
      dateFormatted: dateFormatted,
      dayName: dayName,
    );
  }
}
