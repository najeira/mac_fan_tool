import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DashboardView { overview, details, system }

final viewProvider = NotifierProvider<ViewController, DashboardView>(
  ViewController.new,
);

class ViewController extends Notifier<DashboardView> {
  @override
  DashboardView build() {
    return DashboardView.overview;
  }

  void setView(DashboardView view) {
    state = view;
  }
}
