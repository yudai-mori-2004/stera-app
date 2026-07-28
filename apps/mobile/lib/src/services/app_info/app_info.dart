import "dart:io";
import "package:stera/src/services/app_info/models/device_details.dart";
import "package:stera/src/services/kv_store/kv_store.dart";
import "package:device_info_plus/device_info_plus.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:uuid/uuid.dart";

class AppInfo {
  static PackageInfo? _packageInfo;
  static PackageInfo get packageInfo => _packageInfo!;

  static DeviceInfoPlugin? _deviceInfo;
  static DeviceInfoPlugin get deviceInfo => _deviceInfo!;

  static bool _isInitialized = false;

  static const _uuid = Uuid();

  static DeviceDetails _deviceDetails = DeviceDetails.empty();
  static DeviceDetails get deviceDetails => _deviceDetails;

  /// User-facing version for UI (e.g. profile footer). Maps `4.3.0-alpha` → `4.3.0 alpha`.
  static String get displayVersion {
    if (!_isInitialized) return "Unknown";
    return packageInfo.version.replaceFirst("-alpha", " alpha");
  }

  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
    _deviceInfo = DeviceInfoPlugin();
    _isInitialized = true;
    await getDeviceDetails();
  }

  static Future<DeviceDetails> getDeviceDetails() async {
    if (!_isInitialized) await init();

    final deviceDetailsCache = KvStore.get<String>(KvStoreKeys.deviceDetails);

    final appVersion = packageInfo.version;

    if (deviceDetailsCache != null) {
      final cached = DeviceDetails.fromJson(deviceDetailsCache);
      _deviceDetails = DeviceDetails(
        id: cached.id,
        label: cached.label,
        platform: cached.platform,
        osVersion: cached.osVersion,
        manufacturer: cached.manufacturer,
        model: cached.model,
        appVersion: appVersion,
      );
    } else {
      final deviceId = await _getDeviceId();
      final deviceLabel = await _getDeviceLabel();
      final osVersion = await _getOsVersion();
      final manufacturer = await _getManufacturer();
      final model = await _getModel();
      _deviceDetails = DeviceDetails(
        id: deviceId,
        label: deviceLabel,
        platform: Platform.operatingSystem,
        osVersion: osVersion,
        manufacturer: manufacturer,
        model: model,
        appVersion: appVersion,
      );
    }
    await KvStore.set(KvStoreKeys.deviceDetails, _deviceDetails.toJson());

    return _deviceDetails;
  }

  static Future<String> _getDeviceId() async {
    final id = _uuid.v4();
    return id;
  }

  static Future<String> _getDeviceLabel() async {
    if (!_isInitialized) await init();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer;
      final model = androidInfo.model;
      final capitalizedManufacturer = manufacturer.isNotEmpty
          ? manufacturer[0].toUpperCase() + manufacturer.substring(1)
          : manufacturer;
      return "$capitalizedManufacturer $model";
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      iosInfo.utsname.machine;
      return iosInfo.name;
    } else {
      return "Unknown Device";
    }
  }

  static Future<String> _getOsVersion() async {
    if (Platform.isAndroid) {
      return (await deviceInfo.androidInfo).version.release;
    } else if (Platform.isIOS) {
      return (await deviceInfo.iosInfo).systemVersion;
    } else {
      return "Unknown";
    }
  }

  static Future<String> _getManufacturer() async {
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer;
      return manufacturer.isNotEmpty
          ? manufacturer[0].toUpperCase() + manufacturer.substring(1)
          : manufacturer;
    } else if (Platform.isIOS) {
      return "Apple";
    } else {
      return "Unknown";
    }
  }

  static Future<String> _getModel() async {
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.utsname.machine;
    } else {
      return "Unknown";
    }
  }
}
