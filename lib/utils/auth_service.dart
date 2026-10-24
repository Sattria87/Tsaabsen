import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// AuthService — Manajemen Sesi Login Persisten
/// ============================================================
/// Menyimpan data user di SharedPreferences sehingga saat
/// aplikasi ditutup & dibuka kembali, user langsung masuk ke
/// HomeScreen tanpa harus login ulang.
/// Sesi dihapus hanya ketika user menekan tombol Logout.
class AuthService {
  static const _keyIsLoggedIn = 'is_logged_in';
  static const _keyUserData   = 'user_data';

  static final _prefs = SharedPreferencesAsync();

  // ── SIMPAN SESI ──────────────────────────────────────────────
  /// Dipanggil setelah login berhasil.
  /// Menyimpan flag login dan seluruh data user sebagai JSON string langsung ke native storage.
  static Future<bool> saveSession(Map<String, dynamic> userData) async {
    try {
      await _prefs.setBool(_keyIsLoggedIn, true);
      await _prefs.setString(_keyUserData, jsonEncode(userData));
      debugPrint('[AuthService] Sesi berhasil disimpan untuk ${userData['username']}');
      return true;
    } catch (e, stack) {
      debugPrint('[AuthService Error saveSession] $e\n$stack');
      return false;
    }
  }

  // ── CEK SESI ─────────────────────────────────────────────────
  /// Kembalikan true jika ada sesi aktif yang tersimpan.
  static Future<bool> isLoggedIn() async {
    try {
      final val = await _prefs.getBool(_keyIsLoggedIn);
      return val ?? false;
    } catch (e) {
      debugPrint('[AuthService Error isLoggedIn] $e');
      return false;
    }
  }

  // ── AMBIL DATA USER ──────────────────────────────────────────
  /// Kembalikan data user yang tersimpan, atau null jika tidak ada.
  static Future<Map<String, dynamic>?> getSavedUser() async {
    try {
      final raw = await _prefs.getString(_keyUserData);
      if (raw == null || raw.isEmpty) {
        debugPrint('[AuthService] Tidak ada data user tersimpan.');
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        debugPrint('[AuthService] Sesi aktif ditemukan untuk: ${decoded['username']}');
        return decoded;
      }
      return null;
    } catch (e, stack) {
      debugPrint('[AuthService Error getSavedUser] $e\n$stack');
      return null;
    }
  }

  // ── HAPUS SESI (LOGOUT) ───────────────────────────────────────
  /// Dipanggil saat user menekan tombol Logout.
  /// Menghapus semua data sesi dari penyimpanan lokal.
  static Future<void> clearSession() async {
    try {
      await _prefs.remove(_keyIsLoggedIn);
      await _prefs.remove(_keyUserData);
      debugPrint('[AuthService] Sesi berhasil dihapus (logout).');
    } catch (e) {
      debugPrint('[AuthService Error clearSession] $e');
    }
  }
}
