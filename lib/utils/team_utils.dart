import 'package:flutter/material.dart';

/// Returns the primary brand color for use in charts, text, etc.
/// Teams with visually similar hues use their secondary brand color
/// (e.g., KT uses black instead of red to differentiate from T1).
Color teamColor(String code) {
  switch (code.toUpperCase()) {
    case 'T1':  return const Color(0xFFB91C1C); // T1 Deep Crimson
    case 'GEN': return const Color(0xFFB8962E); // Gen.G Antique Gold
    case 'KT':  return const Color(0xFF94A3B8); // KT Steel Silver (avoids red clash)
    case 'HLE': return const Color(0xFFFF6600); // Hanwha Vivid Orange
    case 'BFX': return const Color(0xFFC8E635); // BNK Yellow-Lime
    case 'NS':  return const Color(0xFFEC4899); // Nongshim Magenta
    case 'KRX': return const Color(0xFF9333EA); // Kwangdong Purple
    case 'BRO': return const Color(0xFF166534); // Brion Dark Green
    case 'DK':  return const Color(0xFF1E3A8A); // Dplus KIA Navy
    case 'DNS': return const Color(0xFF3B82F6); // DN Blue
    default:    return const Color(0xFF64748B);
  }
}

/// Returns a background color for logo containers.
Color teamLogoBgColor(String code) => const Color(0xFF1A2035);
