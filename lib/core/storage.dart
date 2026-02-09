import 'package:shared_preferences/shared_preferences.dart';
class SentryStorage {
  static const String _keyCalMv = "calibration_mv";
  static Future<void> saveCalibration(double mv) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCalMv, mv);
  }
  static Future<double?> getCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyCalMv);
  }
  static Future<void> saveSensor(String name) async {}
}
