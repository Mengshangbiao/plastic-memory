import 'package:flutter/material.dart';

const paper = Color(0xFF07080A);
const surface = Color(0xFF101215);
const raisedSurface = Color(0xFF16191D);
const hairline = Color(0x12FFFFFF);
const ink = Color(0xFFE6E8EB);
const secondaryInk = Color(0xFF969CA4);
const quietInk = Color(0xFF5C636B);

const joy = Color(0xFFFFB86B);
const anger = Color(0xFFFF5C5C);
const sorrow = Color(0xFF5C8DFF);
const fear = Color(0xFFB08CFF);
const love = Color(0xFFFF7AC6);
const calm = Color(0xFF4FD1C5);
const thought = Color(0xFFA6E36B);
const longing = Color(0xFFE0C46C);
const accent = calm;
const emotionSpectrum = [
  joy,
  anger,
  sorrow,
  fear,
  love,
  calm,
  thought,
  longing,
];

// FNV-1a keeps project and speaker accents stable across application launches.
Color memoryColor(String identity) {
  var hash = 0x811c9dc5;
  for (final unit in identity.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return emotionSpectrum[hash % emotionSpectrum.length];
}

const memoryRadius = BorderRadius.all(Radius.circular(4));
const memoryMotion = Duration(milliseconds: 200);
const monoStyle = TextStyle(
  fontFamily: 'Consolas',
  fontFamilyFallback: ['Noto Sans SC', 'Microsoft YaHei'],
  fontSize: 11,
  letterSpacing: .88,
  color: secondaryInk,
);
