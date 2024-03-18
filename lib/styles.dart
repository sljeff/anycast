import 'package:flutter/material.dart';

class DarkColor {
  static const Color primary = Color(0xFF34D399);
  static const Color primaryLightPlus1 = Color(0xFFA7F3D0);
  static const Color primaryLightMax = Color(0xFFECFDF5);
  static const Color primaryDark = Color(0xFF079669);
  static const Color primaryBackground = Color(0xFF30444E);
  static const Color primaryBackgroundDark = Color(0xFF22343C);
  static const Color accentColor = Color(0xFFFFBC25);
  static const Color secondaryColor = Color(0xFF96A7AF);

  static const TextStyle cardTitleBold = TextStyle(
    color: primaryLightMax,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontFamily: 'Noto Sans',
    height: 0,
  );
  static const TextStyle cardTextLight = TextStyle(
    color: primary,
    fontSize: 12,
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
    height: 0,
  );
  static const TextStyle defaultText = TextStyle(
    color: secondaryColor,
    fontSize: 12,
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
    height: 0,
  );
  static const TextStyle defaultTitle = TextStyle(
    color: primaryLightMax,
    fontSize: 16,
    fontFamily: "Noto Sans",
    fontWeight: FontWeight.w700,
    height: 0,
  );
  static const TextStyle defaultMainText = TextStyle(
    color: primaryLightMax,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    fontFamily: 'Comfortaa',
    height: 0,
  );
  static const TextStyle mainTitle = TextStyle(
    color: primaryLightMax,
    fontSize: 44,
    fontFamily: 'Comfortaa',
    fontWeight: FontWeight.w700,
    height: 0,
    letterSpacing: 4.40,
  );
  static const TextStyle secondaryTitle = TextStyle(
    color: primaryLightMax,
    fontSize: 24,
    fontFamily: 'Comfortaa',
    fontWeight: FontWeight.w700,
    height: 0,
    letterSpacing: 2.40,
  );
}
