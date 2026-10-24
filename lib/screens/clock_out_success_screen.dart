import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/mysql_helper.dart';
import 'home_screen.dart';

class ClockOutSuccessScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String locationName;
  final String clockInTime;
  final String clockOutTime;

  const ClockOutSuccessScreen({
    super.key,
    required this.userData,
    required this.locationName,
    required this.clockInTime,
    required this.clockOutTime,
  });

  @override
  State<ClockOutSuccessScreen> createState() => _ClockOutSuccessScreenState();
}

class _ClockOutSuccessScreenState extends State<ClockOutSuccessScreen> {
  bool _isSubmitting = false;

  void _navigateToHome(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => HomeScreen(userData: widget.userData)),
      (route) => false,
    );
  }

  Future<void> _handleClockOutAction() async {
    setState(() => _isSubmitting = true);
    try {
      final username = widget.userData['username'] ?? '';
      if (username.isNotEmpty) {
        await MySQLHelper.saveAttendance(username, 'clock_out');
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Clock Out berhasil diselesaikan!'),
        backgroundColor: Color(0xFF00A800),
      ),
    );
    _navigateToHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final String displayClockIn = widget.clockInTime.isNotEmpty && widget.clockInTime != '--:--'
        ? widget.clockInTime
        : '08:50';

    final String displayLocation = widget.locationName.isNotEmpty
        ? widget.locationName
        : 'Kantor Pusat';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _navigateToHome(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // ==========================================
            // 1. BACKGROUND WATERMARK TSA (SESUAI DESAIN)
            // ==========================================
            Positioned.fill(
              child: Image.asset(
                'assets/Minimalist TSA Login Background.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  );
                },
              ),
            ),

            // ==========================================
            // 2. KONTEN UTAMA (TERPUSAT PERSIS GAMBAR)
            // ==========================================
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),

                      // A. IKON JAM BIRU DENGAN PANAH MELINGKAR (SESUAI GAMBAR)
                      const ClockOutRefreshIcon(size: 78),

                      const SizedBox(height: 20),

                      // B. TEKS "Klik Tombol untuk Clock Out"
                      const Text(
                        'Klik Tombol untuk\nClock Out',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2937),
                          height: 1.35,
                        ),
                      ),

                      const SizedBox(height: 22),

                      // C. TOMBOL BIRU PILL "Back to Home"
                      SizedBox(
                        width: 210,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => _navigateToHome(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF), // Biru persis referensi
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: const Text(
                            'Back to Home',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // D. KARTU INFORMASI PUTIH (Clock In & Lokasi)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Baris 1: Jam Clock In
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  color: Color(0xFF6B7280),
                                  size: 26,
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Clock In',
                                      style: TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      displayClockIn,
                                      style: const TextStyle(
                                        color: Color(0xFF1E293B),
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const Divider(
                              height: 28,
                              color: Color(0xFFF1F5F9),
                              thickness: 1.2,
                            ),

                            // Baris 2: Lokasi Kantor
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  color: Color(0xFF6B7280),
                                  size: 26,
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Lokasi',
                                      style: TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      displayLocation,
                                      style: const TextStyle(
                                        color: Color(0xFF1E293B),
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// WIDGET CUSTOM IKON CLOCK OUT BIRU DENGAN PANAH & JARUM (PERSIS GAMBAR)
/// =========================================================================
class ClockOutRefreshIcon extends StatelessWidget {
  final double size;
  const ClockOutRefreshIcon({super.key, this.size = 76});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ClockOutIconPainter(),
    );
  }
}

class _ClockOutIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.115;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final bluePaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.fill;

    // 1. Arc utama: melingkar dari jam 10:00 searah jarum jam ke jam 06:00
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -2.35, 4.15, false, bluePaint);

    // 2. Titik putus-putus di sisi kiri bawah (jam 07:00 s/d jam 09:30)
    final dotRadius = strokeWidth * 0.44;
    final dotAngles = [2.25, 2.68, 3.12];
    for (final angle in dotAngles) {
      final dx = center.dx + radius * math.cos(angle);
      final dy = center.dy + radius * math.sin(angle);
      canvas.drawCircle(Offset(dx, dy), dotRadius, fillPaint);
    }

    // 3. Kepala panah segitiga di ujung atas-kiri (jam 10:00)
    final arrowTip = Offset(
      center.dx + radius * math.cos(-2.35),
      center.dy + radius * math.sin(-2.35),
    );
    final angle = -2.35 - math.pi / 2;
    final arrowSize = strokeWidth * 1.55;
    final arrowPath = Path()
      ..moveTo(
        arrowTip.dx + arrowSize * math.cos(angle),
        arrowTip.dy + arrowSize * math.sin(angle),
      )
      ..lineTo(
        arrowTip.dx + arrowSize * 0.75 * math.cos(angle + 2.35),
        arrowTip.dy + arrowSize * 0.75 * math.sin(angle + 2.35),
      )
      ..lineTo(
        arrowTip.dx + arrowSize * 0.75 * math.cos(angle - 2.35),
        arrowTip.dy + arrowSize * 0.75 * math.sin(angle - 2.35),
      )
      ..close();
    canvas.drawPath(arrowPath, fillPaint);

    // 4. Jarum jam bentuk "L" di tengah (jam 12 dan jam 3)
    final handsPaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.95
      ..strokeCap = StrokeCap.square;

    final handPath = Path()
      ..moveTo(center.dx, center.dy - radius * 0.50)
      ..lineTo(center.dx, center.dy)
      ..lineTo(center.dx + radius * 0.50, center.dy);
    canvas.drawPath(handPath, handsPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
