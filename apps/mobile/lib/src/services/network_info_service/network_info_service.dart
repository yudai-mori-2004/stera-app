import "package:connectivity_plus/connectivity_plus.dart";
import "package:network_info_plus/network_info_plus.dart";

class NetworkInfoService {
  NetworkInfoService._();
  static final NetworkInfoService instance = NetworkInfoService._();

  final NetworkInfo _info = NetworkInfo();
  final Connectivity _connectivity = Connectivity();

  Future<bool> isOnWifi() async {
    try {
      final ip = await _info.getWifiIP();
      if (ip != null && ip.isNotEmpty) return true;
    } catch (_) {}

    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }
}
