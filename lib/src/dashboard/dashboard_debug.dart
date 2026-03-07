import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_colors.dart';
import 'package:mac_fan_tool/src/dashboard/dashboard_ref.dart';

class DebugFlags {
  const DebugFlags({
    this.showBootstrapping = false,
    this.showRefreshing = false,
    this.showError = false,
    this.showSuccess = false,
    this.showHardwareNote = false,
  });

  final bool showBootstrapping;
  final bool showRefreshing;
  final bool showError;
  final bool showSuccess;
  final bool showHardwareNote;

  DebugFlags copyWith({
    bool? showBootstrapping,
    bool? showRefreshing,
    bool? showError,
    bool? showSuccess,
    bool? showHardwareNote,
  }) {
    return DebugFlags(
      showBootstrapping: showBootstrapping ?? this.showBootstrapping,
      showRefreshing: showRefreshing ?? this.showRefreshing,
      showError: showError ?? this.showError,
      showSuccess: showSuccess ?? this.showSuccess,
      showHardwareNote: showHardwareNote ?? this.showHardwareNote,
    );
  }

  bool get isEmpty {
    return !showBootstrapping &&
        !showRefreshing &&
        !showError &&
        !showSuccess &&
        !showHardwareNote;
  }
}

final debugFlagsProvider = NotifierProvider<DebugFlagsController, DebugFlags>(
      DebugFlagsController.new,
    );

class DebugFlagsController extends Notifier<DebugFlags> {
  @override
  DebugFlags build() {
    return const DebugFlags();
  }

  void toggleBootstrapping() {
    state = state.copyWith(showBootstrapping: !state.showBootstrapping);
  }

  void toggleRefreshing() {
    state = state.copyWith(showRefreshing: !state.showRefreshing);
  }

  void toggleError() {
    state = state.copyWith(showError: !state.showError);
  }

  void toggleSuccess() {
    state = state.copyWith(showSuccess: !state.showSuccess);
  }

  void toggleHardwareNote() {
    state = state.copyWith(showHardwareNote: !state.showHardwareNote);
  }

  void clear() {
    state = const DebugFlags();
  }
}

class DebugPanel extends ConsumerWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(debugFlagsProvider);

    if (!kDebugMode) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DashboardColors.softSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DashboardColors.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Debug Flags',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: flags.isEmpty ? null : ref.debugFlagsActions.clear,
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilterChip(
                label: const Text('Bootstrapping'),
                selected: flags.showBootstrapping,
                onSelected: (_) => ref.debugFlagsActions.toggleBootstrapping(),
              ),
              FilterChip(
                label: const Text('Refreshing'),
                selected: flags.showRefreshing,
                onSelected: (_) => ref.debugFlagsActions.toggleRefreshing(),
              ),
              FilterChip(
                label: const Text('Error Banner'),
                selected: flags.showError,
                onSelected: (_) => ref.debugFlagsActions.toggleError(),
              ),
              FilterChip(
                label: const Text('Success Banner'),
                selected: flags.showSuccess,
                onSelected: (_) => ref.debugFlagsActions.toggleSuccess(),
              ),
              FilterChip(
                label: const Text('Hardware Note'),
                selected: flags.showHardwareNote,
                onSelected: (_) => ref.debugFlagsActions.toggleHardwareNote(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
