import 'universal_device.dart';

/// Implemented by each adapter (HA, MQTT, Nexus Bridge, Manual IP).
/// Capabilities call back into this to execute commands, so the model
/// package stays free of transport code.
abstract class DeviceController {
  Future<void> sendCommand(
    UniversalDevice device,
    String capabilityType,
    dynamic value,
  );
}
