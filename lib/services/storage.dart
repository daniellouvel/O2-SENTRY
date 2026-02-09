import 'package:shared_preferences/shared_preferences.dart';

class SentryStorage {
  // Clés de stockage
  static const String _keySensorName = "selected_sensor_name";
  static const String _keyCalMv = "calibration_mv";

  // Sauvegarder le profil de sonde
  static Future<void> saveSensor(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySensorName, name);
  }

  // Récupérer le nom de la sonde sauvegardée
  static Future<String?> getSensor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySensorName);
  }

  // Sauvegarder la tension de calibration (mV à l'air)
  static Future<void> saveCalibration(double mv) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCalMv, mv);
  }

  // Récupérer la tension de calibration
  static Future<double?> getCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyCalMv);
  }
}
