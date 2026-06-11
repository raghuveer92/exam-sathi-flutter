/// Google AdSense configuration for Flutter web.
///
/// Auto ads: enabled via [web/index.html] script (ca-pub-6864237109521868).
/// Google places ads automatically once the site is approved.
///
/// Optional right-rail manual unit — set at build time:
///   --dart-define=ADSENSE_SLOT=1234567890
class AdConfig {
  AdConfig._();

  static const String clientId = String.fromEnvironment(
    'ADSENSE_CLIENT',
    defaultValue: 'ca-pub-6864237109521868',
  );

  /// Display ad unit slot — only needed for the fixed right sidebar rail.
  static const String adSlot = String.fromEnvironment(
    'ADSENSE_SLOT',
    defaultValue: '',
  );

  static bool get hasAutoAds => clientId.isNotEmpty;

  static bool get hasManualRail => clientId.isNotEmpty && adSlot.isNotEmpty;
}
