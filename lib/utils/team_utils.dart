import 'package:flutter/material.dart';

/// Returns the primary brand color for use in charts, text, etc.
/// Teams with visually similar hues use their secondary brand color
/// (e.g., KT uses black instead of red to differentiate from T1).
Color teamColor(String code) {
  switch (code.toUpperCase()) {
    case 'T1':  return const Color(0xFFC9082A); // T1 Crimson
    case 'GEN': return const Color(0xFFC49F3F); // Gen.G Gold
    case 'KT':  return const Color(0xFF1A1A1A); // KT Black (secondary, avoids clash with T1/NS)
    case 'HLE': return const Color(0xFFFF6600); // Hanwha Orange
    case 'BFX': return const Color(0xFFCA8A04); // BNK Yellow
    case 'NS':  return const Color(0xFFE8291C); // Nongshim Red
    case 'KRX': return const Color(0xFF9333EA); // Kiwoom Purple
    case 'DRX': return const Color(0xFF9333EA); // DRX Purple
    case 'BRO': return const Color(0xFF166534); // Brion Dark Green
    case 'DK':  return const Color(0xFF1E3A8A); // Dplus KIA Navy
    case 'DNS': return const Color(0xFF2563EB); // Blue
    case 'FOX': return const Color(0xFF16A34A); // Green
    default:    return const Color(0xFF64748B);
  }
}

/// Returns a background color for logo containers that ensures the logo
/// is visible. Only DK and KRX have white-on-dark logos that need a
/// darker neutral bg; everything else uses the standard light bg.
Color teamLogoBgColor(String code) {
  switch (code.toUpperCase()) {
    case 'DK':
    case 'KRX': return const Color(0xFF334155); // slate-700, neutral dark for white logos
    default:    return const Color(0xFFEFF3F8); // standard light blue-gray
  }
}
