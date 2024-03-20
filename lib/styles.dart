import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DarkColor {
  static const Color primary = Color(0xFF34D399);
  static const Color primaryLightPlus1 = Color(0xFFA7F3D0);
  static const Color primaryLightMax = Color(0xFFECFDF5);
  static const Color primaryDark = Color(0xFF079669);
  static const Color primaryBackground = Color(0xFF30444E);
  static const Color primaryBackgroundDark = Color(0xFF22343C);
  static const Color accentColor = Color(0xFFFFBC25);
  static const Color secondaryColor = Color(0xFF96A7AF);

  static TextStyle cardTitleBold = TextStyle(
    color: primaryLightMax,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontFamily: GoogleFonts.notoSans().fontFamily,
    height: 0,
  );
  static TextStyle cardTextLight = TextStyle(
    color: primary,
    fontSize: 12,
    fontFamily: GoogleFonts.inter().fontFamily,
    fontWeight: FontWeight.w400,
    height: 0,
  );
  static TextStyle defaultText = TextStyle(
    color: secondaryColor,
    fontSize: 12,
    fontFamily: GoogleFonts.inter().fontFamily,
    fontWeight: FontWeight.w400,
    height: 0,
  );
  static TextStyle defaultTitle = TextStyle(
    color: primaryLightMax,
    fontSize: 16,
    fontFamily: GoogleFonts.notoSans().fontFamily,
    fontWeight: FontWeight.w700,
    height: 0,
  );
  static TextStyle defaultMainText = TextStyle(
    color: primaryLightMax,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    fontFamily: GoogleFonts.comfortaa().fontFamily,
    height: 0,
  );
  static TextStyle mainTitle = TextStyle(
    color: primaryLightMax,
    fontSize: 44,
    fontFamily: GoogleFonts.comfortaa().fontFamily,
    fontWeight: FontWeight.w700,
    height: 0,
    letterSpacing: 4.40,
  );
  static TextStyle secondaryTitle = TextStyle(
    color: primaryLightMax,
    fontSize: 24,
    fontFamily: GoogleFonts.comfortaa().fontFamily,
    fontWeight: FontWeight.w700,
    height: 0,
    letterSpacing: 2.40,
  );
}
