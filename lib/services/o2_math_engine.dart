class O2MathEngine {
  static double calculateFO2(double currentMv, double calMv) {
    if (calMv == 0) return 20.9;
    return (currentMv / calMv) * 20.9;
  }
  static double calculateMOD(double fo2, double ppO2Limit) {
    if (fo2 <= 0) return 0;
    return ((ppO2Limit / (fo2 / 100)) - 1) * 10;
  }
}