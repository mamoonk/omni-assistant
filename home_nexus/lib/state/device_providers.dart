import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../mock/mock_devices.dart';
import 'history_provider.dart';

/// Mutates capability state locally. Used until a Home Assistant
/// connection is live — the UI only ever talks to DeviceController.
class MockDeviceController implements DeviceController {
  final Ref _ref;
  MockDeviceController(this._ref);

  @override
  Future<void> sendCommand(
    UniversalDevice device,
    String capabilityType,
    dynamic value,
  ) async {
    final cap = device.capabilityOfType(capabilityType);
    switch (cap) {
      case PowerSwitchCapability c:
        c.on = value as bool;
      case BrightnessCapability c:
        c.level = value as int;
      case TargetTemperatureCapability c:
        c.target = value as num;
      case ModeCapability c:
        c.mode = value as String;
      case ColorRgbCapability c:
        final rgb = value as List;
        c.r = rgb[0] as int;
        c.g = rgb[1] as int;
        c.b = rgb[2] as int;
      default:
        return;
    }
    _ref.read(devicesProvider.notifier).touch(device.id);
  }
}

class DevicesNotifier extends Notifier<List<UniversalDevice>> {
  @override
  List<UniversalDevice> build() => buildMockDevices();

  /// Re-emit after in-place capability mutation so widgets rebuild.
  void touch(String deviceId) => state = [...state];

  void upsert(UniversalDevice device) {
    final i = state.indexWhere((d) => d.id == device.id);
    state = i < 0
        ? [...state, device]
        : ([...state]..[i] = device);
    _recordHistory(device);
  }

  void replaceAll(List<UniversalDevice> devices) {
    state = devices;
    devices.forEach(_recordHistory);
  }

  /// Swaps all devices of one origin, keeping other origins intact.
  /// Demo/mock devices are dropped once any real source provides devices.
  void replaceOrigin(OriginType origin, List<UniversalDevice> devices) {
    state = [
      ...state.where((d) =>
          d.origin.type != origin && d.origin.connectionId != 'mock'),
      ...devices,
    ];
    devices.forEach(_recordHistory);
  }

  void _recordHistory(UniversalDevice device) {
    final temp = device.capabilities
        .whereType<SensorCapability>()
        .where((c) => c.type == CapabilityType.currentTemperature)
        .firstOrNull;
    final value = temp?.value;
    if (value != null) {
      ref.read(historyProvider.notifier).record(device.id, value);
    }
  }
}

final devicesProvider =
    NotifierProvider<DevicesNotifier, List<UniversalDevice>>(
        DevicesNotifier.new);

/// Ordered room list derived from devices; drives dashboard tabs.
final roomsProvider = Provider<List<String>>((ref) {
  final rooms = ref
      .watch(devicesProvider)
      .map((d) => d.roomId)
      .toSet()
      .toList()
    ..sort();
  return rooms;
});
