import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const kBurgundy = Color(0xFF4A0E1A);
const kBurgundyLight = Color(0xFF6B1A2A);
const kGold = Color(0xFFD4AF37);
const kGoldLight = Color(0xFFF0D060);
const kGoldDark = Color(0xFF9A7B1A);
const kCardWhite = Color(0xFFFFFDF5);
const kCardRed = Color(0xFFB71C1C);
const kCardBlack = Color(0xFF1A1A1A);
const kTableGreen = Color(0xFF1A3A2A);
const kTableGreenMid = Color(0xFF254D38);
const kSlotFrame = Color(0xFF2E5C44);
const kSlotFrameBorder = Color(0xFF5AAE80);
const kSlotDumpBorder = Color(0xFF2E4A3A);
const kBlockedBg = Color(0xFF3D1A1A);
const kBlockedBorder = Color(0xFFB06060);
const kDragTarget = Color(0xFF3D3010);
const kDragTargetBorder = Color(0xFFE8C84A);

const kRoyalGoldBg = Color(0xFF3A2800);
const kRoyalGoldBorder = Color(0xFFFFD700);
const kRoyalGlowColor = Color(0xFFFFD700);

const kNumberSilverBorder = Color(0xFFE0E0E0);
const kSelectionHighlight = Color(0xFF1DE9B6);

// ── Difficulty accents (canonical: easy=green, medium=blue, classic=gold,
//    expert=red — matches the difficulty picker) ──────────────────────────────
const kDiffEasy       = Color(0xFF4CAF50);
const kDiffEasyDark   = Color(0xFF2E7D32);
const kDiffMedium     = Color(0xFF64B5F6);
const kDiffMediumDark = Color(0xFF1565C0);
const kDiffExpert     = Color(0xFFFF5252);
// classic reuses kGold / kGoldDark; expert dark reuses kCardRed.

// ── Promoted call-site colors ────────────────────────────────────────────────
const kBurgundyDeep      = Color(0xFF3A0D15); // darkest burgundy — deep dialog surfaces & text on light backgrounds
const kGoldTintBg        = Color(0x448B6914); // translucent gold button fill
const kStreakBadgeStart  = Color(0xFFFFD700);
const kStreakBadgeEnd    = Color(0xFFB8860B);
const kStreakBadgeGlow   = Color(0x88FFD700);
const kStreakActiveGreen = Color(0xFF2A5C1A);
const kRoyalCellGradEdge = Color(0xFF4A3200); // royal cell glow gradient edges
const kRoyalCellGradMid  = Color(0xFF2A1800); // royal cell glow gradient center
const kDanger            = Color(0xFFC62828); // destructive actions (leave duel)
const kRulesPageBurgundy = Color(0xFF4A1A2A);
const kRulesPageNavy     = Color(0xFF1A2A4A);
const kRulesPageBrown    = Color(0xFF3A2A1A);
// rules "clear phase" page reuses kTableGreen.

/// Brand confetti palette (win celebration) — gold/burgundy identity.
const List<Color> kConfettiColors = [kGold, kGoldLight, kCardWhite, kCardRed];

// ── Spacing scale (codifies the measured dominant gaps: 4/8/12/16/24/32) ────
const double kSpaceXs  = 4.0;
const double kSpaceSm  = 8.0;
const double kSpaceMd  = 12.0;
const double kSpaceLg  = 16.0;
const double kSpaceXl  = 24.0;
const double kSpaceXxl = 32.0;

// ── Radius scale (measured dominant radii: 8/12/16/20) ──────────────────────
const double kRadiusSm = 8.0;
const double kRadiusMd = 12.0;
const double kRadiusLg = 16.0;
const double kRadiusXl = 20.0;
const BorderRadius kBrSm = BorderRadius.all(Radius.circular(kRadiusSm));
const BorderRadius kBrMd = BorderRadius.all(Radius.circular(kRadiusMd));
const BorderRadius kBrLg = BorderRadius.all(Radius.circular(kRadiusLg));
const BorderRadius kBrXl = BorderRadius.all(Radius.circular(kRadiusXl));

// ── Motion (measured clusters: ~150 / 200 / 250-280 / 400-450 / 600) ────────
const Duration kDurFast      = Duration(milliseconds: 150);
const Duration kDurShort     = Duration(milliseconds: 200);
const Duration kDurMed       = Duration(milliseconds: 250);
const Duration kDurSlow      = Duration(milliseconds: 400);
const Duration kDurXSlow     = Duration(milliseconds: 600);
const Duration kDurRoute     = Duration(milliseconds: 260);
const Duration kDurRouteBack = Duration(milliseconds: 200);
const Duration kDurSnack     = Duration(seconds: 3);
const Curve kCurveStandard   = Curves.easeInOut;
const Curve kCurveEmphasized = Curves.easeOutCubic;

// ── Shadows ──────────────────────────────────────────────────────────────────
const BoxShadow kShadowGoldGlow = BoxShadow(
  color: Color(0x40D4AF37), // kGold at 25%
  blurRadius: 36,
  spreadRadius: 2,
);
const BoxShadow kShadowText = BoxShadow(
  color: Color(0xCC000000),
  blurRadius: 8,
);

// ── Text styles (adopt only where an inline style matches exactly) ──────────
const TextStyle kTsHeading = TextStyle(
  color: kGold,
  fontSize: 20,
  fontWeight: FontWeight.w800,
  letterSpacing: 1,
);
const TextStyle kTsLabelCaps = TextStyle(
  color: kGoldLight,
  fontSize: 12,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.0,
);
const TextStyle kTsBody = TextStyle(
  color: kGoldLight,
  fontSize: 14,
  height: 1.5,
);
const TextStyle kTsButton = TextStyle(
  fontWeight: FontWeight.w700,
  letterSpacing: 0.8,
);

// ── Accessibility ────────────────────────────────────────────────────────────
const double kMinTouchTarget = 44.0;

// ── Assets & deck geometry ───────────────────────────────────────────────────
const kCardBackAsset = 'assets/images/card_back_red.png';

const kDeckStackW = 78.0;
const kDeckStackH = 108.0;
const kDeckLayerOffsetX = 1.0;
const kDeckLayerOffsetY = 2.0;
