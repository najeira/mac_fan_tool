import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DashboardView { overview, details, system }

final dashboardViewProvider =
    NotifierProvider<DashboardViewController, DashboardView>(
      DashboardViewController.new,
    );

class DashboardViewController extends Notifier<DashboardView> {
  @override
  DashboardView build() {
    return DashboardView.overview;
  }

  void setView(DashboardView view) {
    state = view;
  }
}
