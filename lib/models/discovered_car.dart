class DiscoveredCar {
  final String deviceId;
  final String ip;
  final DateTime lastSeen;
  final String? alias;

  const DiscoveredCar({
    required this.deviceId,
    required this.ip,
    required this.lastSeen,
    this.alias,
  });

  String get displayName => alias?.isNotEmpty == true
      ? alias!
      : 'RC-CAR-${deviceId.substring(deviceId.length - 4)}';

  DiscoveredCar copyWith({String? ip, DateTime? lastSeen, String? alias}) {
    return DiscoveredCar(
      deviceId: deviceId,
      ip: ip ?? this.ip,
      lastSeen: lastSeen ?? this.lastSeen,
      alias: alias ?? this.alias,
    );
  }
}
