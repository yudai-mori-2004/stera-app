import "dart:convert";

class DeviceDetails {
  final String id;
  final String label;
  final String platform;
  final String osVersion;
  final String manufacturer;
  final String model;
  final String appVersion;

  DeviceDetails({
    required this.id,
    required this.label,
    required this.platform,
    required this.osVersion,
    required this.manufacturer,
    required this.model,
    required this.appVersion,
  });

  Map<String, String> toMap() {
    return {
      "device_id": id,
      "device_label": label,
      "platform": platform,
      "os_version": osVersion,
      "manufacturer": manufacturer,
      "model": model,
      "app_version": appVersion,
    };
  }

  factory DeviceDetails.fromMap(Map<String, String> map) {
    return DeviceDetails(
      id: map["device_id"] ?? "Unknown",
      label: map["device_label"] ?? "Unknown",
      platform: map["platform"] ?? "Unknown",
      osVersion: map["os_version"] ?? "Unknown",
      manufacturer: map["manufacturer"] ?? "Unknown",
      model: map["model"] ?? "Unknown",
      appVersion: map["app_version"] ?? "Unknown",
    );
  }

  factory DeviceDetails.empty() {
    return DeviceDetails(
      id: "Unknown",
      label: "Unknown",
      platform: "Unknown",
      osVersion: "Unknown",
      manufacturer: "Unknown",
      model: "Unknown",
      appVersion: "Unknown",
    );
  }

  String toJson() => json.encode(toMap());

  factory DeviceDetails.fromJson(String source) =>
      DeviceDetails.fromMap(Map<String, String>.from(json.decode(source)));
}
