class SensorProfile {
  final String name;
  final double airVoltage;
  const SensorProfile({required this.name, required this.airVoltage});
}
const List<SensorProfile> sensorLibrary = [
  SensorProfile(name: "PSR-11-39-MDSX1", airVoltage: 11.5),
  SensorProfile(name: "AII SF-01", airVoltage: 10.5),
  SensorProfile(name: "Maxtec MAX-12", airVoltage: 13.0),
];