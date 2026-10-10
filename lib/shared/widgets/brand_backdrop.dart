import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/utils/image_decode.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';

/// Paints the signed-in account's white-label **background image** (its nearest
/// Main-Agent brand) subtly behind [child], so an agent's identity carries into
/// the screens beneath it — not just the nav (B-049). No-op when no background is
/// set, and always kept low-opacity so foreground content stays readable.
class BrandBackdrop extends ConsumerWidget {
  final Widget child;

  /// How strongly the background image shows through (0–1). Kept low by default
  /// so cards/text on top remain legible on any image.
  final double opacity;

  const BrandBackdrop({super.key, required this.child, this.opacity = 0.10});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final url = auth is AuthAuthenticated ? auth.brand.agentBackgroundUrl : '';
    if (url.trim().isEmpty) return child;
    // Perf (POS lag, 2026-10): this sits behind EVERY POS frame, full screen.
    // - It was wrapped in `Opacity`, which renders the subtree into an offscreen
    //   layer and composites it back — a full-screen saveLayer on every frame the
    //   page repaints. `Image.opacity` applies the same alpha inside the draw call.
    // - It decoded the uploaded original (often a phone photo); at 10% opacity the
    //   screen width is far more resolution than anyone can see.
    // - RepaintBoundary keeps scrolling the grid on top from repainting it.
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: Image.network(
              url,
              fit: BoxFit.cover,
              opacity: AlwaysStoppedAnimation(opacity),
              cacheWidth: decodePx(context, MediaQuery.sizeOf(context).width),
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
