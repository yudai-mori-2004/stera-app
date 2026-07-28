import "dart:async";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "package:rxdart/rxdart.dart";

/// Singleton service that monitors network connectivity using connectivity_plus.
class ConnectivityService {
  ConnectivityService._internal();

  static final ConnectivityService _instance = ConnectivityService._internal();
  static ConnectivityService get instance => _instance;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final _connectivitySubject = BehaviorSubject<bool>.seeded(true);
  Stream<bool> get connectivityStream => _connectivitySubject.stream.distinct();
  bool get isOnline => _connectivitySubject.value;

  void startMonitoring() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    checkNow();
  }

  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasConnection = !results.contains(ConnectivityResult.none);
    _updateStatus(hasConnection);
  }

  void _updateStatus(bool isOnline) {
    if (_connectivitySubject.value != isOnline) {
      debugPrint("🌐 ConnectivityService: ${isOnline ? 'ONLINE' : 'OFFLINE'}");
      _connectivitySubject.add(isOnline);
    }
  }

  Future<bool> checkNow() async {
    final results = await _connectivity.checkConnectivity();
    final hasConnection = !results.contains(ConnectivityResult.none);
    _updateStatus(hasConnection);
    return hasConnection;
  }

  /// Wait until connectivity is restored
  Future<void> waitForConnectivity() async {
    if (isOnline) return;
    await connectivityStream.firstWhere((online) => online);
  }

  void dispose() {
    stopMonitoring();
    _connectivitySubject.close();
  }
}
