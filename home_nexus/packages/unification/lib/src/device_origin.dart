enum OriginType { homeAssistant, nexusBridge, mqtt, manualIp }

class DeviceOrigin {
  final OriginType type;

  /// Identifies which connection instance owns this device
  /// (a user can have multiple HA instances or brokers).
  final String connectionId;

  /// The id the source system uses, e.g. HA entity_id or Zigbee IEEE address.
  final String nativeId;

  /// zigbee, zwave, thread, wifi, bluetooth, unknown
  final String protocol;

  const DeviceOrigin({
    required this.type,
    required this.connectionId,
    required this.nativeId,
    this.protocol = 'unknown',
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'connectionId': connectionId,
        'nativeId': nativeId,
        'protocol': protocol,
      };

  factory DeviceOrigin.fromJson(Map<String, dynamic> json) => DeviceOrigin(
        type: OriginType.values.byName(json['type'] as String),
        connectionId: json['connectionId'] as String,
        nativeId: json['nativeId'] as String,
        protocol: json['protocol'] as String? ?? 'unknown',
      );
}
