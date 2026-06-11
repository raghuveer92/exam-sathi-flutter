import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_adsense/flutter_adsense.dart';

import '../../../core/ads/ad_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive_helper.dart';

/// Right-side AdSense rail for wide desktop web layouts.
class WebAdRail extends StatelessWidget {
  const WebAdRail({super.key});

  static const double _railWidth = 300;
  static const double _minViewportWidth = 1280;

  static bool shouldShow(BuildContext context) {
    if (!kIsWeb || !AdConfig.hasManualRail) return false;
    if (!ResponsiveHelper.isDesktop(context)) return false;
    return MediaQuery.sizeOf(context).width >= _minViewportWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _railWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.divider)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Advertisement',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textHint,
                    letterSpacing: 0.4,
                  ),
            ),
            const SizedBox(height: 16),
            AdsenseWidget(
              adClient: AdConfig.clientId,
              adSlot: AdConfig.adSlot,
              adFormat: 'vertical',
              width: 280,
              height: 600,
              fullWidthResponsive: false,
            ),
          ],
        ),
      ),
    );
  }
}
