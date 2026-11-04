import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/mysql_helper.dart';
import '../widgets/employee_avatar.dart';
import 'face_capture_screen.dart';

class LocationVerificationScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const LocationVerificationScreen({super.key, required this.userData});

  @override
  State<LocationVerificationScreen> createState() =>
      _LocationVerificationScreenState();
}

class _LocationVerificationScreenState
    extends State<LocationVerificationScreen> {
  late final MapController _mapController;

  bool _isCheckingLocation = false;
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _selectedBranch;
  String _statusMessage = 'Memuat data kantor cabang...';
  bool _isWithinRadius =
      false; // Ketat: harus diverifikasi GPS secara nyata (tanpa bypass)
  double _currentDistance = 0.0;
  Position? _currentUserPosition;

  // ============================================================
  // VARIABEL STATUS FITUR OPSI "OTHER" (TUGAS LUAR / LAPANGAN)
  // ============================================================
  static const Map<String, dynamic> _otherBranch = {
    'id': -999,
    'branch_name': 'Other (Luar Kantor / Lapangan)',
    'city': 'Site / Customer / Luar Kantor',
    'latitude': -7.3402015,
    'longitude': 112.7202620,
    'radius': 0,
    'is_other': true,
  };

  bool get _isOtherMode =>
      _selectedBranch != null && _selectedBranch!['id'] == _otherBranch['id'];

  String? _selectedOtherCategory = 'Berada di Site'; // Default: 'Berada di Site'
  final TextEditingController _otherPlaceNameController =
      TextEditingController();
  Position? _otherRealtimeGps;
  bool _isRecordingGps = false;
  DateTime? _gpsRecordedAt;
  File? _otherEvidenceFile;
  final ImagePicker _imagePicker = ImagePicker();

  bool get _isOtherValid {
    return _selectedOtherCategory != null &&
        _otherPlaceNameController.text.trim().isNotEmpty &&
        _otherRealtimeGps != null &&
        _otherEvidenceFile != null;
  }

  // Fallback 3 cabang utama (termasuk lokasi testing) jika backend offline/belum terhubung
  static const List<Map<String, dynamic>> _defaultBranches = [
    {
      'id': 1,
      'branch_name': 'TUNGGAL SAHABAT ABADI',
      'city': 'Surabaya',
      'latitude': -7.3402015,
      'longitude': 112.7202620,
      'radius': 100,
    },
    {
      'id': 2,
      'branch_name': 'Markas Kopasus (Testing)',
      'city': 'Surabaya',
      'latitude': -7.3175435,
      'longitude': 112.7281284,
      'radius': 100,
    },
    {
      'id': 3,
      'branch_name': 'Cabang Sidoarjo',
      'city': 'Sidoarjo',
      'latitude': -7.4478000,
      'longitude': 112.7183000,
      'radius': 100,
    },
  ];

  static Map<String, dynamic> get _defaultBranch => _defaultBranches.first;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _branches = List.from(_defaultBranches)..add(_otherBranch);
    _selectedBranch = _defaultBranches.first;
    _loadBranchesFromDB();
  }

  @override
  void dispose() {
    _otherPlaceNameController.dispose();
    super.dispose();
  }

  // 1. Ambil data kantor cabang dari database MySQL
  Future<void> _loadBranchesFromDB() async {
    setState(() {
      _statusMessage = 'Memeriksa status kehadiran...';
    });

    // Validasi: Cegah Clock In jika pengajuan izin hari ini ditolak (Alpha) atau sedang aktif
    final username = widget.userData['username'] ?? '';
    if (username.isNotEmpty) {
      final status = await MySQLHelper.getTodayAttendanceStatus(username);
      if (!mounted) return;

      if (status != null &&
          status['hasPermission'] == true &&
          (status['permissionStatus'] ?? '').toString().toLowerCase() ==
              'rejected') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pengajuan izin Anda hari ini telah ditolak (Alpha). Anda tidak dapat melakukan Clock In Hadir.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
        return;
      }

      if (status != null &&
          status['hasClockedIn'] == true &&
          status['hasClockedOut'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Anda sedang dalam status Clock In! Silakan Clock Out terlebih dahulu.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
        return;
      }
    }

    try {
      final loadedBranches = await MySQLHelper.getBranches();

      if (!mounted) return;
      setState(() {
        final list = <Map<String, dynamic>>[];
        if (loadedBranches.isNotEmpty) {
          list.addAll(loadedBranches);
        } else {
          list.addAll(_defaultBranches);
        }
        // Tambahkan opsi Other di urutan paling akhir
        list.add(_otherBranch);
        _branches = list;

        // Cari cabang yang cocok dengan profil karyawan
        final userBranch = (widget.userData['branch'] ?? '')
            .toString()
            .toLowerCase();
        Map<String, dynamic>? matched;
        for (var b in _branches) {
          if (b['id'] == _otherBranch['id']) continue;
          final bName = (b['branch_name'] ?? '').toString().toLowerCase();
          final bCity = (b['city'] ?? '').toString().toLowerCase();
          if (userBranch.isNotEmpty &&
              (bName.contains(userBranch) || bCity.contains(userBranch))) {
            matched = b;
            break;
          }
        }
        _selectedBranch = matched ?? _branches.first;
      });

      // Pindahkan peta ke koordinat cabang yang dipilih
      _recenterMap();

      // Cek lokasi riil pengguna via GPS nyata (AUTO-DETECT SEMUA CABANG)
      await _checkUserLocation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _branches = List.from(_defaultBranches)..add(_otherBranch);
        _selectedBranch = _defaultBranches.first;
      });
      _recenterMap();
      await _checkUserLocation();
    }
  }

  // Dipanggil saat user memilih cabang secara manual di dropdown / peta
  void _onBranchSelected(Map<String, dynamic> branch) {
    setState(() {
      _selectedBranch = branch;
      if (branch['id'] == _otherBranch['id']) {
        _selectedOtherCategory ??= 'Berada di Site';
        _isWithinRadius = false;
        if (_currentUserPosition != null && _otherRealtimeGps == null) {
          _otherRealtimeGps = _currentUserPosition;
          _gpsRecordedAt = DateTime.now();
        }
      }
    });
    _recenterMap();

    if (branch['id'] == _otherBranch['id']) {
      return;
    }

    // Jika koordinat GPS sudah ada, langsung verifikasi ulang jaraknya
    if (_currentUserPosition != null) {
      final targetLat = _parseDouble(branch['latitude'], -7.3402015);
      final targetLon = _parseDouble(branch['longitude'], 112.7202620);
      final allowedRadius = _parseInt(branch['radius'], 100);

      final dist = Geolocator.distanceBetween(
        _currentUserPosition!.latitude,
        _currentUserPosition!.longitude,
        targetLat,
        targetLon,
      );

      setState(() {
        _currentDistance = dist;
        if (dist <= allowedRadius) {
          _isWithinRadius = true;
          _statusMessage =
              'Lokasi Terverifikasi: Berada dalam radius ${branch['branch_name']} ($allowedRadius meter)';
        } else {
          _isWithinRadius = false;
          _statusMessage =
              'Di luar radius ${branch['branch_name']}! Jarak: ${dist.toStringAsFixed(0)}m (Maks: ${allowedRadius}m)';
        }
      });
    } else {
      _checkUserLocation();
    }
  }

  double _parseDouble(dynamic val, double fallback) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? fallback;
  }

  int _parseInt(dynamic val, int fallback) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? fallback;
  }

  void _recenterMap() {
    if (_isOtherMode) {
      final pos = _otherRealtimeGps ?? _currentUserPosition;
      if (pos != null) {
        try {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 16.5);
        } catch (_) {}
      }
      return;
    }

    if (_selectedBranch != null) {
      final targetLat = _parseDouble(_selectedBranch!['latitude'], -7.3402015);
      final targetLon = _parseDouble(
        _selectedBranch!['longitude'],
        112.7202620,
      );
      try {
        _mapController.move(LatLng(targetLat, targetLon), 16.5);
      } catch (_) {}
    }
  }

  // 2. Pengecekan GPS Asli menggunakan Geolocator (KETAT, TANPA BYPASS)
  Future<void> _checkUserLocation() async {
    if (_selectedBranch == null) return;

    setState(() {
      _isCheckingLocation = true;
      _statusMessage = 'Mendeteksi posisi GPS nyata Anda...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _isCheckingLocation = false;
          _isWithinRadius = false;
          _statusMessage =
              'GPS perangkat belum aktif. Harap aktifkan GPS HP Anda!';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() {
            _isCheckingLocation = false;
            _isWithinRadius = false;
            _statusMessage =
                'Izin lokasi ditolak! Diperlukan akses GPS untuk Clock In.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _isCheckingLocation = false;
          _isWithinRadius = false;
          _statusMessage =
              'Izin lokasi ditolak permanen. Buka Pengaturan HP untuk mengizinkan.';
        });
        return;
      }

      Position userPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      // Jika user sedang memilih Other, pertahankan pilihan Other dan update GPS realtime
      if (_isOtherMode) {
        if (!mounted) return;
        setState(() {
          _currentUserPosition = userPosition;
          _isCheckingLocation = false;
          _otherRealtimeGps ??= userPosition;
          _gpsRecordedAt ??= DateTime.now();
        });
        _recenterMap();
        return;
      }

      // ============================================================
      // LOGIKA AUTO-DETECT CERDAS KE SELURUH CABANG
      // ============================================================
      Map<String, dynamic>? withinRadiusBranch;
      Map<String, dynamic>? nearestBranch;
      double minDistance = double.infinity;

      for (var b in _branches) {
        // Lewati opsi 'Other' saat auto-detect
        if (b['id'] == _otherBranch['id'] || b['is_other'] == true) continue;

        final bLat = _parseDouble(b['latitude'], -7.3402015);
        final bLon = _parseDouble(b['longitude'], 112.7202620);
        final bRad = _parseInt(b['radius'], 100);

        final dist = Geolocator.distanceBetween(
          userPosition.latitude,
          userPosition.longitude,
          bLat,
          bLon,
        );

        // Jika user berada di dalam radius cabang yang sedang dipilih, utamakan cabang tersebut
        if (_selectedBranch != null &&
            b['id'] == _selectedBranch!['id'] &&
            dist <= bRad) {
          withinRadiusBranch = b;
          break;
        }

        // Simpan cabang yang radiusnya cocok
        if (dist <= bRad && withinRadiusBranch == null) {
          withinRadiusBranch = b;
        }

        if (dist < minDistance) {
          minDistance = dist;
          nearestBranch = b;
        }
      }

      if (!mounted) return;

      // KASUS 1: Pengguna terdeteksi di dalam radius salah satu cabang
      if (withinRadiusBranch != null) {
        final activeRad = _parseInt(withinRadiusBranch['radius'], 100);
        final dist = Geolocator.distanceBetween(
          userPosition.latitude,
          userPosition.longitude,
          _parseDouble(withinRadiusBranch['latitude'], -7.3402015),
          _parseDouble(withinRadiusBranch['longitude'], 112.7202620),
        );

        setState(() {
          _selectedBranch = withinRadiusBranch;
          _currentUserPosition = userPosition;
          _currentDistance = dist;
          _isWithinRadius = true;
          _isCheckingLocation = false;
          _statusMessage =
              'Terverifikasi di ${withinRadiusBranch!['branch_name']}: Jarak ${dist.toStringAsFixed(0)}m (Maks: ${activeRad}m)';
        });
        _recenterMap();
        return;
      }

      // KASUS 2: Pengguna di luar radius semua cabang
      final activeTarget = _selectedBranch ?? nearestBranch ?? _branches.first;
      final targetLat = _parseDouble(activeTarget['latitude'], -7.3402015);
      final targetLon = _parseDouble(activeTarget['longitude'], 112.7202620);
      final allowedRadius = _parseInt(activeTarget['radius'], 100);

      final distanceInMeters = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        targetLat,
        targetLon,
      );

      setState(() {
        _selectedBranch = activeTarget;
        _currentUserPosition = userPosition;
        _currentDistance = distanceInMeters;
        _isCheckingLocation = false;
        _isWithinRadius = false;
        _statusMessage =
            'Di luar radius ${activeTarget['branch_name']} (Maks: ${allowedRadius}m). Jarak: ${distanceInMeters.toStringAsFixed(0)}m. Terdekat: ${nearestBranch?['branch_name'] ?? activeTarget['branch_name']} (${minDistance.toStringAsFixed(0)}m)';
      });
      _recenterMap();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _isWithinRadius = false; // KETAT: jangan bypass jika timeout!
        _statusMessage =
            'Waktu GPS habis. Pastikan Anda berada di luar ruangan dengan sinyal GPS baik.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _isWithinRadius = false; // KETAT: jangan bypass jika ada error!
        _statusMessage = 'Gagal mendeteksi lokasi GPS: $e';
      });
    }
  }

  // ============================================================
  // FUNGSI KHUSUS OPSI OTHER: PENCATATAN GPS & FOTO EVIDENCE
  // ============================================================
  Future<void> _captureRealtimeGps() async {
    setState(() => _isRecordingGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS HP Anda belum aktif. Harap aktifkan GPS!'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isRecordingGps = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin GPS ditolak!'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isRecordingGps = false);
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;
      setState(() {
        _otherRealtimeGps = pos;
        _currentUserPosition = pos;
        _gpsRecordedAt = DateTime.now();
        _isRecordingGps = false;
      });

      try {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 16.5);
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'GPS Realtime Tercatat: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}',
          ),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecordingGps = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mencatat koordinat GPS realtime: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickEvidence(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() {
          _otherEvidenceFile = File(picked.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengambil foto evidence: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s WIB';
  }

  // Beralih ke halaman Foto Selfie setelah validasi
  void _goToFaceCapture() {
    if (_isOtherMode) {
      if (!_isOtherValid) {
        String errorMsg = 'Harap lengkapi formulir absensi tugas luar:';
        if (_selectedOtherCategory == null) {
          errorMsg = 'Pilih kategori (Berada di Site / Bertemu Customer / Lainnya)';
        } else if (_otherPlaceNameController.text.trim().isEmpty) {
          errorMsg = 'Harap isi keterangan nama site / tempat kunjungan.';
        } else if (_otherRealtimeGps == null) {
          errorMsg =
              'Harap tekan tombol "Catat Koordinat GPS Realtime" terlebih dahulu.';
        } else if (_otherEvidenceFile == null) {
          errorMsg = 'Harap ambil/lampirkan foto evidence di lokasi.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(errorMsg),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      final category = _selectedOtherCategory ?? 'Tugas Luar';
      final place = _otherPlaceNameController.text.trim();
      final lat = _otherRealtimeGps!.latitude.toStringAsFixed(6);
      final lon = _otherRealtimeGps!.longitude.toStringAsFixed(6);
      final fullLocationName = 'Other ($category) - $place [GPS: $lat, $lon]';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FaceCaptureScreen(
            userData: widget.userData,
            locationName: fullLocationName,
            distance: 0,
            evidenceImage: _otherEvidenceFile,
          ),
        ),
      );
      return;
    }

    final locationName = _selectedBranch?['branch_name'] ?? 'Kantor Pusat';
    final distance = _currentDistance.round();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceCaptureScreen(
          userData: widget.userData,
          locationName: locationName,
          distance: distance,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Koordinat pusat peta
    double mapCenterLat = -7.3402015;
    double mapCenterLon = 112.7202620;

    if (_isOtherMode) {
      if (_otherRealtimeGps != null) {
        mapCenterLat = _otherRealtimeGps!.latitude;
        mapCenterLon = _otherRealtimeGps!.longitude;
      } else if (_currentUserPosition != null) {
        mapCenterLat = _currentUserPosition!.latitude;
        mapCenterLon = _currentUserPosition!.longitude;
      }
    } else {
      mapCenterLat = _parseDouble(
        _selectedBranch?['latitude'] ?? _defaultBranch['latitude'],
        -7.3402015,
      );
      mapCenterLon = _parseDouble(
        _selectedBranch?['longitude'] ?? _defaultBranch['longitude'],
        112.7202620,
      );
    }

    final int allowedRadius = _parseInt(
      _selectedBranch?['radius'] ?? _defaultBranch['radius'],
      100,
    );

    final String displayName =
        widget.userData['name']?.toString().isNotEmpty == true
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
              // ================= 1. HEADER & PROFILE CARD SECTION =================
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Latar Belakang Lengkung Biru Navy Tua (Sesuai Desain)
                  Container(
                    height: 150,
                    decoration: const BoxDecoration(
                      color: Color(0xFF131B3E),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(36),
                        bottomRight: Radius.circular(36),
                      ),
                    ),
                    padding: const EdgeInsets.only(
                      top: 44,
                      left: 16,
                      right: 16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Kembali',
                        ),
                      ],
                    ),
                  ),

                  // Kartu Profil Mengambang dengan Garis Kuning Keemasan (Sesuai Desain)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 52,
                      left: 24,
                      right: 24,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(
                            0xFFFFD166,
                          ), // Garis emas/kuning persis gambar
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
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
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                            child: EmployeeAvatarWidget(
                              userData: widget.userData,
                              radius: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Detail Nama & Status
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
                                Text(
                                  _isOtherMode
                                      ? 'Clock In (Tugas Luar)'
                                      : 'Clock In',
                                  style: TextStyle(
                                    color: _isOtherMode
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFF22C55E),
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

              const SizedBox(height: 28),

              // ================= 2. STEPPER PROGRESS BAR =================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          // Titik dan Garis Penghubung
                          Row(
                            children: [
                              // Langkah 1: Titik Oranye (Aktif)
                              Container(
                                width: 13,
                                height: 13,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF5722),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 3,
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              // Langkah 2: Titik Abu-Abu
                              Container(
                                width: 13,
                                height: 13,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFCBD5E1),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 3,
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              // Langkah 3: Titik Abu-Abu
                              Container(
                                width: 13,
                                height: 13,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFCBD5E1),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Label Teks Langkah
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Lokasi',
                                style: TextStyle(
                                  color: Color(0xFFFF5722),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _isOtherMode ? 'Evidence' : 'Radius',
                                style: const TextStyle(
                                  color: Color(0xFFFF5722),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'Clock In',
                                style: TextStyle(
                                  color: Color(0xFF22C55E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Tombol Refresh GPS
                    InkWell(
                      onTap: _isOtherMode
                          ? _captureRealtimeGps
                          : _checkUserLocation,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 14),
                            SizedBox(width: 3),
                            Text(
                              'GPS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ================= 2.5 KANTOR CABANG SELECTOR =================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isOtherMode
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFE2E8F0),
                      width: _isOtherMode ? 1.5 : 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _isOtherMode
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                              : const Color(0xFF007AFF).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isOtherMode
                              ? Icons.alt_route_rounded
                              : Icons.business_rounded,
                          color: _isOtherMode
                              ? const Color(0xFFD97706)
                              : const Color(0xFF007AFF),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'KANTOR CABANG',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.4,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isOtherMode
                                        ? const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.15)
                                        : const Color(0xFF10B981)
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _isOtherMode ? 'Tugas Luar' : 'Auto-Detect',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: _isOtherMode
                                          ? const Color(0xFFD97706)
                                          : const Color(0xFF059669),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<dynamic>(
                                value: _selectedBranch?['id'],
                                isDense: true,
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Color(0xFF1E293B),
                                  size: 20,
                                ),
                                items: _branches.map((b) {
                                  final isOtherItem =
                                      b['id'] == _otherBranch['id'];
                                  final bName =
                                      b['branch_name']?.toString() ?? 'Cabang';
                                  final bCity = b['city']?.toString() ?? '';
                                  final label = isOtherItem
                                      ? '⭐ $bName'
                                      : (bCity.isNotEmpty
                                          ? '$bName ($bCity)'
                                          : bName);

                                  return DropdownMenuItem<dynamic>(
                                    value: b['id'],
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isOtherItem
                                            ? const Color(0xFFD97706)
                                            : const Color(0xFF1E293B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (selectedId) {
                                  if (selectedId != null) {
                                    final chosen = _branches.firstWhere(
                                      (b) => b['id'] == selectedId,
                                      orElse: () => _branches.first,
                                    );
                                    _onBranchSelected(chosen);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Banner rekomendasi jika user di luar radius kantor dan belum pilih Other
              if (!_isOtherMode &&
                  !_isWithinRadius &&
                  !_isCheckingLocation) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_rounded,
                          color: Color(0xFFD97706),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tidak berada di kantor cabang?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                'Pilih Other jika sedang di site atau bertemu customer.',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            final otherChoice = _branches.firstWhere(
                              (b) => b['id'] == _otherBranch['id'],
                              orElse: () => _otherBranch,
                            );
                            _onBranchSelected(otherChoice);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Pilih Other',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // ================= 2.6 FORM ISIAN KHUSUS OPSI "OTHER" =================
              if (_isOtherMode) ...[
                const SizedBox(height: 10),
                _buildOtherFormCard(),
              ],

              const SizedBox(height: 12),

              // ================= 3. WIDGET PETA DENGAN RADIUS & PIN =================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: LatLng(mapCenterLat, mapCenterLon),
                            initialZoom: 16.5,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all,
                            ),
                          ),
                          children: [
                            // Tile Lapisan Peta OpenStreetMap
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.projectwg',
                            ),

                            // Lingkaran Radius
                            if (!_isOtherMode)
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: LatLng(mapCenterLat, mapCenterLon),
                                    color: const Color(
                                      0x4D4ADE80,
                                    ), // Hijau transparan
                                    borderColor: const Color(0xFF22C55E),
                                    borderStrokeWidth: 1.5,
                                    useRadiusInMeter: true,
                                    radius: allowedRadius.toDouble(),
                                  ),
                                ],
                              )
                            else if (_otherRealtimeGps != null)
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: LatLng(
                                      _otherRealtimeGps!.latitude,
                                      _otherRealtimeGps!.longitude,
                                    ),
                                    color: const Color(
                                      0x330EA5E9,
                                    ), // Biru cyan transparan
                                    borderColor: const Color(0xFF0EA5E9),
                                    borderStrokeWidth: 1.5,
                                    useRadiusInMeter: true,
                                    radius: (_otherRealtimeGps!.accuracy > 0
                                            ? _otherRealtimeGps!.accuracy
                                            : 25.0)
                                        .clamp(15.0, 80.0),
                                  ),
                                ],
                              ),

                            // MarkerLayer
                            MarkerLayer(
                              markers: [
                                // Marker cabang fisik lainnya
                                for (var b in _branches)
                                  if (b['id'] != _otherBranch['id'] &&
                                      b['id'] != _selectedBranch?['id'])
                                    Marker(
                                      point: LatLng(
                                        _parseDouble(b['latitude'], -7.3402015),
                                        _parseDouble(
                                          b['longitude'],
                                          112.7202620,
                                        ),
                                      ),
                                      width: 32,
                                      height: 32,
                                      child: GestureDetector(
                                        onTap: () => _onBranchSelected(b),
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Color(0xFF94A3B8),
                                          size: 28,
                                        ),
                                      ),
                                    ),

                                // Marker Cabang Aktif Dipilih (jika bukan other)
                                if (!_isOtherMode)
                                  Marker(
                                    point: LatLng(mapCenterLat, mapCenterLon),
                                    width: 44,
                                    height: 44,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Color(0xFF06B6D4),
                                      size: 42,
                                    ),
                                  ),

                                // Marker Posisi GPS Realtime Other
                                if (_isOtherMode && _otherRealtimeGps != null)
                                  Marker(
                                    point: LatLng(
                                      _otherRealtimeGps!.latitude,
                                      _otherRealtimeGps!.longitude,
                                    ),
                                    width: 46,
                                    height: 46,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Color(0xFFFF5722),
                                      size: 44,
                                    ),
                                  ),

                                // Marker posisi pengguna saat ini
                                if (_currentUserPosition != null &&
                                    (!_isOtherMode ||
                                        _otherRealtimeGps == null))
                                  Marker(
                                    point: LatLng(
                                      _currentUserPosition!.latitude,
                                      _currentUserPosition!.longitude,
                                    ),
                                    width: 18,
                                    height: 18,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF007AFF),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.2,
                                            ),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        // Indikator Loading GPS Tipis di Atas Peta
                        if (_isCheckingLocation || _isRecordingGps)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF007AFF),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isRecordingGps
                                        ? 'Mencatat GPS...'
                                        : 'Memindai GPS...',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ================= 4. STATUS RADIUS / KELENGKAPAN =================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isOtherMode
                          ? (_isOtherValid
                              ? Icons.check_circle_outline
                              : Icons.info_outline)
                          : (_isWithinRadius
                              ? Icons.check_circle_outline
                              : Icons.info_outline),
                      color: _isOtherMode
                          ? (_isOtherValid
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFD97706))
                          : (_isWithinRadius
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444)),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _isOtherMode
                            ? (_isOtherValid
                                ? 'Data kehadiran $_selectedOtherCategory lengkap & terverifikasi GPS realtime.'
                                : (_otherRealtimeGps == null
                                    ? 'Harap catat koordinat GPS realtime terlebih dahulu.'
                                    : (_otherPlaceNameController
                                            .text
                                            .trim()
                                            .isEmpty
                                        ? 'Harap isi keterangan nama site / tempat.'
                                        : 'Harap lampirkan foto evidence di lokasi.')))
                            : (_isWithinRadius
                                ? 'Anda berada dalam radius $allowedRadius meter'
                                : (_isCheckingLocation
                                    ? 'Mendeteksi posisi GPS Anda...'
                                    : 'Anda berada di luar radius ($allowedRadius m). Silakan mendekat atau pilih opsi Other jika sedang di site/customer.')),
                        style: TextStyle(
                          color: _isOtherMode
                              ? (_isOtherValid
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFB45309))
                              : (_isWithinRadius
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFEF4444)),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ================= 5. TOMBOL LANJUT SELFIE =================
              Center(
                child: SizedBox(
                  width: 220,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isOtherMode
                        ? (_isOtherValid ? _goToFaceCapture : () => _goToFaceCapture())
                        : ((_isWithinRadius && !_isCheckingLocation)
                            ? _goToFaceCapture
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFFDC2626),
                                    content: Text(
                                      _statusMessage.isNotEmpty
                                          ? _statusMessage
                                          : 'Anda berada di luar radius kantor ($allowedRadius m). Jika sedang tugas luar, silakan pilih opsi "Other"!',
                                    ),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isOtherMode
                          ? (_isOtherValid
                              ? const Color(0xFF007AFF)
                              : const Color(0xFF94A3B8))
                          : ((_isWithinRadius && !_isCheckingLocation)
                              ? const Color(0xFF007AFF)
                              : const Color(0xFF94A3B8)),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Lanjut Selfie',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WIDGET CARD FORM KHUSUS OPSI "OTHER"
  // ============================================================
  Widget _buildOtherFormCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Opsi Other
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.alt_route_rounded,
                    color: Color(0xFFE65100),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Presensi Luar Kantor (Other)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pilih kegiatan, isi tempat, catat GPS & lampirkan bukti',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Pilihan Kategori (Berada di Site, Bertemu Customer, Lainnya)
            const Text(
              'PILIH STATUS KEBERADAAN *',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildCategoryChip(
                  label: 'Berada di Site',
                  icon: Icons.engineering_rounded,
                  value: 'Berada di Site',
                ),
                _buildCategoryChip(
                  label: 'Bertemu Customer',
                  icon: Icons.handshake_rounded,
                  value: 'Bertemu Customer',
                ),
                _buildCategoryChip(
                  label: 'Lainnya',
                  icon: Icons.business_center_rounded,
                  value: 'Lainnya',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Keterangan Nama Site / Tempat
            Text(
              _selectedOtherCategory == 'Bertemu Customer'
                  ? 'NAMA TEMPAT / PERUSAHAAN CUSTOMER *'
                  : (_selectedOtherCategory == 'Berada di Site'
                      ? 'NAMA SITE / PROYEK *'
                      : 'KETERANGAN NAMA TEMPAT / DINAS *'),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _otherPlaceNameController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                prefixIcon: const Icon(
                  Icons.place_rounded,
                  color: Color(0xFF64748B),
                  size: 20,
                ),
                hintText: _selectedOtherCategory == 'Bertemu Customer'
                    ? 'Contoh: PT Sumber Rejeki / Kantor Klien Sudirman'
                    : (_selectedOtherCategory == 'Berada di Site'
                        ? 'Contoh: Site Proyek Tol Gempol KM 12 / Gudang Perak'
                        : 'Contoh: Workshop Pelatihan / Seminar / Dinas Luar'),
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF007AFF),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Tombol Catat LongLat GPS Realtime
            const Text(
              'KOORDINAT GPS REALTIME *',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _isRecordingGps ? null : _captureRealtimeGps,
                icon: _isRecordingGps
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.my_location_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                label: Text(
                  _isRecordingGps
                      ? 'Mengambil Titik GPS Realtime...'
                      : (_otherRealtimeGps == null
                          ? 'Catat Koordinat GPS Realtime'
                          : 'Perbarui Koordinat GPS Realtime'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // Info box setelah koordinat tercatat
            if (_otherRealtimeGps != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lat: ${_otherRealtimeGps!.latitude.toStringAsFixed(6)}, Lon: ${_otherRealtimeGps!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF166534),
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Akurasi: ±${_otherRealtimeGps!.accuracy.toStringAsFixed(1)}m • Tercatat: ${_gpsRecordedAt != null ? _formatTime(_gpsRecordedAt!) : 'Realtime'}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // 4. Evidence (Foto Bukti di Lokasi)
            const Text(
              'EVIDENCE / FOTO BUKTI DI LOKASI *',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Ambil foto bukti keberadaan Anda di site atau tempat customer',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),

            if (_otherEvidenceFile == null) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickEvidence(ImageSource.camera),
                      icon: const Icon(
                        Icons.camera_alt_rounded,
                        size: 18,
                        color: Color(0xFF007AFF),
                      ),
                      label: const Text(
                        'Buka Kamera',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(
                          color: Color(0xFFBFDBFE),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: const Color(0xFFEFF6FF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickEvidence(ImageSource.gallery),
                      icon: const Icon(
                        Icons.photo_library_rounded,
                        size: 18,
                        color: Color(0xFF475569),
                      ),
                      label: const Text(
                        'Pilih Galeri',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF475569),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(
                          color: Color(0xFFE2E8F0),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: const Color(0xFFF8FAFC),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Preview Foto Evidence
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFBBF7D0),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Image.file(
                            _otherEvidenceFile!,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Evidence Siap',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () => _pickEvidence(ImageSource.camera),
                            icon: const Icon(
                              Icons.sync_rounded,
                              size: 16,
                              color: Color(0xFF007AFF),
                            ),
                            label: const Text(
                              'Ganti Foto',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _otherEvidenceFile = null),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: Color(0xFFEF4444),
                            ),
                            label: const Text(
                              'Hapus',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Chip Pilihan Kategori
  Widget _buildCategoryChip({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final bool isSelected = _selectedOtherCategory == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedOtherCategory = value;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF).withValues(alpha: 0.1)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF007AFF)
                : const Color(0xFFE2E8F0),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? const Color(0xFF007AFF)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF007AFF)
                    : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
