import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/mysql_helper.dart';
import '../widgets/employee_avatar.dart';
import 'face_capture_screen.dart';

class LocationVerificationScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const LocationVerificationScreen({super.key, required this.userData});

  @override
  State<LocationVerificationScreen> createState() => _LocationVerificationScreenState();
}

class _LocationVerificationScreenState extends State<LocationVerificationScreen> {
  late final MapController _mapController;

  bool _isCheckingLocation = false;
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _selectedBranch;
  String _statusMessage = 'Memuat data kantor cabang...';
  bool _isWithinRadius = false; // Ketat: harus diverifikasi GPS secara nyata (tanpa bypass)
  double _currentDistance = 0.0;
  Position? _currentUserPosition;

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
    _branches = List.from(_defaultBranches);
    _selectedBranch = _defaultBranches.first;
    _loadBranchesFromDB();
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
          (status['permissionStatus'] ?? '').toString().toLowerCase() == 'rejected') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengajuan izin Anda hari ini telah ditolak (Alpha). Anda tidak dapat melakukan Clock In Hadir.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
        return;
      }

      if (status != null && status['hasClockedIn'] == true && status['hasClockedOut'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anda sedang dalam status Clock In! Silakan Clock Out terlebih dahulu.'),
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
        if (loadedBranches.isNotEmpty) {
          _branches = loadedBranches;
        } else {
          _branches = List.from(_defaultBranches);
        }

        // Cari cabang yang cocok dengan profil karyawan
        final userBranch = (widget.userData['branch'] ?? '').toString().toLowerCase();
        Map<String, dynamic>? matched;
        for (var b in _branches) {
          final bName = (b['branch_name'] ?? '').toString().toLowerCase();
          final bCity = (b['city'] ?? '').toString().toLowerCase();
          if (userBranch.isNotEmpty && (bName.contains(userBranch) || bCity.contains(userBranch))) {
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
        _branches = List.from(_defaultBranches);
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
    });
    _recenterMap();

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
          _statusMessage = 'Lokasi Terverifikasi: Berada dalam radius ${branch['branch_name']} ($allowedRadius meter)';
        } else {
          _isWithinRadius = false;
          _statusMessage = 'Di luar radius ${branch['branch_name']}! Jarak: ${dist.toStringAsFixed(0)}m (Maks: ${allowedRadius}m)';
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
    if (_selectedBranch != null) {
      final targetLat = _parseDouble(_selectedBranch!['latitude'], -7.3402015);
      final targetLon = _parseDouble(_selectedBranch!['longitude'], 112.7202620);
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
          _statusMessage = 'GPS perangkat belum aktif. Harap aktifkan GPS HP Anda!';
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
            _statusMessage = 'Izin lokasi ditolak! Diperlukan akses GPS untuk Clock In.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _isCheckingLocation = false;
          _isWithinRadius = false;
          _statusMessage = 'Izin lokasi ditolak permanen. Buka Pengaturan HP untuk mengizinkan.';
        });
        return;
      }

      Position userPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      // ============================================================
      // LOGIKA AUTO-DETECT CERDAS KE SELURUH CABANG
      // ============================================================
      Map<String, dynamic>? withinRadiusBranch;
      Map<String, dynamic>? nearestBranch;
      double minDistance = double.infinity;

      for (var b in _branches) {
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
        if (_selectedBranch != null && b['id'] == _selectedBranch!['id'] && dist <= bRad) {
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
          _statusMessage = 'Terverifikasi di ${withinRadiusBranch!['branch_name']}: Jarak ${dist.toStringAsFixed(0)}m (Maks: ${activeRad}m)';
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
        _statusMessage = 'Di luar radius ${activeTarget['branch_name']} (${distanceInMeters.toStringAsFixed(0)}m). Terdekat: ${nearestBranch?['branch_name'] ?? activeTarget['branch_name']} (${minDistance.toStringAsFixed(0)}m)';
      });
      _recenterMap();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _isWithinRadius = false; // KETAT: jangan bypass jika timeout!
        _statusMessage = 'Waktu GPS habis. Pastikan Anda berada di luar ruangan dengan sinyal GPS baik.';
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

  // Beralih ke halaman Foto Selfie setelah radius terverifikasi
  void _goToFaceCapture() {
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
    final double targetLat = _parseDouble(_selectedBranch?['latitude'] ?? _defaultBranch['latitude'], -7.3402015);
    final double targetLon = _parseDouble(_selectedBranch?['longitude'] ?? _defaultBranch['longitude'], 112.7202620);
    final int allowedRadius = _parseInt(_selectedBranch?['radius'] ?? _defaultBranch['radius'], 100);

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

                  // Kartu Profil Mengambang dengan Garis Kuning Keemasan (Sesuai Desain)
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
                              border: Border.all(color: Colors.grey.shade200, width: 1),
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
                                const Text(
                                  'Clock In',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E), // Hijau Clock In
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

              // ================= 2. STEPPER PROGRESS BAR (SESUAI DESAIN) =================
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
                                  color: Color(0xFFFF5722), // Oranye aktif
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 3,
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              // Langkah 2: Titik Abu-Abu (Belum)
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
                              // Langkah 3: Titik Abu-Abu (Belum)
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
                            children: const [
                              Text(
                                'Lokasi',
                                style: TextStyle(
                                  color: Color(0xFFFF5722), // Oranye
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Radius',
                                style: TextStyle(
                                  color: Color(0xFFFF5722), // Aktif
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Clock In',
                                style: TextStyle(
                                  color: Color(0xFF22C55E), // Hijau
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
                      onTap: _checkUserLocation,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981), // Emerald green
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

              // ================= 2.5 KANTOR CABANG SELECTOR & AUTO-DETECT =================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.business_rounded, color: Color(0xFF007AFF), size: 18),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Auto-Detect',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF059669),
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
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF1E293B), size: 20),
                                items: _branches.map((b) {
                                  final bName = b['branch_name']?.toString() ?? 'Cabang';
                                  final bCity = b['city']?.toString() ?? '';
                                  final label = bCity.isNotEmpty ? '$bName ($bCity)' : bName;
                                  return DropdownMenuItem<dynamic>(
                                    value: b['id'],
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E293B),
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

              const SizedBox(height: 12),

              // ================= 3. WIDGET PETA DENGAN RADIUS & PIN =================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
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
                            initialCenter: LatLng(targetLat, targetLon),
                            initialZoom: 16.5,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all,
                            ),
                          ),
                          children: [
                            // Tile Lapisan Peta OpenStreetMap
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.projectwg',
                            ),

                            // Lingkaran Hijau Radius Kehadiran (Sesuai Desain)
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: LatLng(targetLat, targetLon),
                                  color: const Color(0x4D4ADE80), // Hijau transparan
                                  borderColor: const Color(0xFF22C55E),
                                  borderStrokeWidth: 1.5,
                                  useRadiusInMeter: true,
                                  radius: allowedRadius.toDouble(),
                                ),
                              ],
                            ),

                            // Pin Marker Lokasi Biru Cyan/Teal (Sesuai Desain)
                            MarkerLayer(
                              markers: [
                                // Marker untuk semua cabang lain yang terdaftar
                                for (var b in _branches)
                                  if (b['id'] != _selectedBranch?['id'])
                                    Marker(
                                      point: LatLng(
                                        _parseDouble(b['latitude'], -7.3402015),
                                        _parseDouble(b['longitude'], 112.7202620),
                                      ),
                                      width: 32,
                                      height: 32,
                                      child: GestureDetector(
                                        onTap: () => _onBranchSelected(b),
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Color(0xFF94A3B8), // Abu-abu elegan cabang lain
                                          size: 28,
                                        ),
                                      ),
                                    ),

                                // Marker untuk Cabang yang Aktif Dipilih
                                Marker(
                                  point: LatLng(targetLat, targetLon),
                                  width: 44,
                                  height: 44,
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Color(0xFF06B6D4), // Cyan/Teal Pin persis di gambar
                                    size: 42,
                                  ),
                                ),
                                // Marker posisi pengguna saat ini (jika ada)
                                if (_currentUserPosition != null)
                                  Marker(
                                    point: LatLng(_currentUserPosition!.latitude, _currentUserPosition!.longitude),
                                    width: 18,
                                    height: 18,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF007AFF),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.2),
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
                        if (_isCheckingLocation)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 6,
                                  )
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF007AFF)),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Memindai GPS...',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
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

              // ================= 4. STATUS RADIUS (HIJAU PERSIS DESAIN) =================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isWithinRadius ? Icons.check_circle_outline : Icons.info_outline,
                      color: _isWithinRadius ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _isWithinRadius
                            ? 'Anda berada dalam radius $allowedRadius meter'
                            : (_isCheckingLocation
                                ? 'Mendeteksi posisi GPS Anda...'
                                : 'Anda berada di luar radius ($allowedRadius m). Silakan mendekat ke lokasi kantor.'),
                        style: TextStyle(
                          color: _isWithinRadius ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
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

              // ================= 5. TOMBOL LANJUT SELFIE (SETELAH RADIUS SESUAI) =================
              Center(
                child: SizedBox(
                  width: 220,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_isWithinRadius && !_isCheckingLocation)
                        ? _goToFaceCapture
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFFDC2626),
                                content: Text(
                                  _statusMessage.isNotEmpty
                                      ? _statusMessage
                                      : 'Anda berada di luar radius kantor ($allowedRadius m). Wajib berada di lokasi kantor untuk Clock In!',
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_isWithinRadius && !_isCheckingLocation)
                          ? const Color(0xFF007AFF) // Biru aktif jika di dalam radius
                          : const Color(0xFF94A3B8), // Abu-abu tegas jika di luar radius
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
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
}