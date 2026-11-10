import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Donut/Pie Chart Minimalis & Elegan untuk Statistik Kehadiran Bulanan Karyawan
class MonthlyAttendanceDonutChart extends StatelessWidget {
  final int sangatBaik;
  final int baik;
  final int cukup;
  final int kurang;
  final int totalHadir;
  final double size;

  const MonthlyAttendanceDonutChart({
    super.key,
    required this.sangatBaik,
    required this.baik,
    required this.cukup,
    required this.kurang,
    required this.totalHadir,
    this.size = 126,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutChartPainter(
              sangatBaik: sangatBaik,
              baik: baik,
              cukup: cukup,
              kurang: kurang,
              total: totalHadir,
            ),
          ),
          // Center Text: Angka Total Presensi
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$totalHadir',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const Text(
                'Presensi',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final int sangatBaik;
  final int baik;
  final int cukup;
  final int kurang;
  final int total;

  _DonutChartPainter({
    required this.sangatBaik,
    required this.baik,
    required this.cukup,
    required this.kurang,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.19;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Jika data kosong / belum ada presensi
    if (total == 0) {
      basePaint.color = const Color(0xFFE2E8F0);
      canvas.drawCircle(center, radius, basePaint);
      return;
    }

    final sum = sangatBaik + baik + cukup + kurang;
    if (sum == 0) {
      basePaint.color = const Color(0xFFE2E8F0);
      canvas.drawCircle(center, radius, basePaint);
      return;
    }

    // Segmen data (Sangat Baik, Baik, Cukup, Kurang)
    final items = [
      _ChartSegment(sangatBaik, const Color(0xFF00BFA5)), // Toska Sangat Baik
      _ChartSegment(baik, const Color(0xFF38BDF8)),       // Biru Muda Baik
      _ChartSegment(cukup, const Color(0xFFF59E0B)),      // Amber/Kuning Cukup
      _ChartSegment(kurang, const Color(0xFFEF4444)),     // Merah Kurang
    ];

    double startAngle = -math.pi / 2; // Mulai dari atas jam 12
    const minSweepAngle = 0.05; // Gap visual kecil

    for (final seg in items) {
      if (seg.value <= 0) continue;
      final sweepAngle = (seg.value / sum) * (2 * math.pi);
      
      basePaint.color = seg.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle - (items.where((i) => i.value > 0).length > 1 ? minSweepAngle : 0),
        false,
        basePaint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.sangatBaik != sangatBaik ||
        oldDelegate.baik != baik ||
        oldDelegate.cukup != cukup ||
        oldDelegate.kurang != kurang ||
        oldDelegate.total != total;
  }
}

class _ChartSegment {
  final int value;
  final Color color;
  _ChartSegment(this.value, this.color);
}

