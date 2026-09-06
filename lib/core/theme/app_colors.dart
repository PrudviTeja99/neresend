import 'package:flutter/material.dart';

/// Semantic design colors and traffic-light readiness palette for DropFlow
class AppColors {
  AppColors._();

  // Primary Brand Palettes (Dark Futuristic Theme)
  static const Color background = Color(0xFF0F172A); // Slate 900
  static const Color surface = Color(0xFF1E293B);    // Slate 800
  static const Color surfaceHighlight = Color(0xFF334155); // Slate 700
  static const Color surfaceElevated = Color(0xFF1E293B);

  static const Color primary = Color(0xFF6366F1);    // Indigo 500
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color accent = Color(0xFF14B8A6);     // Teal 500

  // Text colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Traffic-Light Readiness States
  static const Color readyGreen = Color(0xFF10B981); // Emerald 500 (🟢 Ready)
  static const Color readyGreenGlow = Color(0x3310B981);
  
  static const Color scanningYellow = Color(0xFFF59E0B); // Amber 500 (🟡 Scanning)
  static const Color scanningYellowGlow = Color(0x33F59E0B);
  
  static const Color offlineRed = Color(0xFFEF4444); // Rose 500 (🔴 Offline)
  static const Color offlineRedGlow = Color(0x33EF4444);

  // Transfer Speeds & Badges
  static const Color speedCyan = Color(0xFF06B6D4);
  static const Color trustedBadge = Color(0xFF8B5CF6); // Purple 500
}

