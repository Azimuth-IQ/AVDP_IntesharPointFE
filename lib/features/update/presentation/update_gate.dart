import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:inteshar/features/update/application/update_controller.dart';
import 'package:inteshar/features/update/domain/app_release.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// Wraps the app: checks for updates once on first frame, shows a dismissible
/// sheet for optional updates, and replaces the UI with a blocking screen for
/// mandatory ones. Non-Android targets resolve to [UpToDate] immediately.
class UpdateGate extends ConsumerStatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(updateControllerProvider.notifier).check();
    });
  }

  bool _isMandatory(UpdateState s) => switch (s) {
    UpdateAvailableState v => v.mandatory,
    UpdateDownloading v => v.mandatory,
    UpdateFailed v => v.mandatory,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);
    if (_isMandatory(state)) {
      return _ForcedUpdateScreen(state: state);
    }
    // Optional update: render the prompt as an IN-TREE overlay above the whole app rather than
    // a Navigator route. A route (showModalBottomSheet) gets buried when the app navigates
    // (splash → shell) after the check resolves — leaving the sheet under the nav rail. As a
    // Stack child of the UpdateGate (which wraps `child` in MaterialApp.builder) it's always on top.
    final showOptional =
        state is UpdateAvailableState && !state.mandatory && !_dismissed;
    return Stack(
      children: [
        widget.child,
        if (showOptional)
          Positioned.fill(
            child: _OptionalUpdateOverlay(
              onDismiss: () {
                ref.read(updateControllerProvider.notifier).dismiss();
                if (mounted) setState(() => _dismissed = true);
              },
            ),
          ),
      ],
    );
  }
}

/// Full-screen scrim + bottom card holding the optional-update prompt, rendered in-tree so it
/// can never be buried by the app's own navigation.
class _OptionalUpdateOverlay extends StatelessWidget {
  final VoidCallback onDismiss;
  const _OptionalUpdateOverlay({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: const ColoredBox(color: Colors.black54),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              // Cap the card height so a long changelog can't push it past the
              // screen; the sheet content scrolls within (B-084).
              constraints: BoxConstraints(
                maxWidth: 480,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: _UpdateSheet(onDismiss: onDismiss),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Forced (blocking) screen ────────────────────────────────────────────────

class _ForcedUpdateScreen extends ConsumerWidget {
  final UpdateState state;
  const _ForcedUpdateScreen({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final release = _releaseOf(state);
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            // Scrollable so the "Update now" button is always reachable — on a
            // short screen or with a long changelog it was spilling off-screen
            // and the forced update couldn't be started (B-084).
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IntesharStar(size: 56, color: cs.onSurface),
                  const SizedBox(height: 24),
                  Text(
                    l.updateRequiredTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.updateRequiredBody,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (release != null) ...[
                    const SizedBox(height: 20),
                    _ReleaseSummary(release: release),
                  ],
                  const SizedBox(height: 24),
                  _ActionArea(state: state),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Optional update sheet ───────────────────────────────────────────────────

class _UpdateSheet extends ConsumerWidget {
  final VoidCallback onDismiss;
  const _UpdateSheet({required this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(updateControllerProvider);
    final release = _releaseOf(state);
    if (release == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.updateAvailableTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l.updateBody,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _ReleaseSummary(release: release),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (state is! UpdateDownloading)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDismiss,
                        child: Text(l.updateLater),
                      ),
                    ),
                  if (state is! UpdateDownloading) const SizedBox(width: 12),
                  Expanded(flex: 2, child: _ActionArea(state: state)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared pieces ───────────────────────────────────────────────────────────

class _ReleaseSummary extends StatelessWidget {
  final AppRelease release;
  const _ReleaseSummary({required this.release});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final changelog = (release.changelog ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l.updateVersion(
                  release.versionName.isNotEmpty
                      ? release.versionName
                      : '${release.versionCode}',
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (release.sizeLabel.isNotEmpty)
                Text(
                  release.sizeLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          if (changelog.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l.updateWhatsNew,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(changelog, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// The "Update now" button, the download progress bar, and the retry /
/// permission states — shared by the sheet and the forced screen.
class _ActionArea extends ConsumerWidget {
  final UpdateState state;
  const _ActionArea({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final notifier = ref.read(updateControllerProvider.notifier);

    if (state is UpdateDownloading) {
      final p = (state as UpdateDownloading).progress;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p > 0 ? p : null,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            p > 0
                ? '${l.updateDownloading} ${(p * 100).round()}%'
                : l.updateOpenInstaller,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    if (state is UpdateFailed && (state as UpdateFailed).permissionDenied) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.updatePermissionBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await openAppSettings();
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(l.updatePermissionOpenSettings),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: notifier.install,
              child: Text(l.updateRetry),
            ),
          ),
        ],
      );
    }

    final isFailed = state is UpdateFailed;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: notifier.install,
        icon: const Icon(Icons.download_outlined, size: 18),
        label: Text(isFailed ? l.updateRetry : l.updateNow),
      ),
    );
  }
}

AppRelease? _releaseOf(UpdateState s) => switch (s) {
  UpdateAvailableState v => v.release,
  UpdateDownloading v => v.release,
  UpdateFailed v => v.release,
  _ => null,
};
