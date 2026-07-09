import 'package:unification/unification.dart';

const _origin = DeviceOrigin(
  type: OriginType.homeAssistant,
  connectionId: 'mock',
  nativeId: 'mock',
  protocol: 'wifi',
);

/// Hardcoded devices proving the UI concept before real hardware (§9.4).
List<UniversalDevice> buildMockDevices() => [
      UniversalDevice(
        id: 'mock:hue_go',
        name: 'Hue Go',
        manufacturer: 'Philips',
        model: 'Hue Go',
        origin: _origin,
        roomId: 'Living Room',
        capabilities: [
          PowerSwitchCapability(on: true),
          BrightnessCapability(level: 80),
          ColorTemperatureCapability(mireds: 320),
          ColorRgbCapability(r: 255, g: 180, b: 90),
        ],
      ),
      UniversalDevice(
        id: 'mock:ceiling',
        name: 'Ceiling Light',
        origin: _origin,
        roomId: 'Living Room',
        capabilities: [
          PowerSwitchCapability(),
          BrightnessCapability(level: 40),
        ],
      ),
      UniversalDevice(
        id: 'mock:coffee',
        name: 'Coffee Maker',
        origin: _origin,
        roomId: 'Kitchen',
        capabilities: [PowerSwitchCapability()],
      ),
      UniversalDevice(
        id: 'mock:washer_plug',
        name: 'Washer Plug',
        origin: _origin,
        roomId: 'Kitchen',
        capabilities: [
          PowerSwitchCapability(on: true),
          SensorCapability(type: CapabilityType.power, value: 480, unit: 'W'),
          SensorCapability(
              type: CapabilityType.energy, value: 12.4, unit: 'kWh'),
        ],
      ),
      UniversalDevice(
        id: 'mock:front_door',
        name: 'Front Door',
        origin: _origin,
        roomId: 'Hallway',
        capabilities: [
          BinarySensorCapability(type: CapabilityType.contact),
          SensorCapability(type: CapabilityType.battery, value: 87, unit: '%'),
        ],
      ),
      UniversalDevice(
        id: 'mock:hall_motion',
        name: 'Hallway Motion',
        origin: _origin,
        roomId: 'Hallway',
        capabilities: [
          BinarySensorCapability(type: CapabilityType.motion, active: true),
        ],
      ),
      UniversalDevice(
        id: 'mock:thermostat',
        name: 'Thermostat',
        origin: _origin,
        roomId: 'Living Room',
        capabilities: [
          PowerSwitchCapability(on: true),
          TargetTemperatureCapability(target: 21.5),
          SensorCapability(
              type: CapabilityType.currentTemperature, value: 20.3, unit: '°C'),
          ModeCapability(
            type: CapabilityType.fanMode,
            mode: 'auto',
            options: ['auto', 'low', 'high'],
          ),
        ],
      ),
      UniversalDevice(
        id: 'mock:bedroom_temp',
        name: 'Bedroom Sensor',
        origin: _origin,
        roomId: 'Bedroom',
        capabilities: [
          SensorCapability(
              type: CapabilityType.currentTemperature, value: 19.1, unit: '°C'),
          SensorCapability(type: CapabilityType.humidity, value: 46, unit: '%'),
        ],
      ),
    ];
