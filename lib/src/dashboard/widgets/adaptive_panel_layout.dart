import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mac_fan_tool/src/dashboard/dashboard_state.dart';

class AdaptivePanelLayout extends ConsumerWidget {
  const AdaptivePanelLayout({
    super.key,
    required this.children,
    this.spacing = 20,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    final isWide = ref.watch(isWideProvider);
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in children.asMap().entries) ...[
            Expanded(child: entry.value),
            if (entry.key != children.length - 1) SizedBox(width: spacing),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in children.asMap().entries) ...[
          entry.value,
          if (entry.key != children.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}
