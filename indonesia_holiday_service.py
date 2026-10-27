"""
Indonesia Holiday & Workday Realtime Service
============================================
Mengelola acuan Hari Kerja, Hari Libur Nasional (Tanggal Merah), dan Cuti Bersama Pemerintah Indonesia.
Otomatis memperbarui data tahunan dari data resmi / SKB 3 Menteri dengan cache lokal dan fallback bawaan.
"""

import os
import json
import urllib.request
import threading
from datetime import datetime, date, timedelta

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_FILE = os.path.join(BASE_DIR, 'assets', 'indonesia_holidays_cache.json')
REMOTE_URL = 'https://raw.githubusercontent.com/guangrei/APIHariLibur_V2/main/calendar.min.json'

# Hari Libur Nasional Tetap Setiap Tahun (Bulan-Hari)
FIXED_HOLIDAYS = {
    '01-01': {'name_id': 'Tahun Baru Masehi', 'name_en': "New Year's Day", 'is_cuti': False},
    '05-01': {'name_id': 'Hari Buruh Internasional', 'name_en': 'International Labor Day', 'is_cuti': False},
    '06-01': {'name_id': 'Hari Lahir Pancasila', 'name_en': 'Pancasila Day', 'is_cuti': False},
    '08-17': {'name_id': 'Hari Kemerdekaan RI (HUT RI)', 'name_en': 'Indonesian Independence Day', 'is_cuti': False},
    '12-25': {'name_id': 'Hari Raya Natal', 'name_en': 'Christmas Day', 'is_cuti': False},
    '12-26': {'name_id': 'Cuti Bersama Hari Raya Natal', 'name_en': 'Christmas Collective Leave', 'is_cuti': True},
}

# Kurasi Resmi SKB 3 Menteri untuk Tahun 2024, 2025, 2026, 2027 (Fallback Offline)
OFFLINE_HOLIDAYS = {
    # 2025
    '2025-01-01': {'name_id': 'Tahun Baru 2025 Masehi', 'name_en': "New Year's Day 2025", 'is_cuti': False},
    '2025-01-27': {'name_id': 'Isra Mikraj Nabi Muhammad SAW', 'name_en': "Isra Mi'raj", 'is_cuti': False},
    '2025-01-28': {'name_id': 'Cuti Bersama Tahun Baru Imlek 2576', 'name_en': 'Chinese New Year Collective Leave', 'is_cuti': True},
    '2025-01-29': {'name_id': 'Tahun Baru Imlek 2576 Kongzili', 'name_en': 'Chinese New Year 2576', 'is_cuti': False},
    '2025-03-28': {'name_id': 'Cuti Bersama Hari Suci Nyepi', 'name_en': 'Nyepi Collective Leave', 'is_cuti': True},
    '2025-03-29': {'name_id': 'Hari Suci Nyepi Tahun Baru Saka 1947', 'name_en': 'Nyepi Day', 'is_cuti': False},
    '2025-03-31': {'name_id': 'Hari Raya Idul Fitri 1446 H', 'name_en': 'Eid al-Fitr 1446 H', 'is_cuti': False},
    '2025-04-01': {'name_id': 'Hari Raya Idul Fitri 1446 H', 'name_en': 'Eid al-Fitr 1446 H', 'is_cuti': False},
    '2025-04-02': {'name_id': 'Cuti Bersama Idul Fitri 1446 H', 'name_en': 'Eid al-Fitr Collective Leave', 'is_cuti': True},
    '2025-04-03': {'name_id': 'Cuti Bersama Idul Fitri 1446 H', 'name_en': 'Eid al-Fitr Collective Leave', 'is_cuti': True},
    '2025-04-04': {'name_id': 'Cuti Bersama Idul Fitri 1446 H', 'name_en': 'Eid al-Fitr Collective Leave', 'is_cuti': True},
    '2025-04-07': {'name_id': 'Cuti Bersama Idul Fitri 1446 H', 'name_en': 'Eid al-Fitr Collective Leave', 'is_cuti': True},
    '2025-04-18': {'name_id': 'Wafat Yesus Kristus (Jumat Agung)', 'name_en': 'Good Friday', 'is_cuti': False},
    '2025-04-20': {'name_id': 'Kebangkitan Yesus Kristus (Hari Paskah)', 'name_en': 'Easter Sunday', 'is_cuti': False},
    '2025-05-01': {'name_id': 'Hari Buruh Internasional', 'name_en': 'Labor Day', 'is_cuti': False},
    '2025-05-12': {'name_id': 'Hari Raya Waisak 2569 BE', 'name_en': 'Vesak Day 2569 BE', 'is_cuti': False},
    '2025-05-13': {'name_id': 'Cuti Bersama Hari Raya Waisak', 'name_en': 'Vesak Collective Leave', 'is_cuti': True},
    '2025-05-29': {'name_id': 'Kenaikan Yesus Kristus', 'name_en': 'Ascension Day', 'is_cuti': False},
    '2025-05-30': {'name_id': 'Cuti Bersama Kenaikan Yesus Kristus', 'name_en': 'Ascension Collective Leave', 'is_cuti': True},
    '2025-06-01': {'name_id': 'Hari Lahir Pancasila', 'name_en': 'Pancasila Day', 'is_cuti': False},
    '2025-06-06': {'name_id': 'Hari Raya Idul Adha 1446 H', 'name_en': 'Eid al-Adha 1446 H', 'is_cuti': False},
    '2025-06-09': {'name_id': 'Cuti Bersama Idul Adha 1446 H', 'name_en': 'Eid al-Adha Collective Leave', 'is_cuti': True},
    '2025-06-27': {'name_id': '1 Muharram Tahun Baru Islam 1447 H', 'name_en': 'Islamic New Year 1447 H', 'is_cuti': False},
    '2025-08-17': {'name_id': 'Proklamasi Kemerdekaan RI Ke-80', 'name_en': 'Indonesian Independence Day', 'is_cuti': False},
    '2025-09-05': {'name_id': 'Maulid Nabi Muhammad SAW', 'name_en': "Prophet Muhammad's Birthday", 'is_cuti': False},
    '2025-12-25': {'name_id': 'Hari Raya Natal', 'name_en': 'Christmas Day', 'is_cuti': False},
    '2025-12-26': {'name_id': 'Cuti Bersama Hari Raya Natal', 'name_en': 'Christmas Collective Leave', 'is_cuti': True},

    # 2026 (Tahun Ini)
    '2026-01-01': {'name_id': 'Tahun Baru 2026 Masehi', 'name_en': "New Year's Day 2026", 'is_cuti': False},
    '2026-01-16': {'name_id': 'Isra Mikraj Nabi Muhammad SAW', 'name_en': "Isra Mi'raj", 'is_cuti': False},
    '2026-02-16': {'name_id': 'Cuti Bersama Tahun Baru Imlek 2577', 'name_en': 'Chinese New Year Collective Leave', 'is_cuti': True},
    '2026-02-17': {'name_id': 'Tahun Baru Imlek 2577 Kongzili', 'name_en': 'Chinese New Year 2577', 'is_cuti': False},
    '2026-03-19': {'name_id': 'Cuti Bersama Hari Suci Nyepi', 'name_en': 'Nyepi Collective Leave', 'is_cuti': True},
    '2026-03-20': {'name_id': 'Hari Suci Nyepi Tahun Baru Saka 1948', 'name_en': 'Nyepi Day', 'is_cuti': False},
    '2026-03-21': {'name_id': 'Hari Raya Idul Fitri 1447 H', 'name_en': 'Eid al-Fitr 1447 H', 'is_cuti': False},
    '2026-03-22': {'name_id': 'Hari Raya Idul Fitri 1447 H', 'name_en': 'Eid al-Fitr 1447 H', 'is_cuti': False},
    '2026-03-23': {'name_id': 'Cuti Bersama Idul Fitri 1447 H', 'name_en': 'Eid al-Fitr Collective Leave', 'is_cuti': True},
    '2026-03-24': {'name_id': 'Cuti Bersama Idul Fitri 1447 H', 'name_en': 'Eid al-Fitr Collective Leave', 'is_cuti': True},
    '2026-04-03': {'name_id': 'Wafat Yesus Kristus (Jumat Agung)', 'name_en': 'Good Friday', 'is_cuti': False},
    '2026-05-01': {'name_id': 'Hari Buruh Internasional', 'name_en': 'Labor Day', 'is_cuti': False},
    '2026-05-14': {'name_id': 'Kenaikan Yesus Kristus', 'name_en': 'Ascension Day', 'is_cuti': False},
    '2026-05-15': {'name_id': 'Cuti Bersama Kenaikan Yesus Kristus', 'name_en': 'Ascension Collective Leave', 'is_cuti': True},
    '2026-05-27': {'name_id': 'Hari Raya Idul Adha 1447 H', 'name_en': 'Eid al-Adha 1447 H', 'is_cuti': False},
    '2026-05-31': {'name_id': 'Hari Raya Waisak 2570 BE', 'name_en': 'Vesak Day 2570 BE', 'is_cuti': False},
    '2026-06-01': {'name_id': 'Hari Lahir Pancasila', 'name_en': 'Pancasila Day', 'is_cuti': False},
    '2026-06-16': {'name_id': '1 Muharram Tahun Baru Islam 1448 H', 'name_en': 'Islamic New Year 1448 H', 'is_cuti': False},
    '2026-08-17': {'name_id': 'Proklamasi Kemerdekaan RI Ke-81', 'name_en': 'Indonesian Independence Day', 'is_cuti': False},
    '2026-08-25': {'name_id': 'Maulid Nabi Muhammad SAW', 'name_en': "Prophet Muhammad's Birthday", 'is_cuti': False},
    '2026-12-25': {'name_id': 'Hari Raya Natal', 'name_en': 'Christmas Day', 'is_cuti': False},
    '2026-12-26': {'name_id': 'Cuti Bersama Hari Raya Natal', 'name_en': 'Christmas Collective Leave', 'is_cuti': True},

    # 2027
    '2027-01-01': {'name_id': 'Tahun Baru 2027 Masehi', 'name_en': "New Year's Day 2027", 'is_cuti': False},
    '2027-02-06': {'name_id': 'Tahun Baru Imlek 2578', 'name_en': 'Chinese New Year 2578', 'is_cuti': False},
    '2027-03-10': {'name_id': 'Hari Raya Idul Fitri 1448 H', 'name_en': 'Eid al-Fitr 1448 H', 'is_cuti': False},
    '2027-05-01': {'name_id': 'Hari Buruh Internasional', 'name_en': 'Labor Day', 'is_cuti': False},
    '2027-06-01': {'name_id': 'Hari Lahir Pancasila', 'name_en': 'Pancasila Day', 'is_cuti': False},
    '2027-08-17': {'name_id': 'HUT Proklamasi Kemerdekaan RI', 'name_en': 'Indonesian Independence Day', 'is_cuti': False},
    '2027-12-25': {'name_id': 'Hari Raya Natal', 'name_en': 'Christmas Day', 'is_cuti': False},
}

_HOLIDAYS_DATA = None
_LAST_SYNC_TIME = None


def load_cached_holidays():
    """Muat data hari libur dari cache lokal atau fallback jika belum ada."""
    global _HOLIDAYS_DATA
    if _HOLIDAYS_DATA is not None:
        return _HOLIDAYS_DATA

    data = dict(OFFLINE_HOLIDAYS)

    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, 'r', encoding='utf-8') as f:
                cached = json.load(f)
                if isinstance(cached, dict):
                    data.update(cached)
        except Exception as e:
            print(f"[HolidayService] Gagal membaca cache lokal: {e}")

    _HOLIDAYS_DATA = data
    return _HOLIDAYS_DATA


def sync_holidays_from_cloud():
    """Tarik data kalender resmi terbaru dari GitHub secara background tanpa membebani server."""
    global _HOLIDAYS_DATA, _LAST_SYNC_TIME

    def _sync_worker():
        global _HOLIDAYS_DATA, _LAST_SYNC_TIME
        try:
            req = urllib.request.Request(
                REMOTE_URL,
                headers={'User-Agent': 'TSA-Absensi-WorkdaySync/1.0'}
            )
            with urllib.request.urlopen(req, timeout=8) as res:
                remote_data = json.loads(res.read().decode('utf-8'))

            parsed = {}
            for date_key, val in remote_data.items():
                if not isinstance(val, dict):
                    continue
                # Format tanggal YYYY-MM-DD
                if len(date_key) == 10 and date_key[4] == '-' and date_key[7] == '-':
                    is_holiday = val.get('holiday', True)
                    summary = val.get('summary', ['Hari Libur'])
                    name_id = summary[0] if summary else 'Hari Libur Nasional'
                    is_cuti = 'cuti' in name_id.lower()

                    if is_holiday or is_cuti:
                        parsed[date_key] = {
                            'name_id': name_id,
                            'name_en': val.get('name_en', name_id),
                            'is_cuti': is_cuti
                        }

            if parsed:
                os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
                with open(CACHE_FILE, 'w', encoding='utf-8') as f:
                    json.dump(parsed, f, indent=2, ensure_ascii=False)
                
                if _HOLIDAYS_DATA:
                    _HOLIDAYS_DATA.update(parsed)
                else:
                    _HOLIDAYS_DATA = parsed
                _LAST_SYNC_TIME = datetime.now()
                print(f"[HolidayService] Berhasil sinkronisasi {len(parsed)} hari libur dari cloud.")
        except Exception as err:
            # Tetap aman menggunakan OFFLINE_HOLIDAYS jika internet VPS bermasalah
            print(f"[HolidayService Notice] Cloud sync offline/tertunda: {err}")

    # Jalankan di background thread agar respons web tidak terhambat
    t = threading.Thread(target=_sync_worker, daemon=True)
    t.start()


def get_holiday_for_date(target_date):
    """
    Cek apakah tanggal tertentu merupakan hari libur nasional atau cuti bersama.
    Mengembalikan (is_holiday, is_cuti, event_dict)
    """
    holidays = load_cached_holidays()
    date_str = target_date.strftime('%Y-%m-%d')
    month_day = target_date.strftime('%m-%d')

    # 1. Cek tanggal spesifik YYYY-MM-DD
    if date_str in holidays:
        info = holidays[date_str]
        return True, info.get('is_cuti', False), info

    # 2. Cek hari libur nasional tetap (setiap tahun)
    if month_day in FIXED_HOLIDAYS:
        info = FIXED_HOLIDAYS[month_day]
        return True, info.get('is_cuti', False), info

    return False, False, None


def get_workday_status(dt=None):
    """
    Menganalisis status hari ini / tanggal tertentu:
    - Hari Kerja (Workday): Senin-Jumat & Bukan Tanggal Merah & Bukan Cuti Bersama
    - Akhir Pekan (Weekend): Sabtu / Minggu
    - Hari Libur Nasional (Tanggal Merah): Hari Libur Resmi Pemerintah
    - Cuti Bersama: Cuti Bersama Resmi Pemerintah
    """
    if dt is None:
        dt = datetime.now()

    weekday = dt.weekday()  # 0: Senin, 1: Selasa, ..., 5: Sabtu, 6: Minggu
    is_weekend = weekday in (5, 6)
    is_holiday, is_cuti, holiday_info = get_holiday_for_date(dt.date())

    day_names_id = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"]
    day_names_en = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    month_names_id = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"]
    month_names_en = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    day_name_id = day_names_id[weekday]
    day_name_en = day_names_en[weekday]
    date_formatted_id = f"{dt.day} {month_names_id[dt.month - 1]} {dt.year}"
    date_formatted_en = f"{month_names_en[dt.month - 1]} {dt.day}, {dt.year}"

    if is_cuti:
        status_type = 'cuti_bersama'
        is_working_day = False
        status_label_id = 'Cuti Bersama'
        status_label_en = 'Collective Leave'
        event_name_id = holiday_info['name_id']
        event_name_en = holiday_info.get('name_en', holiday_info['name_id'])
        badge_color = '#ea580c' # Amber / Orange
        badge_class = 'pill-cuti'
        icon = 'bi-umbrella-fill'
    elif is_holiday:
        status_type = 'national_holiday'
        is_working_day = False
        status_label_id = 'Libur Nasional (Tanggal Merah)'
        status_label_en = 'Public Holiday'
        event_name_id = holiday_info['name_id']
        event_name_en = holiday_info.get('name_en', holiday_info['name_id'])
        badge_color = '#dc2626' # Vibrant Red
        badge_class = 'pill-holiday'
        icon = 'bi-calendar-x-fill'
    elif is_weekend:
        status_type = 'weekend'
        is_working_day = False
        status_label_id = 'Akhir Pekan (Libur)'
        status_label_en = 'Weekend (Off)'
        event_name_id = f'Hari {day_name_id} (Libur Mingguan)'
        event_name_en = f'{day_name_en} (Weekly Off)'
        badge_color = '#64748b' # Slate Gray
        badge_class = 'pill-weekend'
        icon = 'bi-cup-hot-fill'
    else:
        status_type = 'workday'
        is_working_day = True
        status_label_id = 'Hari Kerja'
        status_label_en = 'Working Day'
        event_name_id = 'Hari Kerja Aktif (Jam Operasional Kantor)'
        event_name_en = 'Active Working Day (Office Hours)'
        badge_color = '#16a34a' # Emerald Green
        badge_class = 'pill-workday'
        icon = 'bi-briefcase-fill'

    # Daftar Libur Terdekat dalam 30 Hari ke depan
    upcoming = []
    holidays = load_cached_holidays()
    for i in range(1, 31):
        future_d = dt.date() + timedelta(days=i)
        is_f_hol, is_f_cuti, f_info = get_holiday_for_date(future_d)
        if is_f_hol and f_info:
            upcoming.append({
                'date': future_d.strftime('%d-%m-%Y'),
                'name_id': f_info['name_id'],
                'name_en': f_info.get('name_en', f_info['name_id']),
                'is_cuti': is_f_cuti,
                'days_left': i
            })
            if len(upcoming) >= 3:
                break

    return {
        'date_iso': dt.strftime('%Y-%m-%d'),
        'time_str': dt.strftime('%H:%M:%S'),
        'day_id': day_name_id,
        'day_en': day_name_en,
        'date_id': date_formatted_id,
        'date_en': date_formatted_en,
        'display_id': f"{day_name_id}, {date_formatted_id}",
        'display_en': f"{day_name_en}, {date_formatted_en}",
        'is_working_day': is_working_day,
        'is_weekend': is_weekend,
        'is_holiday': is_holiday,
        'is_cuti_bersama': is_cuti,
        'status_type': status_type,
        'status_label_id': status_label_id,
        'status_label_en': status_label_en,
        'event_name_id': event_name_id,
        'event_name_en': event_name_en,
        'badge_color': badge_color,
        'badge_class': badge_class,
        'icon': icon,
        'upcoming_holidays': upcoming
    }


# Inisialisasi awal saat modul di-import
load_cached_holidays()
sync_holidays_from_cloud()
