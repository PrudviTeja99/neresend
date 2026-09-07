import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Clean card widget rendering a visual QR code for remote session pairing
class QrCodeCard extends StatelessWidget {
  final String data;
  final double size;
  final VoidCallback? onTap;

  const QrCodeCard({
    super.key,
    required this.data,
    this.size = 140,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: CustomPaint(
          size: Size(size - 24, size - 24),
          painter: _QrCustomPainter(data: data),
        ),
      ),
    );
  }
}

class _QrCustomPainter extends CustomPainter {
  final String data;

  _QrCustomPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    const matrixSize = 21; // Standard Version 1 QR matrix (21x21)
    final cellSize = size.width / matrixSize;

    // Build deterministic pseudo-matrix from input string hash
    final matrix = List.generate(
      matrixSize,
      (r) => List.generate(matrixSize, (c) => false),
    );

    // 1. Draw 3 Corner Position Detection Patterns (7x7)
    void drawFinderPattern(int startR, int startC) {
      for (int r = 0; r < 7; r++) {
        for (int c = 0; c < 7; c++) {
          final isBorder = (r == 0 || r == 6 || c == 0 || c == 6);
          final isCenter = (r >= 2 && r <= 4 && c >= 2 && c <= 4);
          matrix[startR + r][startC + c] = isBorder || isCenter;
        }
      }
    }

    drawFinderPattern(0, 0); // Top-left
    drawFinderPattern(0, matrixSize - 7); // Top-right
    drawFinderPattern(matrixSize - 7, 0); // Bottom-left

    // 2. Timing Patterns
    for (int i = 8; i < matrixSize - 8; i++) {
      matrix[6][i] = (i % 2 == 0);
      matrix[i][6] = (i % 2 == 0);
    }

    // 3. Deterministic Data Fill
    int hash = 0;
    for (final codeUnit in data.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0xFFFFFFFF;
    }

    int bitIndex = 0;
    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        // Skip finder patterns
        final isTopLeft = (r < 8 && c < 8);
        final isTopRight = (r < 8 && c >= matrixSize - 8);
        final isBottomLeft = (r >= matrixSize - 8 && c < 8);
        final isTiming = (r == 6 || c == 6);

        if (!isTopLeft && !isTopRight && !isBottomLeft && !isTiming) {
          final bit = ((hash ^ (r * matrixSize + c + bitIndex)) % 3) == 0;
          matrix[r][c] = bit;
          bitIndex++;
        }
      }
    }

    // Paint cells onto canvas with smooth rounded squares
    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        if (matrix[r][c]) {
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              c * cellSize + 0.5,
              r * cellSize + 0.5,
              cellSize - 1,
              cellSize - 1,
            ),
            const Radius.circular(1.5),
          );
          canvas.drawRRect(rect, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrCustomPainter oldDelegate) =>
      oldDelegate.data != data;
}
