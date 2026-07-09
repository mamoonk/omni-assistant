import 'package:test/test.dart';
import 'package:unification/unification.dart';

void main() {
  test('device round-trips through JSON with all capability kinds', () {
    final device = UniversalDevice(
      id: 'ha:primary:light.hue_go',
      name: 'Hue Go',
      manufacturer: 'Philips',
      model: 'Go',
      origin: const DeviceOrigin(
        type: OriginType.homeAssistant,
        connectionId: 'primary',
        nativeId: 'light.hue_go',
        protocol: 'wifi',
      ),
      roomId: 'Living Room',
      capabilities: [
        PowerSwitchCapability(on: true),
        BrightnessCapability(level: 42),
        ColorRgbCapability(r: 10, g: 20, b: 30),
        ColorTemperatureCapability(mireds: 250),
        TargetTemperatureCapability(target: 22.5, min: 5, max: 30),
        SensorCapability(
            type: CapabilityType.currentTemperature, value: 19.5, unit: '°C'),
        BinarySensorCapability(type: CapabilityType.motion, active: true),
        ModeCapability(
            type: CapabilityType.fanMode, mode: 'low', options: ['low', 'high']),
      ],
    );

    final restored = deviceFromJson(deviceToJson(device));

    expect(restored.id, device.id);
    expect(restored.roomId, device.roomId);
    expect(restored.origin.type, OriginType.homeAssistant);
    expect(restored.capabilities.length, device.capabilities.length);
    expect(restored.currentState, device.currentState);
    expect(restored.capability<PowerSwitchCapability>()!.on, isTrue);
    expect(restored.capability<BrightnessCapability>()!.level, 42);
    expect(restored.capability<TargetTemperatureCapability>()!.max, 30);
    expect(restored.capability<ModeCapability>()!.options, ['low', 'high']);
  });
}
