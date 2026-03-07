import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardDebugOverrides {
  const DashboardDebugOverrides({
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

  DashboardDebugOverrides copyWith({
    bool? showBootstrapping,
    bool? showRefreshing,
    bool? showError,
    bool? showSuccess,
    bool? showHardwareNote,
  }) {
    return DashboardDebugOverrides(
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

final dashboardDebugOverridesProvider =
    NotifierProvider<
      DashboardDebugOverridesController,
      DashboardDebugOverrides
    >(DashboardDebugOverridesController.new);

class DashboardDebugOverridesController
    extends Notifier<DashboardDebugOverrides> {
  @override
  DashboardDebugOverrides build() {
    return const DashboardDebugOverrides();
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
    state = const DashboardDebugOverrides();
  }
}

class DashboardDebugPanel extends ConsumerWidget {
  const DashboardDebugPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides = ref.watch(dashboardDebugOverridesProvider);
    final actions = ref.read(dashboardDebugOverridesProvider.notifier);

    if (!kDebugMode) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7DDD1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Debug Overrides',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: overrides.isEmpty ? null : actions.clear,
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
                selected: overrides.showBootstrapping,
                onSelected: (_) => actions.toggleBootstrapping(),
              ),
              FilterChip(
                label: const Text('Refreshing'),
                selected: overrides.showRefreshing,
                onSelected: (_) => actions.toggleRefreshing(),
              ),
              FilterChip(
                label: const Text('Error Banner'),
                selected: overrides.showError,
                onSelected: (_) => actions.toggleError(),
              ),
              FilterChip(
                label: const Text('Success Banner'),
                selected: overrides.showSuccess,
                onSelected: (_) => actions.toggleSuccess(),
              ),
              FilterChip(
                label: const Text('Hardware Note'),
                selected: overrides.showHardwareNote,
                onSelected: (_) => actions.toggleHardwareNote(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
