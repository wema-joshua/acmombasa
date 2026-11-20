import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

/// Central logo area.
///
/// Tries to load [AppAssets.logo]. If the asset is missing it falls back to a
/// clearly marked placeholder, so replacing the logo is just: add the PNG at
/// that path and register it in pubspec.yaml. No code changes needed.
class LogoArea extends StatelessWidget {
  const LogoArea({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(size * 0.18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Image.asset(
        AppAssets.logo,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _LogoPlaceholder(),
      ),
    );
  }
}

class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_outlined, size: 44, color: AppColors.navy),
        SizedBox(height: 6),
        Text(
          'LOGO',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}
