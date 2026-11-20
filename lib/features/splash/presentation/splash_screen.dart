import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/app_initializer.dart';
import '../application/splash_controller.dart';
import 'widgets/logo_area.dart';
import 'widgets/splash_background.dart';

typedef DestinationBuilder = Widget Function(
  BuildContext context,
  StartupDestination destination,
);

/// Shown at launch while the app initialises, then replaces itself with the
/// screen returned by [destinationBuilder].
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, required this.destinationBuilder});

  final DestinationBuilder destinationBuilder;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _minimumSplashDuration = Duration(seconds: 8);

  late final SplashController _controller;
  late final Stopwatch _stopwatch;
  Timer? _navigationTimer;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _controller = SplashController(initializer: AppInitializer(ref))
      ..addListener(_onChanged);
    _controller.start();
  }

  void _onChanged() {
    if (_controller.status != SplashStatus.ready ||
        !mounted ||
        _hasNavigated ||
        _navigationTimer != null) {
      return;
    }

    final remaining = _minimumSplashDuration - _stopwatch.elapsed;
    if (remaining > Duration.zero) {
      _navigationTimer = Timer(remaining, _navigateToDestination);
    } else {
      _navigateToDestination();
    }
  }

  void _navigateToDestination() {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    final destination = _controller.destination!;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, _) =>
            widget.destinationBuilder(context, destination),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SplashBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortest =
                math.min(constraints.maxWidth, constraints.maxHeight);
            final logoSize = (shortest * 0.22).clamp(110.0, 200.0);
            final titleSize = (shortest * 0.045).clamp(22.0, 34.0);

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LogoArea(size: logoSize),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          AppStrings.appName,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.splashTitle
                              .copyWith(fontSize: titleSize),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          AppStrings.tagline,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.splashSubtitle,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        if (_controller.status == SplashStatus.failed)
                          _ErrorPanel(
                            error: _controller.error,
                            onRetry: _controller.start,
                          )
                        else
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: AppColors.white, size: 28),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          AppStrings.initFailedTitle,
          textAlign: TextAlign.center,
          style: AppTextStyles.splashError,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$error',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.splashSubtitle.copyWith(fontSize: 12),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: onRetry,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.americanRed,
            foregroundColor: AppColors.white,
          ),
          child: const Text(AppStrings.retry),
        ),
      ],
    );
  }
}
